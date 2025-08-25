#!/usr/bin/env python3

import click
import os
import yaml
import subprocess
import sys
from pathlib import Path
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt, Confirm
from rich.progress import Progress, SpinnerColumn, TextColumn
import tempfile
import glob

console = Console()

# Global config file location
CONFIG_FILE = Path.home() / ".iot-ota-config.yaml"
ANSIBLE_INVENTORY = "inventory.yaml"

class Config:
    """Manages global configuration for the CLI tool."""
    def __init__(self):
        self.data = self.load_config()

    def load_config(self):
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                return yaml.safe_load(f) or {}
        return {}

    def save_config(self):
        CONFIG_FILE.parent.mkdir(exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            yaml.dump(self.data, f, default_flow_style=False)

    def get(self, key, default=None):
        return self.data.get(key, default)

    def set(self, key, value):
        self.data[key] = value
        self.save_config()

config = Config()

def _run_ansible_playbook():
    """Internal function to run the setup/trigger playbook."""
    if not load_inventory().get("edge_devices", {}).get("hosts"):
        console.print("[red]No devices configured. Use 'iot-ota devices add' first.[/red]")
        sys.exit(1)
    
    missing_files = [f for f in ["edge_deploy.sh", "ota_public.pem"] if not Path(f).exists()]
    if missing_files:
        console.print(f"[red]Missing required files: {', '.join(missing_files)}. Run 'iot-ota init' first.[/red]")
        sys.exit(1)
    
    create_setup_playbook()
    
    try:
        console.print("Running Ansible playbook...")
        result = subprocess.run(
            ["ansible-playbook", "-i", ANSIBLE_INVENTORY, "setup_devices.yaml", "-v"],
            capture_output=True, text=True
        )
        
        if result.returncode == 0:
            return True
        else:
            console.print(f"[red]Ansible command failed (return code: {result.returncode}):[/red]")
            console.print(result.stdout)
            if result.stderr: console.print(f"[red]STDERR: {result.stderr}[/red]")
            sys.exit(1)
            
    except FileNotFoundError:
        console.print("[red]Error: 'ansible-playbook' command not found.[/red]")
        console.print("[yellow]Please ensure Ansible is installed and in your system's PATH.[/yellow]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]An error occurred while running Ansible: {e}[/red]")
        sys.exit(1)

@click.group()
@click.version_option(version="1.0.0")
def cli():
    """A CLI tool for managing and deploying Over-The-Air (OTA) updates to IoT devices."""
    pass

def get_program_files_by_language(language):
    """Get a list of program files in the current directory based on language."""
    patterns = {
        "cpp": ["*.cpp", "*.cc", "*.cxx"],
        "c": ["*.c"],
        "python": ["*.py"],
        "java": ["*.java", "*.jar"]
    }
    
    files = []
    for pattern in patterns.get(language, []):
        files.extend(glob.glob(pattern))
    
    return sorted(files)

def get_program_file_basename(program_file):
    """Get the basename for the program file, without its extension."""
    return program_file.rsplit(".", 1)[0] if "." in program_file else program_file

@cli.command()
def init():
    """Initialize a new IoT OTA project in the current directory."""
    console.print("[bold green]🚀 Initializing IoT OTA Project[/bold green]")
    
    if Path("iot-ota.yaml").exists():
        if not Confirm.ask("[yellow]Project already initialized. Overwrite configuration?"):
            console.print("[red]Initialization cancelled.[/red]")
            return
    
    project_config = {}
    
    # --- Collect Project Information ---
    languages = ["cpp", "c", "python", "java"]
    project_config["language"] = Prompt.ask(
        "Select programming language", 
        choices=languages, 
        default="python"
    )
    
    available_files = get_program_files_by_language(project_config["language"])
    
    if available_files:
        console.print(f"\n[cyan]Available {project_config['language']} files in this directory:[/cyan]")
        for i, file in enumerate(available_files, 1):
            console.print(f"  {i}. {file}")
        console.print(f"  {len(available_files) + 1}. <Enter custom filename>")
        
        choice = Prompt.ask(
            "Select your main program file",
            choices=[str(i) for i in range(1, len(available_files) + 2)],
            default="1"
        )
        
        if int(choice) <= len(available_files):
            project_config["program_file"] = available_files[int(choice) - 1]
        else:
            default_ext = {"cpp": ".cpp", "c": ".c", "python": ".py", "java": ".jar"}
            suggested_name = f"main{default_ext.get(project_config['language'], '')}"
            project_config["program_file"] = Prompt.ask(
                "Enter your main program filename",
                default=suggested_name
            )
    else:
        default_ext = {"cpp": ".cpp", "c": ".c", "python": ".py", "java": ".jar"}
        suggested_name = f"main{default_ext.get(project_config['language'], '')}"
        console.print(f"[yellow]No {project_config['language']} files found. Please provide a filename.[/yellow]")
        project_config["program_file"] = Prompt.ask(
            "Enter your main program filename",
            default=suggested_name
        )

    devices = ["rpi3b", "jetsonnano", "jetsonorin", "x86_64"]
    project_config["edge_device"] = Prompt.ask(
        "Select target edge device", 
        choices=devices, 
        default="rpi3b"
    )
    
    project_config["s3_bucket"] = Prompt.ask(
        "Enter S3 bucket name for updates",
        default="iot-ota-rtupdate"
    )
    
    # --- Create Project Config ---
    project_config["version"] = "1.0.0"
    project_config["docker_image_tag"] = "1.0"
    project_config["program_basename"] = get_program_file_basename(project_config["program_file"])
    
    with open("iot-ota.yaml", "w") as f:
        yaml.dump(project_config, f, default_flow_style=False)
    
    # --- Run the initialization script ---
    console.print("\n[yellow]Running project setup script...[/yellow]")
    run_init_script(project_config)
    
    console.print("\n[bold green]✅ Project initialized successfully![/bold green]")
    console.print(f"[cyan]Project config saved to: [bold]iot-ota.yaml[/bold][/cyan]")
    console.print(f"[cyan]Next steps:[/cyan]")
    console.print(f"  1. Configure your devices: [bold]iot-ota devices add[/bold]")
    console.print(f"  2. Setup devices for OTA: [bold]iot-ota devices setup[/bold]")
    console.print(f"  3. Build and deploy updates: [bold]iot-ota deploy[/bold]")

def run_init_script(project_config):
    """Creates and runs the legacy bash script to generate project files."""
    init_script_content = get_original_init_script()
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False, encoding='utf-8') as f:
        f.write(init_script_content)
        script_path = f.name
    
    try:
        os.chmod(script_path, 0o755)
        
        lang_map = {"cpp": "1", "c": "2", "python": "3", "java": "4"}
        device_map = {"rpi3b": "1", "jetsonnano": "2", "jetsonorin": "3", "x86_64": "4"}
        
        responses = [
            lang_map[project_config["language"]],
            device_map[project_config["edge_device"]],
            project_config["program_file"]
        ]
        
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            task = progress.add_task("Generating Dockerfile, keys, and scripts...", total=None)
            
            process = subprocess.Popen(
                [script_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd="."
            )
            
            input_data = "\n".join(responses) + "\n"
            stdout, stderr = process.communicate(input=input_data, timeout=300) # 5-min timeout
            
            if process.returncode != 0:
                progress.stop()
                console.print(f"[red]Error running setup script (return code: {process.returncode}):[/red]")
                if stderr: console.print(f"[red]STDERR: {stderr}[/red]")
                if stdout: console.print(f"[yellow]STDOUT: {stdout}[/yellow]")
                sys.exit(1)
            
            progress.update(task, description="✅ Project setup complete")
    
    except subprocess.TimeoutExpired:
        console.print("[red]Error: The setup script timed out.[/red]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]An unexpected error occurred: {e}[/red]")
        sys.exit(1)
    finally:
        if os.path.exists(script_path):
            os.unlink(script_path)

@cli.command()
@click.option('--no-upload', is_flag=True, help="Build the Docker image locally without uploading.")
def build(no_upload):
    """Build the Docker image and prepare for deployment."""
    console.print("[bold blue]🔨 Building project...[/bold blue]")
    
    if not Path("iot-ota.yaml").exists():
        console.print("[red]Error: Not in an IoT OTA project directory. Run 'iot-ota init' first.[/red]")
        sys.exit(1)

    script_to_run = "./redeploy.sh"
    if not Path(script_to_run).exists():
        console.print(f"[red]Error: {script_to_run} not found. Run 'iot-ota init' first.[/red]")
        sys.exit(1)

    command = [script_to_run]
    if no_upload:
        command.append("--no-upload")

    try:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            task_description = "Building local Docker image..." if no_upload else "Building and uploading to S3..."
            task = progress.add_task(task_description, total=None)
            
            result = subprocess.run(
                command, capture_output=True, text=True, cwd="."
            )
            
            if result.returncode == 0:
                console.print(f"[bold green]✅ Build successful![/bold green]")
            else:
                progress.stop()
                console.print(f"[red]Build failed (return code: {result.returncode}):[/red]")
                if result.stderr: console.print(f"[red]{result.stderr}[/red]")
                if result.stdout: console.print(f"[yellow]{result.stdout}[/yellow]")
                sys.exit(1)
                
    except Exception as e:
        console.print(f"[red]Error during build process: {e}[/red]")
        sys.exit(1)

@cli.group()
def devices():
    """Manage edge devices in the Ansible inventory."""
    pass

@devices.command("add")
def devices_add():
    """Add a new edge device to the inventory."""
    console.print("[bold green]📱 Adding new edge device[/bold green]")
    
    device_info = {
        "name": Prompt.ask("Device name (e.g., living-room-pi)"),
        "host": Prompt.ask("Device IP or hostname"),
        "user": Prompt.ask("SSH username", default="pi"),
        "port": int(Prompt.ask("SSH port", default="22")),
        "ssh_key": Prompt.ask("Path to SSH private key (optional, leave blank for password auth)"),
    }
    
    inventory = load_inventory()
    
    if "edge_devices" not in inventory:
        inventory["edge_devices"] = {"hosts": {}}
    
    inventory["edge_devices"]["hosts"][device_info["name"]] = {
        "ansible_host": device_info["host"],
        "ansible_user": device_info["user"],
        "ansible_port": device_info["port"],
    }
    
    if device_info["ssh_key"]:
        inventory["edge_devices"]["hosts"][device_info["name"]]["ansible_ssh_private_key_file"] = device_info["ssh_key"]
    
    save_inventory(inventory)
    console.print(f"[green]✅ Device '[bold]{device_info['name']}[/bold]' added successfully![/green]")

@devices.command("list")
def devices_list():
    """List all configured edge devices."""
    inventory = load_inventory()
    
    if not inventory.get("edge_devices", {}).get("hosts"):
        console.print("[yellow]No devices configured. Use 'iot-ota devices add' to add one.[/yellow]")
        return
    
    table = Table(title="Configured Edge Devices")
    table.add_column("Name", style="cyan", no_wrap=True)
    table.add_column("Host", style="green")
    table.add_column("User", style="yellow")
    table.add_column("Port", style="blue")
    
    for name, details in inventory["edge_devices"]["hosts"].items():
        table.add_row(
            name,
            details.get("ansible_host", "N/A"),
            details.get("ansible_user", "N/A"),
            str(details.get("ansible_port", "N/A"))
        )
    
    console.print(table)

@devices.command("remove")
@click.argument('device_name', required=False)
def devices_remove(device_name):
    """Remove an edge device from the inventory."""
    inventory = load_inventory()
    
    if not inventory.get("edge_devices", {}).get("hosts"):
        console.print("[yellow]No devices to remove.[/yellow]")
        return
    
    device_names = list(inventory["edge_devices"]["hosts"].keys())
    
    if not device_name:
        console.print("[cyan]Available devices:[/cyan]")
        for i, name in enumerate(device_names, 1):
            console.print(f"  {i}. {name}")
        
        choice = Prompt.ask(
            "Select device to remove",
            choices=[str(i) for i in range(1, len(device_names) + 1)]
        )
        device_name = device_names[int(choice) - 1]
    
    if device_name not in device_names:
        console.print(f"[red]Error: Device '{device_name}' not found.[/red]")
        sys.exit(1)

    if Confirm.ask(f"Are you sure you want to remove device '[bold]{device_name}[/bold]'?"):
        del inventory["edge_devices"]["hosts"][device_name]
        save_inventory(inventory)
        console.print(f"[green]✅ Device '{device_name}' removed successfully![/green]")

@devices.command("setup")
def devices_setup():
    """Deploy initial OTA agent to devices for the first time."""
    console.print("[bold blue]🛰️  Performing first-time setup for devices...[/bold blue]")
    success = _run_ansible_playbook()
    if success:
        console.print("[bold green]✅ Device setup and initial deployment successful![/bold green]")

@cli.command()
def trigger():
    """Trigger an update check on all devices without building a new version."""
    console.print("[bold blue]📡 Triggering update on all devices...[/bold blue]")
    success = _run_ansible_playbook()
    if success:
        console.print("[bold green]✅ Update trigger signal sent successfully![/bold green]")
        console.print("[dim]Devices will now check S3 for the latest version.[/dim]")

@cli.command()
def deploy():
    """A full workflow: build, upload, and deploy to all devices."""
    console.print("[bold green]🚀 Starting full deployment cycle...[/bold green]")
    
    # Step 1: Build and Upload
    console.print("\n[cyan]Step 1: Building project and uploading to S3...[/cyan]")
    try:
        ctx = click.Context(build, info_name='build')
        ctx.invoke(build, no_upload=False)
    except SystemExit as e:
        if e.code != 0:
            console.print("[red]Build step failed. Aborting deployment.[/red]")
            sys.exit(1)
    
    # Step 2: Trigger update on devices
    console.print("\n[cyan]Step 2: Triggering update on all devices...[/cyan]")
    try:
        ctx = click.Context(trigger, info_name='trigger')
        ctx.invoke(trigger)
    except SystemExit as e:
        if e.code != 0:
            console.print("[red]Device deployment step failed.[/red]")
            sys.exit(1)
    
    console.print("\n[bold green]🎉 Full deployment cycle complete![/bold green]")

@cli.command()
def status():
    """Show current project configuration and status."""
    console.print("[bold blue]📊 Project Status[/bold blue]")
    
    if not Path("iot-ota.yaml").exists():
        console.print("[red]Not in an IoT OTA project directory. Run 'iot-ota init' to start.[/red]")
        return
    
    with open("iot-ota.yaml", "r") as f:
        project_config = yaml.safe_load(f)
    
    table = Table(title="Project Configuration (from iot-ota.yaml)")
    table.add_column("Setting", style="cyan")
    table.add_column("Value", style="green")
    for key, value in project_config.items():
        table.add_row(key, str(value))
    console.print(table)
    
    devices_list()

@cli.command()
@click.option('--full', is_flag=True, help="Remove all generated project files, not just temporary ones.")
def clean(full):
    """Clean up temporary or all generated files."""
    files_to_clean = ["*.tar", "*.sig", "*.sha256", "setup_devices.yaml"]
    
    if full:
        console.print("[bold red]🧹 Performing full clean...[/bold red]")
        files_to_clean.extend([
            "iot-ota.yaml", "inventory.yaml", "Dockerfile", 
            "edge_deploy.sh", "redeploy.sh", "ota_private.pem", 
            "ota_public.pem", "version.yaml"
        ])
    else:
        console.print("[bold yellow]🧹 Cleaning temporary files...[/bold yellow]")

    cleaned_files = []
    for pattern in files_to_clean:
        for file in glob.glob(pattern):
            try:
                os.remove(file)
                cleaned_files.append(file)
            except Exception as e:
                console.print(f"[red]Failed to remove {file}: {e}[/red]")
    
    if cleaned_files:
        console.print(f"[green]✅ Cleaned up {len(cleaned_files)} files:[/green]")
        for file in cleaned_files:
            console.print(f"  - [dim]{file}[/dim]")
    else:
        console.print("[yellow]No generated files to clean.[/yellow]")

def load_inventory():
    """Load the Ansible inventory file."""
    if Path(ANSIBLE_INVENTORY).exists():
        with open(ANSIBLE_INVENTORY, "r") as f:
            return yaml.safe_load(f) or {}
    return {}

def save_inventory(inventory):
    """Save the Ansible inventory file."""
    with open(ANSIBLE_INVENTORY, "w") as f:
        yaml.dump(inventory, f, default_flow_style=False)

def create_setup_playbook():
    """Create the Ansible playbook for device setup."""
    playbook_content = f"""---
- name: Deploy OTA Agent and Trigger Update
  hosts: edge_devices
  gather_facts: no
  become: no # Assumes user has docker permissions
  tasks:
    - name: Get project directory name from localhost
      delegate_to: localhost
      run_once: true
      set_fact:
        project_dir_name: "{os.path.basename(os.getcwd())}"

    - name: Ensure project directory exists on device
      ansible.builtin.file:
        path: "~/{{{{ project_dir_name }}}}"
        state: directory
        mode: '0755'

    - name: Copy public key for signature verification
      ansible.builtin.copy:
        src: ota_public.pem
        dest: "~/{{{{ project_dir_name }}}}/ota_public.pem"
        mode: '0644'

    - name: Copy the OTA deployment script to the device
      ansible.builtin.copy:
        src: edge_deploy.sh
        dest: "~/edge_deploy.sh"
        mode: '0755'

    - name: Run the OTA deployment script
      ansible.builtin.shell:
        cmd: "cd ~ && ./edge_deploy.sh"
        warn: no # Suppress warnings about using shell over command
      register: deployment_result
      changed_when: "'New version found' in deployment_result.stdout"

    - name: Show deployment output
      ansible.builtin.debug:
        msg: "{{{{ deployment_result.stdout_lines }}}}"

    - name: Show deployment errors (if any)
      ansible.builtin.debug:
        msg: "{{{{ deployment_result.stderr_lines }}}}"
      when: deployment_result.stderr | length > 0
"""
    with open("setup_devices.yaml", "w") as f:
        f.write(playbook_content)

def get_original_init_script():
    """Returns the content of the legacy bash script used for initialization."""
    return r'''#!/bin/bash
set -e

# This script is not meant to be run directly. It's called by the Python CLI.

echo "1. cpp"
echo "2. c"
echo "3. python"
echo "4. java"
read -p "Choose programming language (1-4): " lang_choice
case $lang_choice in
    1) LANGUAGE="cpp" ;;
    2) LANGUAGE="c" ;;
    3) LANGUAGE="python" ;;
    4) LANGUAGE="java" ;;
    *) echo "Invalid choice." ; exit 1 ;;
esac

echo "1. rpi3b"
echo "2. jetsonnano"
echo "3. jetsonorin"
echo "4. x86_64"
read -p "Choose edge device (1-4): " device_choice
case $device_choice in
    1) EDGE_DEVICE="rpi3b" ;;
    2) EDGE_DEVICE="jetsonnano" ;;
    3) EDGE_DEVICE="jetsonorin" ;;
    4) EDGE_DEVICE="x86_64" ;;
    *) echo "Invalid choice." ; exit 1 ;;
esac

read -p "Enter the name of your main program file (e.g., main.cpp, app.py): " PRG_FILE

# --- Derive variables ---
EXTENSION="${PRG_FILE##*.}"
PRG_FILE_BASENAME=$(basename "$PRG_FILE" .${EXTENSION})

case "$EDGE_DEVICE" in
    rpi3b)      PLATFORM="linux/arm/v7" ;;
    jetsonnano) PLATFORM="linux/arm64" ;;
    jetsonorin) PLATFORM="linux/arm64" ;;
    x86_64)     PLATFORM="linux/amd64" ;;
esac

# --- Configuration ---
DOCKER_IMAGE_TAG="1.0"
S3_BUCKET="iot-ota-rtupdate" # This will be overwritten by config, but set a default
PRIVATE_KEY="ota_private.pem"
PUBLIC_KEY="ota_public.pem"
IMAGE_TAR="${PRG_FILE_BASENAME}.tar"
IMAGE_SIG="${IMAGE_TAR}.sig"
VERSION_FILE="version.yaml"
VERSION_SIG="version.yaml.sig"
IMAGE_NAME="${PRG_FILE_BASENAME}:${DOCKER_IMAGE_TAG}"
DIRECTORY_NAME=$(basename "$PWD")

# --- Generate Dockerfile ---
if [[ -f Dockerfile ]]; then
    echo "Dockerfile exists. Overwriting."
    rm Dockerfile
fi

case "$LANGUAGE" in
    cpp)
        BASE="arm32v7/debian:bullseye-slim" && [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/debian:bullseye-slim"
        cat > Dockerfile <<EOF
FROM ${BASE}
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y build-essential && g++ ${PRG_FILE} -o ${PRG_FILE_BASENAME}
CMD ["./${PRG_FILE_BASENAME}"]
EOF
        ;;
    c)
        BASE="arm32v7/debian:bullseye-slim" && [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/debian:bullseye-slim"
        cat > Dockerfile <<EOF
FROM ${BASE}
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y build-essential && gcc ${PRG_FILE} -o ${PRG_FILE_BASENAME}
CMD ["./${PRG_FILE_BASENAME}"]
EOF
        ;;
    python)
        BASE="arm32v7/python:3.9-slim" && [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/python:3.9-slim"
        cat > Dockerfile <<EOF
FROM ${BASE}
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt || true
CMD ["python", "-u", "${PRG_FILE}"]
EOF
        ;;
    java)
        BASE_BUILDER="arm32v7/openjdk:11-jdk-slim" && [[ "$PLATFORM" == "linux/arm64" ]] && BASE_BUILDER="arm64v8/openjdk:11-jdk-slim"
        BASE_RUNTIME="arm32v7/openjdk:11-jre-slim" && [[ "$PLATFORM" == "linux/arm64" ]] && BASE_RUNTIME="arm64v8/openjdk:11-jre-slim"
        
        if [[ "$EXTENSION" == "jar" ]]; then
            cat > Dockerfile <<EOF
FROM ${BASE_RUNTIME}
WORKDIR /app
COPY ${PRG_FILE} .
CMD ["java", "-jar", "${PRG_FILE}"]
EOF
        else
            cat > Dockerfile <<EOF
FROM ${BASE_BUILDER} AS builder
WORKDIR /build
COPY . .
RUN javac ${PRG_FILE} -d .

FROM ${BASE_RUNTIME}
WORKDIR /app
COPY --from=builder /build/${PRG_FILE_BASENAME}.class .
CMD ["java", "${PRG_FILE_BASENAME}"]
EOF
        fi
        ;;
esac
echo "Dockerfile created."

# --- Generate Keys ---
if [[ ! -f "$PRIVATE_KEY" ]]; then
    openssl genpkey -algorithm RSA -out $PRIVATE_KEY -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in $PRIVATE_KEY -out $PUBLIC_KEY
    echo "Generated new RSA key pair."
fi

# --- Generate edge_deploy.sh ---
cat > edge_deploy.sh <<EOF
#!/bin/bash
set -e

S3_BASE_URL="https://${S3_BUCKET}.s3.amazonaws.com/${DIRECTORY_NAME}"
WORKDIR="${DIRECTORY_NAME}"
PUBLIC_KEY="ota_public.pem"
CONTAINER_NAME="${PRG_FILE_BASENAME}_ota_app"

mkdir -p "\$WORKDIR"
cd "\$WORKDIR"

echo "Checking for updates..."
LOCAL_VERSION_TS="1970-01-01T00:00:00Z" # Assume very old date if no local version exists
if [ -f "version.yaml" ]; then
    LOCAL_VERSION_TS=\$(grep "last_build" "version.yaml" | cut -d'"' -f2)
fi

# Download remote version file to check timestamp
if ! aws s3 cp "\${S3_BASE_URL}/version.yaml" remote_version.yaml --quiet; then
    echo "Could not download remote version file. Is the device configured for AWS?"
    exit 1
fi
REMOTE_VERSION_TS=\$(grep "last_build" remote_version.yaml | cut -d'"' -f2)

if [ "\$REMOTE_VERSION_TS" == "\$LOCAL_VERSION_TS" ]; then
    echo "Already up to date."
    # Ensure container is running if it exists
    if ! docker ps -q -f name="^/\${CONTAINER_NAME}\$" | grep -q .; then
      echo "Container is not running. Starting it..."
      docker start \$CONTAINER_NAME || echo "Failed to start container. It may need a fresh deployment."
    fi
    rm -f remote_version.yaml
    exit 0
fi

echo "New version found (\${REMOTE_VERSION_TS}). Updating..."

# Download all deployment artifacts
aws s3 cp "\${S3_BASE_URL}/${IMAGE_TAR}" "${IMAGE_TAR}" --quiet
aws s3 cp "\${S3_BASE_URL}/${IMAGE_SIG}" "${IMAGE_SIG}" --quiet
aws s3 cp "\${S3_BASE_URL}/${VERSION_SIG}" "remote_version.yaml.sig" --quiet

# --- Verify Signatures ---
echo "Verifying signatures..."
openssl dgst -sha256 -binary remote_version.yaml > remote.sha256
if ! openssl pkeyutl -verify -pubin -inkey "\${PUBLIC_KEY}" -sigfile remote_version.yaml.sig -in remote.sha256; then
    echo "ERROR: Version file signature verification failed!"
    rm -f remote* *.tar *.sig
    exit 1
fi
echo "Version file signature OK."

openssl dgst -sha256 -binary "${IMAGE_TAR}" > image.sha256
if ! openssl pkeyutl -verify -pubin -inkey "\${PUBLIC_KEY}" -sigfile "${IMAGE_SIG}" -in image.sha256; then
    echo "ERROR: Image signature verification failed!"
    rm -f remote* *.tar *.sig image.sha256
    exit 1
fi
echo "Image signature OK."

# --- Deploy ---
echo "Stopping and removing old container..."
if [ \$(docker ps -a -q -f name="^/\${CONTAINER_NAME}\$") ]; then
    docker stop \$CONTAINER_NAME || true
    docker rm \$CONTAINER_NAME || true
fi

echo "Loading new image..."
docker load -i "${IMAGE_TAR}"

echo "Starting new container..."
docker run -d --name \$CONTAINER_NAME --restart always "${IMAGE_NAME}"

mv remote_version.yaml version.yaml
rm -f *.tar *.sig *.sha256
echo "Update successful."
cd ..
EOF
chmod +x edge_deploy.sh
echo "edge_deploy.sh created."

# --- Generate redeploy.sh ---
cat > redeploy.sh <<EOF
#!/bin/bash
set -e
NO_UPLOAD=false
if [ "\$1" == "--no-upload" ]; then
    NO_UPLOAD=true
fi

if [ "\$NO_UPLOAD" = true ]; then
    echo "Building Docker image locally..."
else
    echo "Building and redeploying to S3..."
fi

docker buildx build --platform ${PLATFORM} --no-cache -t ${IMAGE_NAME} --output type=docker .
docker save -o ${IMAGE_TAR} ${IMAGE_NAME}

if [ "\$NO_UPLOAD" = true ]; then
    echo "Build complete. Image '${IMAGE_NAME}' is available locally."
    echo "Tarball saved as '${IMAGE_TAR}'."
    rm -f ${IMAGE_TAR} # Clean up tarball if not uploading
    exit 0
fi

echo "Signing artifacts..."
openssl dgst -sha256 -binary ${IMAGE_TAR} > ${IMAGE_TAR}.sha256
openssl pkeyutl -sign -inkey ${PRIVATE_KEY} -in ${IMAGE_TAR}.sha256 -out ${IMAGE_SIG}

CUR_TS=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"\$CUR_TS\"" > ${VERSION_FILE}
openssl dgst -sha256 -binary ${VERSION_FILE} > ${VERSION_FILE}.sha256
openssl pkeyutl -sign -inkey ${PRIVATE_KEY} -in ${VERSION_FILE}.sha256 -out ${VERSION_SIG}

echo "Uploading to s3://${S3_BUCKET}/${DIRECTORY_NAME}/"
aws s3 cp ${IMAGE_TAR} s3://${S3_BUCKET}/${DIRECTORY_NAME}/${IMAGE_TAR}
aws s3 cp ${IMAGE_SIG} s3://${S3_BUCKET}/${DIRECTORY_NAME}/${IMAGE_SIG}
aws s3 cp ${VERSION_FILE} s3://${S3_BUCKET}/${DIRECTORY_NAME}/${VERSION_FILE}
aws s3 cp ${VERSION_SIG} s3://${S3_BUCKET}/${DIRECTORY_NAME}/${VERSION_SIG}

rm -f *.sha256 *.tar *.sig
echo "Redeployment to S3 successful."
EOF
chmod +x redeploy.sh
echo "redeploy.sh created."
'''

if __name__ == "__main__":
    cli()
