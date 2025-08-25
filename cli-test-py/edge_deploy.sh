#!/bin/bash
set -e

S3_BASE_URL="https://iot-ota-rtupdate.s3.amazonaws.com/cli-test-py"
WORKDIR="cli-test-py"
PUBLIC_KEY="ota_public.pem"
CONTAINER_NAME="process_ota_app"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Checking for updates..."
LOCAL_VERSION_TS="1970-01-01T00:00:00Z" # Assume very old date if no local version exists
if [ -f "version.yaml" ]; then
    LOCAL_VERSION_TS=$(grep "last_build" "version.yaml" | cut -d'"' -f2)
fi

# Download remote version file to check timestamp
if ! aws s3 cp "${S3_BASE_URL}/version.yaml" remote_version.yaml --quiet; then
    echo "Could not download remote version file. Is the device configured for AWS?"
    exit 1
fi
REMOTE_VERSION_TS=$(grep "last_build" remote_version.yaml | cut -d'"' -f2)

if [ "$REMOTE_VERSION_TS" == "$LOCAL_VERSION_TS" ]; then
    echo "Already up to date."
    # Ensure container is running if it exists
    if ! docker ps -q -f name="^/${CONTAINER_NAME}$" | grep -q .; then
      echo "Container is not running. Starting it..."
      docker start $CONTAINER_NAME || echo "Failed to start container. It may need a fresh deployment."
    fi
    rm -f remote_version.yaml
    exit 0
fi

echo "New version found (${REMOTE_VERSION_TS}). Updating..."

# Download all deployment artifacts
aws s3 cp "${S3_BASE_URL}/process.tar" "process.tar" --quiet
aws s3 cp "${S3_BASE_URL}/process.tar.sig" "process.tar.sig" --quiet
aws s3 cp "${S3_BASE_URL}/version.yaml.sig" "remote_version.yaml.sig" --quiet

# --- Verify Signatures ---
echo "Verifying signatures..."
openssl dgst -sha256 -binary remote_version.yaml > remote.sha256
if ! openssl pkeyutl -verify -pubin -inkey "${PUBLIC_KEY}" -sigfile remote_version.yaml.sig -in remote.sha256; then
    echo "ERROR: Version file signature verification failed!"
    rm -f remote* *.tar *.sig
    exit 1
fi
echo "Version file signature OK."

openssl dgst -sha256 -binary "process.tar" > image.sha256
if ! openssl pkeyutl -verify -pubin -inkey "${PUBLIC_KEY}" -sigfile "process.tar.sig" -in image.sha256; then
    echo "ERROR: Image signature verification failed!"
    rm -f remote* *.tar *.sig image.sha256
    exit 1
fi
echo "Image signature OK."

# --- Deploy ---
echo "Stopping and removing old container..."
if [ $(docker ps -a -q -f name="^/${CONTAINER_NAME}$") ]; then
    docker stop $CONTAINER_NAME || true
    docker rm $CONTAINER_NAME || true
fi

echo "Loading new image..."
docker load -i "process.tar"

echo "Starting new container..."
docker run -d --name $CONTAINER_NAME --restart always "process:1.0"

mv remote_version.yaml version.yaml
rm -f *.tar *.sig *.sha256
echo "Update successful."
cd ..
