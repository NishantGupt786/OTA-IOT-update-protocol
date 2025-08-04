#!/bin/bash
set -e

PLATFORM="linux/arm/v7"
LANGUAGE="java"
EDGE_DEVICE="rpi3b"
PRG_FILE_NAME="main"
DOCKER_IMAGE_TAG="1.0"
S3_BUCKET="iot-ota-rtupdate"
PRIVATE_KEY="ota_private.pem"
IMAGE_TAR="${PRG_FILE_NAME}.tar"
IMAGE_SIG="${IMAGE_TAR}.sig"
VERSION_FILE="version.yaml"
VERSION_SIG="version.yaml.sig"
IMAGE_NAME="${PRG_FILE_NAME}:${DOCKER_IMAGE_TAG}"
DIRECTORY_NAME=$(basename "$PWD")

docker buildx build --platform $PLATFORM --no-cache -t $IMAGE_NAME --output type=docker .
docker save -o $IMAGE_TAR $IMAGE_NAME

openssl dgst -sha256 -binary $IMAGE_TAR > ${IMAGE_TAR}.sha256
openssl pkeyutl -sign -inkey $PRIVATE_KEY -in ${IMAGE_TAR}.sha256 -out $IMAGE_SIG

CUR_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"$CUR_TS\"" > $VERSION_FILE
openssl dgst -sha256 -binary $VERSION_FILE > ${VERSION_FILE}.sha256
openssl pkeyutl -sign -inkey $PRIVATE_KEY -in ${VERSION_FILE}.sha256 -out $VERSION_SIG

aws s3 cp $IMAGE_TAR s3://$S3_BUCKET/$DIRECTORY_NAME/$IMAGE_TAR
aws s3 cp $IMAGE_SIG s3://$S3_BUCKET/$DIRECTORY_NAME/$IMAGE_SIG
aws s3 cp $VERSION_FILE s3://$S3_BUCKET/$DIRECTORY_NAME/$VERSION_FILE
aws s3 cp $VERSION_SIG s3://$S3_BUCKET/$DIRECTORY_NAME/$VERSION_SIG

rm -f *.sha256

echo "=== REDEPLOY COMPLETE ==="
