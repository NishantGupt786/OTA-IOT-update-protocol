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
        # Start new container with a new temporary name
        NEW_CONTAINER="${CONTAINER_NAME}_new"
        echo "Existing container running—starting new container as $NEW_CONTAINER."
        sudo docker run -d --name "$NEW_CONTAINER" "$IMAGE_NAME"
        # Wait for a short moment; optionally, implement health check here
        sleep 2
        echo "Stopping old container $CONTAINER_NAME..."
        sudo docker stop "$CONTAINER_NAME"
        echo "Removing old container $CONTAINER_NAME..."
        sudo docker rm "$CONTAINER_NAME"
        echo "Renaming new container $NEW_CONTAINER to $CONTAINER_NAME..."
        sudo docker rename "$NEW_CONTAINER" "$CONTAINER_NAME"
        echo "Container successfully updated with no downtime."
    else
        # Start fresh if no running container
        sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        sudo docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"
        echo "Started new container from scratch."
    fi
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Update complete. Local version.yaml updated."

    # Remove all containers except the active one
    for c in $(sudo docker ps -a --format '{{.ID}} {{.Names}}' | grep -v "^$CONTAINER_NAME$" | awk '{print $1}'); do
        sudo docker rm -f "$c" || true
    done

    # Remove dangling images (untagged, unused)
    sudo docker image prune -f

    # Remove all old images matching current image name but not currently used
    ACTIVE_IMAGE_ID=$(sudo docker inspect --format '{{.Image}}' "$CONTAINER_NAME")
    for img in $(sudo docker images --filter=reference="${IMAGE_NAME}" --quiet | grep -v "$ACTIVE_IMAGE_ID"); do
        sudo docker rmi -f "$img" || true
    done

else
    echo "No update needed. Remote version is not newer than local."
fi
