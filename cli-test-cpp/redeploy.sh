#!/bin/bash
set -e
NO_UPLOAD=false
if [ "$1" == "--no-upload" ]; then
    NO_UPLOAD=true
fi

if [ "$NO_UPLOAD" = true ]; then
    echo "Building Docker image locally..."
else
    echo "Building and redeploying to S3..."
fi

docker buildx build --platform linux/arm/v7 --no-cache -t main:1.0 --output type=docker .
docker save -o main.tar main:1.0

if [ "$NO_UPLOAD" = true ]; then
    echo "Build complete. Image 'main:1.0' is available locally."
    echo "Tarball saved as 'main.tar'."
    rm -f main.tar # Clean up tarball if not uploading
    exit 0
fi

echo "Signing artifacts..."
openssl dgst -sha256 -binary main.tar > main.tar.sha256
openssl pkeyutl -sign -inkey ota_private.pem -in main.tar.sha256 -out main.tar.sig

CUR_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"$CUR_TS\"" > version.yaml
openssl dgst -sha256 -binary version.yaml > version.yaml.sha256
openssl pkeyutl -sign -inkey ota_private.pem -in version.yaml.sha256 -out version.yaml.sig

echo "Uploading to s3://iot-ota-rtupdate/cli-test-cpp/"
aws s3 cp main.tar s3://iot-ota-rtupdate/cli-test-cpp/main.tar
aws s3 cp main.tar.sig s3://iot-ota-rtupdate/cli-test-cpp/main.tar.sig
aws s3 cp version.yaml s3://iot-ota-rtupdate/cli-test-cpp/version.yaml
aws s3 cp version.yaml.sig s3://iot-ota-rtupdate/cli-test-cpp/version.yaml.sig

rm -f *.sha256 *.tar *.sig
echo "Redeployment to S3 successful."
