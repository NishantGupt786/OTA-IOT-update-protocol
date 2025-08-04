#!/bin/bash
set -e

# ---- Language Selection ----
echo "Choose programming language:"
select LANGUAGE in cpp c python java; do
  case $LANGUAGE in
    cpp|c|python|java)
      break
      ;;
    *)
      echo "Invalid choice. Try again."
      ;;
  esac
done

# ---- Edge Device Selection ----
echo "Choose edge device:"
select EDGE_DEVICE in rpi3b jetsonnano jetsonorin x86_64; do
  case $EDGE_DEVICE in
    rpi3b|jetsonnano|jetsonorin|x86_64)
      break
      ;;
    *)
      echo "Invalid choice. Try again."
      ;;
  esac
done

# ---- Program File Name ----
read -p "Enter the name of your main program (no extension for C/C++/python; .jar for Java): " PRG_FILE_BASENAME

case "$EDGE_DEVICE" in
  rpi3b)       PLATFORM="linux/arm/v7" ;;
  jetsonnano)  PLATFORM="linux/arm64" ;;
  jetsonorin)  PLATFORM="linux/arm64" ;;
  x86_64)      PLATFORM="linux/amd64" ;;
esac

DOCKER_IMAGE_TAG="1.0"
S3_BUCKET="iot-ota-rtupdate"
PRIVATE_KEY="ota_private.pem"
PUBLIC_KEY="ota_public.pem"
IMAGE_TAR="${PRG_FILE_BASENAME}.tar"
IMAGE_SIG="${IMAGE_TAR}.sig"
VERSION_FILE="version.yaml"
VERSION_SIG="version.yaml.sig"
IMAGE_NAME="${PRG_FILE_BASENAME}:${DOCKER_IMAGE_TAG}"
DIRECTORY_NAME=$(basename "$PWD")

# ---- Generate Dockerfile ----
case "$LANGUAGE" in
  cpp)
    BASE="arm32v7/debian:bullseye-slim"
    [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/debian:bullseye-slim"
    cat > Dockerfile <<EOF
FROM $BASE
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y build-essential && g++ ${PRG_FILE_BASENAME}.cpp -o ${PRG_FILE_BASENAME}
CMD ["./${PRG_FILE_BASENAME}"]
EOF
    ;;
  c)
    BASE="arm32v7/debian:bullseye-slim"
    [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/debian:bullseye-slim"
    cat > Dockerfile <<EOF
FROM $BASE
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y build-essential && gcc ${PRG_FILE_BASENAME}.c -o ${PRG_FILE_BASENAME}
CMD ["./${PRG_FILE_BASENAME}"]
EOF
    ;;
  python)
    BASE="arm32v7/python:3.9-slim"
    [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/python:3.9-slim"
    cat > Dockerfile <<EOF
FROM $BASE
WORKDIR /app
COPY . /app
RUN pip install -r requirements.txt || true
CMD ["python", "${PRG_FILE_BASENAME}.py"]
EOF
    ;;
  java)
    BASE="arm32v7/openjdk:11-jre-slim"
    [[ "$PLATFORM" == "linux/arm64" ]] && BASE="arm64v8/openjdk:11-jre-slim"
    cat > Dockerfile <<EOF
FROM $BASE
WORKDIR /app
COPY . /app
CMD ["java", "-jar", "${PRG_FILE_BASENAME}.jar"]
EOF
    ;;
esac

# ---- Generate keys if not present ----
if [[ ! -f "$PRIVATE_KEY" ]]; then
  openssl genpkey -algorithm RSA -out $PRIVATE_KEY -pkeyopt rsa_keygen_bits:2048
  openssl rsa -pubout -in $PRIVATE_KEY -out $PUBLIC_KEY
fi

# Build and Deploy
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
aws s3 cp $PUBLIC_KEY s3://$S3_BUCKET/$DIRECTORY_NAME/$PUBLIC_KEY

rm -f *.sha256

echo "=== INIT DONE ==="
