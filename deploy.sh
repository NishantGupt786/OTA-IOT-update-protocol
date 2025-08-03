#!/bin/bash
set -e

# ==== USER VARIABLES (edit these) ====
DIRECTORY_NAME="docker-edge"           # e.g., armv7-apps
PRG_FILE_NAME="main"                # e.g., my-cpp-app  or whatever your program is
DOCKER_IMAGE_TAG="1.0"                    # update if needed/semantic versioning
S3_BUCKET="iot-ota-rtupdate"
IMAGE_TAR="${PRG_FILE_NAME}.tar"
IMAGE_NAME="${PRG_FILE_NAME}:${DOCKER_IMAGE_TAG}"

# ==== 1. Build Docker image ====
echo "Building Docker image..."
docker buildx build --platform linux/arm/v7 --no-cache -t $IMAGE_NAME --output type=docker .

# ==== 2. Save Docker image as TAR ====
echo "Saving Docker image to tarball..."
docker save -o $IMAGE_TAR $IMAGE_NAME

# ==== 3. Push docker tarball to S3 ====
echo "Uploading new Docker image tarball to S3..."
aws s3 cp $IMAGE_TAR s3://$S3_BUCKET/$DIRECTORY_NAME/$IMAGE_TAR

# ==== 4. Update version.yaml with new timestamp ====
echo "Updating version.yaml..."
CUR_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"$CUR_TS\"" > version.yaml

# ==== 5. Push updated version.yaml to S3 ====
echo "Uploading version.yaml to S3..."
aws s3 cp version.yaml s3://$S3_BUCKET/$DIRECTORY_NAME/version.yaml

echo "=== DONE. Docker image and version.yaml updated/pushed to S3 ==="
