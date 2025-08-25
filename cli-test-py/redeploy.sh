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

docker buildx build --platform linux/arm/v7 --no-cache -t process:1.0 --output type=docker .
docker save -o process.tar process:1.0

if [ "$NO_UPLOAD" = true ]; then
    echo "Build complete. Image 'process:1.0' is available locally."
    echo "Tarball saved as 'process.tar'."
    rm -f process.tar # Clean up tarball if not uploading
    exit 0
fi

echo "Signing artifacts..."
openssl dgst -sha256 -binary process.tar > process.tar.sha256
openssl pkeyutl -sign -inkey ota_private.pem -in process.tar.sha256 -out process.tar.sig

CUR_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "last_build: \"$CUR_TS\"" > version.yaml
openssl dgst -sha256 -binary version.yaml > version.yaml.sha256
openssl pkeyutl -sign -inkey ota_private.pem -in version.yaml.sha256 -out version.yaml.sig

echo "Uploading to s3://iot-ota-rtupdate/cli-test-py/"
aws s3 cp process.tar s3://iot-ota-rtupdate/cli-test-py/process.tar
aws s3 cp process.tar.sig s3://iot-ota-rtupdate/cli-test-py/process.tar.sig
aws s3 cp version.yaml s3://iot-ota-rtupdate/cli-test-py/version.yaml
aws s3 cp version.yaml.sig s3://iot-ota-rtupdate/cli-test-py/version.yaml.sig

rm -f *.sha256 *.tar *.sig
echo "Redeployment to S3 successful."
