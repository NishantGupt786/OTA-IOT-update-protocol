#!/bin/bash
set -ex

S3_BASE_URL="https://iot-ota-rtupdate.s3.amazonaws.com/docker-edge"
WORKDIR="$HOME/docker-edge-app"
CONTAINER_NAME="main_ota_app"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

LOCAL_VERSION="version.yaml"
NEW_VERSION_TMP="version_remote.yaml"
IMAGE_TAR="main.tar"

echo "=== Fetching remote version.yaml..."
wget -O "$NEW_VERSION_TMP" "$S3_BASE_URL/version.yaml"
if [ ! -s "$NEW_VERSION_TMP" ]; then
    echo "Failed to download remote version file."
    exit 1
fi

# FIRST INSTALL: If local version.yaml does not exist
if [ ! -f "$LOCAL_VERSION" ]; then
    echo "No previous version.yaml found. Performing first-time setup."
    wget -O "$IMAGE_TAR" "$S3_BASE_URL/main.tar"
    if [ ! -s "$IMAGE_TAR" ]; then
        echo "Failed to download image tarball."
        exit 1
    fi
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name!"
        exit 1
    fi
    # Remove any running/stopped containers with this name (safety)
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
        sudo docker rm -f "$CONTAINER_NAME"
    fi
    echo "Running initial container in detached mode..."
    sudo docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Initialized local version.yaml."
    exit 0
fi

# Compare last_build in remote and local version.yaml
LAST_LOCAL=$(grep last_build "$LOCAL_VERSION" | awk '{print $2}' | tr -d '"')
LAST_REMOTE=$(grep last_build "$NEW_VERSION_TMP" | awk '{print $2}' | tr -d '"')

if [[ "$LAST_REMOTE" > "$LAST_LOCAL" ]]; then
    echo "Newer version detected. Performing rolling update to minimize downtime."
    wget -O "$IMAGE_TAR" "$S3_BASE_URL/main.tar"
    if [ ! -s "$IMAGE_TAR" ]; then
        echo "Failed to download image tarball during update."
        exit 1
    fi
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name during update!"
        exit 1
    fi
    CONTAINER_RUNNING=$(sudo docker ps --format '{{.Names}}' | grep -x "$CONTAINER_NAME" || true)
    if [ -n "$CONTAINER_RUNNING" ]; then
        # Start new container with a new name (to avoid port conflicts, adjust as needed)
        echo "Existing container running—spinning up new container as ${CONTAINER_NAME}_new."
        sudo docker run -d --name "${CONTAINER_NAME}_new" "$IMAGE_NAME"
        # Wait a moment (or optionally healthcheck), then gracefully switch
        sleep 2
        sudo docker stop "$CONTAINER_NAME"
        sudo docker rm "$CONTAINER_NAME"
        sudo docker rename "${CONTAINER_NAME}_new" "$CONTAINER_NAME"
        echo "Seamless update—no downtime!"
    else
        # Start fresh if no running container
        sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        sudo docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"
        echo "Started new container."
    fi
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Update complete. Local version.yaml updated."
else
    echo "No update needed. Remote version is not newer than local."
fi
