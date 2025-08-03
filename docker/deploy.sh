#!/bin/bash
set -e

# ==== USER VARIABLES ====
DIRECTORY_NAME="docker-edge"
PRG_FILE_NAME="main"
DOCKER_IMAGE_TAG="1.0"
S3_BUCKET="iot-ota-rtupdate"
PRIVATE_KEY="ota_private.pem"
PUBLIC_KEY="ota_public.pem" # You will upload this to S3 once, devices need a copy too.
IMAGE_TAR="${PRG_FILE_NAME}.tar"
IMAGE_SIG="${IMAGE_TAR}.sig"
VERSION_FILE="version.yaml"
VERSION_SIG="version.yaml.sig"
IMAGE_NAME="${PRG_FILE_NAME}:${DOCKER_IMAGE_TAG}"

# --- Step 0: (One-time) Generate private/public key ---
# Uncomment if you haven't generated your RSA keys yet.
openssl genpkey -algorithm RSA -out ${PRIVATE_KEY} -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in ${PRIVATE_KEY} -out ${PUBLIC_KEY}

# 1. Build Docker image
echo "Building Docker image..."
docker buildx build --platform linux/arm/v7 --no-cache -t $IMAGE_NAME --output type=docker .

# 2. Save Docker image as TAR
echo "Saving Docker image to tarball..."
docker save -o $IMAGE_TAR $IMAGE_NAME

# 3. Sign the Docker image TAR file
echo "Signing the image tarball..."
openssl dgst -sha256 -binary $IMAGE_TAR > ${IMAGE_TAR}.sha256
openssl pkeyutl -sign -inkey ${PRIVATE_KEY} -in ${IMAGE_TAR}.sha256 -out ${IMAGE_SIG}

# 4. Upload tarball and its signature to S3
echo "Uploading Docker image tarball and signature to S3..."
aws s3 cp $IMAGE_TAR s3://$S3_BUCKET/$DIRECTORY_NAME/$IMAGE_TAR
aws s3 cp $IMAGE_SIG s3://$S3_BUCKET/$DIRECTORY_NAME/$IMAGE_SIG

# 5. Update version.yaml with new timestamp and sign it
echo "Updating and signing version.yaml..."
CUR_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"$CUR_TS\"" > $VERSION_FILE
openssl dgst -sha256 -binary $VERSION_FILE > ${VERSION_FILE}.sha256
openssl pkeyutl -sign -inkey ${PRIVATE_KEY} -in ${VERSION_FILE}.sha256 -out ${VERSION_SIG}

# 6. Upload version.yaml and signature to S3
echo "Uploading version.yaml and its signature to S3..."
aws s3 cp $VERSION_FILE s3://$S3_BUCKET/$DIRECTORY_NAME/$VERSION_FILE
aws s3 cp $VERSION_SIG s3://$S3_BUCKET/$DIRECTORY_NAME/$VERSION_SIG

# 7. (Optional, first time only) Upload public key so devices can fetch latest key
aws s3 cp ${PUBLIC_KEY} s3://$S3_BUCKET/$DIRECTORY_NAME/$PUBLIC_KEY

echo "=== DONE. Docker image, signature, and version.yaml updated/pushed to S3 ==="

# Clean up
rm -f *.sha256
