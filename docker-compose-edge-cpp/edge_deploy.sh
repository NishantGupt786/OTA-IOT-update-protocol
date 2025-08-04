#!/bin/bash
set -ex

S3_BASE_URL="https://iot-ota-rtupdate.s3.amazonaws.com/docker-compose-edge-cpp"
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

curl -sSf -o "$NEW_VERSION_TMP" "$S3_BASE_URL/$LOCAL_VERSION"
curl -sSf -o "$VERSION_SIG"     "$S3_BASE_URL/$VERSION_SIG"
curl -sSf -o "$IMAGE_TAR"       "$S3_BASE_URL/$IMAGE_TAR"
curl -sSf -o "$IMAGE_SIG"       "$S3_BASE_URL/$IMAGE_SIG"
curl -sSf -o "$PUBLIC_KEY"      "$S3_BASE_URL/$PUBLIC_KEY"
curl -sSf -o "docker-compose.yml" "$S3_BASE_URL/docker-compose.yml" || true
curl -sSf -o "docker-compose.yml.sig" "$S3_BASE_URL/docker-compose.yml.sig" || true

for f in "$NEW_VERSION_TMP" "$VERSION_SIG" "$IMAGE_TAR" "$IMAGE_SIG" "$PUBLIC_KEY"; do
    [ -s "$f" ] || { echo "Missing or empty $f"; exit 1; }
done

openssl dgst -sha256 -binary "$NEW_VERSION_TMP" > version.check.sha256
openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY"     -in version.check.sha256     -sigfile "$VERSION_SIG" || { echo "version.yaml signature verification failed!"; exit 1; }

openssl dgst -sha256 -binary "$IMAGE_TAR" > image.check.sha256
openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY"     -in image.check.sha256     -sigfile "$IMAGE_SIG" || { echo "main.tar signature verification failed!"; exit 1; }

if [[ -f docker-compose.yml && -f docker-compose.yml.sig ]]; then
  openssl dgst -sha256 -binary docker-compose.yml > compose.check.sha256
  openssl pkeyutl -verify -pubin -inkey "ota_public.pem"       -in compose.check.sha256       -sigfile docker-compose.yml.sig || { echo "docker-compose.yml signature verification failed!"; exit 1; }
  rm -f compose.check.sha256
  COMPOSE_MODE=true
else
  COMPOSE_MODE=false
fi

rm -f *.sha256

if [ ! -f "$LOCAL_VERSION" ]; then
    echo "No previous version.yaml found. Performing first-time setup."
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name!"
        exit 1
    fi

    if [[ "$COMPOSE_MODE" == true ]]; then
        sudo docker compose down || true
        sudo docker compose up -d
    else
        if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^\${CONTAINER_NAME}\$"; then
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
    echo "Newer version detected. Performing rolling update."
    DOCKER_LOAD_OUT=$(sudo docker load -i "$IMAGE_TAR")
    echo "$DOCKER_LOAD_OUT"
    IMAGE_NAME=$(echo "$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print $3}')
    if [ -z "$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name during update!"
        exit 1
    fi

    if [[ "$COMPOSE_MODE" == true ]]; then
        sudo docker compose down || true
        sudo docker compose up -d
    else
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
    fi
    cp "$NEW_VERSION_TMP" "$LOCAL_VERSION"
    echo "Update complete."
else
    echo "No update needed."
fi
