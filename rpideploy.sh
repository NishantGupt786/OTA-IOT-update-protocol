#!/bin/bash
set -ex

S3_BASE_URL="https://iot-ota-rtupdate.s3.amazonaws.com/docker-edge"
WORKDIR="$HOME/docker-edge-app"
CONTAINER_NAME="main_ota_app"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

LOCAL_VERSION="version.yaml"
NEW_VERSION_TMP="version_remote.yaml"
VERSION_SIG="version_remote.yaml.sig"
IMAGE_TAR="main.tar"
IMAGE_SIG="main.tar.sig"
PUBLIC_KEY="ota_public.pem"

# 1. Fetch files
wget -O "$NEW_VERSION_TMP" "$S3_BASE_URL/version.yaml"
wget -O "$VERSION_SIG"     "$S3_BASE_URL/version.yaml.sig"
wget -O "$IMAGE_TAR"       "$S3_BASE_URL/main.tar"
wget -O "$IMAGE_SIG"       "$S3_BASE_URL/main.tar.sig"
wget -O "$PUBLIC_KEY"      "$S3_BASE_URL/ota_public.pem"

# Exit if any file is missing/zero size
for f in "$NEW_VERSION_TMP" "$VERSION_SIG" "$IMAGE_TAR" "$IMAGE_SIG" "$PUBLIC_KEY"; do
    [ -s "$f" ] || { echo "Missing or empty $f"; exit 1; }
done

# 2. Verify version.yaml signature
openssl dgst -sha256 -binary "$NEW_VERSION_TMP" > version.check.sha256
openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY" \
    -in version.check.sha256 \
    -sigfile "$VERSION_SIG"
if [ $? -ne 0 ]; then
    echo "version.yaml signature verification failed!"
    exit 1
fi

# 3. Verify main.tar signature
openssl dgst -sha256 -binary "$IMAGE_TAR" > main.tar.check.sha256
openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY" \
    -in main.tar.check.sha256 \
    -sigfile "$IMAGE_SIG"
if [ $? -ne 0 ]; then
    echo "main.tar signature verification failed!"
    exit 1
fi

rm -f *.sha256

# 4. Update logic
if [ ! -f "$LOCAL_VERSION" ]; then
    echo "No previous version.yaml found. Performing first-time setup."
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name!"
        exit 1
    fi
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
        sudo docker rm -f "$CONTAINER_NAME"
    fi
    sudo docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Initialized local version.yaml."
    exit 0
fi

LAST_LOCAL=$(grep last_build "$LOCAL_VERSION" | awk '{print $2}' | tr -d '"')
LAST_REMOTE=$(grep last_build "$NEW_VERSION_TMP" | awk '{print $2}' | tr -d '"')

if [[ "$LAST_REMOTE" > "$LAST_LOCAL" ]]; then
    echo "Newer version detected. Performing rolling update to minimize downtime."
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name during update!"
        exit 1
    fi
    CONTAINER_RUNNING=$(sudo docker ps --format '{{.Names}}' | grep -x "$CONTAINER_NAME" || true)
    if [ -n "$CONTAINER_RUNNING" ]; then
        NEW_CONTAINER="${CONTAINER_NAME}_new"
        sudo docker run -d --name "$NEW_CONTAINER" "$IMAGE_NAME"
        sleep 2
        sudo docker stop "$CONTAINER_NAME"
        sudo docker rm "$CONTAINER_NAME"
        sudo docker rename "$NEW_CONTAINER" "$CONTAINER_NAME"
    else
        sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        sudo docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"
    fi
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Update complete. Local version.yaml updated."
    # (add any post-update cleanup or logging here)
else
    echo "No update needed. Remote version is not newer than local."
fi
