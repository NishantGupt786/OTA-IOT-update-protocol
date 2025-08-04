#!/bin/bash
set -e

echo "Choose programming language:"
select LANGUAGE in cpp c python java; do
  case $LANGUAGE in
    cpp|c|python|java) break ;;
    *) echo "Invalid choice. Try again." ;;
  esac
done

echo "Choose edge device:"
select EDGE_DEVICE in rpi3b jetsonnano jetsonorin x86_64; do
  case $EDGE_DEVICE in
    rpi3b|jetsonnano|jetsonorin|x86_64) break ;;
    *) echo "Invalid choice. Try again." ;;
  esac
done

read -p "Enter the name of your main program (no extension for C/C++; .py for Python; .jar for Java): " PRG_FILE_BASENAME

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
    BASE_BUILDER="arm32v7/openjdk:11-jdk-slim"
    BASE_RUNTIME="arm32v7/openjdk:11-jre-slim"
    [[ "$PLATFORM" == "linux/arm64" ]] && BASE_BUILDER="arm64v8/openjdk:11-jdk-slim" && BASE_RUNTIME="arm64v8/openjdk:11-jre-slim"

    if [[ "$PRG_FILE_BASENAME" == *.jar ]]; then
    cat > Dockerfile <<EOF
FROM $BASE_RUNTIME
WORKDIR /app
COPY . /app
CMD ["java", "-jar", "$PRG_FILE_BASENAME"]
EOF
    else
      cat > Dockerfile <<EOF
FROM $BASE_BUILDER AS builder
WORKDIR /build
COPY . /build
RUN mkdir -p out && javac ${PRG_FILE_BASENAME}.java -d out && \
    echo "Main-Class: ${PRG_FILE_BASENAME}" > manifest.txt && \
    jar cfm ${PRG_FILE_BASENAME}.jar manifest.txt -C out .

FROM $BASE_RUNTIME
WORKDIR /app
COPY --from=builder /build/${PRG_FILE_BASENAME}.jar /app/${PRG_FILE_BASENAME}.jar
CMD ["java", "-jar", "${PRG_FILE_BASENAME}.jar"]
EOF
    fi
    ;;
esac

if [[ ! -f "$PRIVATE_KEY" ]]; then
  openssl genpkey -algorithm RSA -out $PRIVATE_KEY -pkeyopt rsa_keygen_bits:2048
  openssl rsa -pubout -in $PRIVATE_KEY -out $PUBLIC_KEY
fi

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

EDGE_DEPLOY_SCRIPT="edge_deploy.sh"
cat > $EDGE_DEPLOY_SCRIPT <<EOF
#!/bin/bash
set -ex

S3_BASE_URL="https://${S3_BUCKET}.s3.amazonaws.com/${DIRECTORY_NAME}"
WORKDIR="\$HOME/docker-edge-app"
CONTAINER_NAME="${PRG_FILE_BASENAME}_ota_app"
mkdir -p "\$WORKDIR"
cd "\$WORKDIR"

LOCAL_VERSION="version.yaml"
NEW_VERSION_TMP="version_remote.yaml"
VERSION_SIG="version_remote.yaml.sig"
IMAGE_TAR="${IMAGE_TAR}"
IMAGE_SIG="${IMAGE_SIG}"
PUBLIC_KEY="${PUBLIC_KEY}"

wget -O "\$NEW_VERSION_TMP" "\$S3_BASE_URL/\$LOCAL_VERSION"
wget -O "\$VERSION_SIG"     "\$S3_BASE_URL/\$VERSION_SIG"
wget -O "\$IMAGE_TAR"       "\$S3_BASE_URL/\$IMAGE_TAR"
wget -O "\$IMAGE_SIG"       "\$S3_BASE_URL/\$IMAGE_SIG"
wget -O "\$PUBLIC_KEY"      "\$S3_BASE_URL/\$PUBLIC_KEY"

for f in "\$NEW_VERSION_TMP" "\$VERSION_SIG" "\$IMAGE_TAR" "\$IMAGE_SIG" "\$PUBLIC_KEY"; do
    [ -s "\$f" ] || { echo "Missing or empty \$f"; exit 1; }
done

openssl dgst -sha256 -binary "\$NEW_VERSION_TMP" > version.check.sha256
openssl pkeyutl -verify -pubin -inkey "\$PUBLIC_KEY" \
    -in version.check.sha256 \
    -sigfile "\$VERSION_SIG" || { echo "version.yaml signature verification failed!"; exit 1; }

openssl dgst -sha256 -binary "\$IMAGE_TAR" > image.check.sha256
openssl pkeyutl -verify -pubin -inkey "\$PUBLIC_KEY" \
    -in image.check.sha256 \
    -sigfile "\$IMAGE_SIG" || { echo "${IMAGE_TAR} signature verification failed!"; exit 1; }

rm -f *.sha256

if [ ! -f "\$LOCAL_VERSION" ]; then
    echo "No previous version.yaml found. Performing first-time setup."
    DOCKER_LOAD_OUT=\$(sudo docker load -i "\$IMAGE_TAR")
    echo "\$DOCKER_LOAD_OUT"
    IMAGE_NAME=\$(echo "\$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print \$3}')
    if [ -z "\$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name!"
        exit 1
    fi
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^\\\${CONTAINER_NAME}\\\$"; then
        sudo docker rm -f "\$CONTAINER_NAME"
    fi
    sudo docker run -d --name "\$CONTAINER_NAME" "\$IMAGE_NAME"
    cp "\$NEW_VERSION_TMP" "\$LOCAL_VERSION"
    echo "Initialized local version.yaml."
    exit 0
fi

LAST_LOCAL=\$(grep last_build "\$LOCAL_VERSION" | awk '{print \$2}' | tr -d '"')
LAST_REMOTE=\$(grep last_build "\$NEW_VERSION_TMP" | awk '{print \$2}' | tr -d '"')

if [[ "\$LAST_REMOTE" > "\$LAST_LOCAL" ]]; then
    echo "Newer version detected. Performing rolling update."
    DOCKER_LOAD_OUT=\$(sudo docker load -i "\$IMAGE_TAR")
    echo "\$DOCKER_LOAD_OUT"
    IMAGE_NAME=\$(echo "\$DOCKER_LOAD_OUT" | grep 'Loaded image:' | awk '{print \$3}')
    if [ -z "\$IMAGE_NAME" ]; then
        echo "Could not determine loaded image name during update!"
        exit 1
    fi
    CONTAINER_RUNNING=\$(sudo docker ps --format '{{.Names}}' | grep -x "\$CONTAINER_NAME" || true)
    if [ -n "\$CONTAINER_RUNNING" ]; then
        NEW_CONTAINER="\${CONTAINER_NAME}_new"
        sudo docker run -d --name "\$NEW_CONTAINER" "\$IMAGE_NAME"
        sleep 2
        sudo docker stop "\$CONTAINER_NAME"
        sudo docker rm "\$CONTAINER_NAME"
        sudo docker rename "\$NEW_CONTAINER" "\$CONTAINER_NAME"
    else
        sudo docker rm -f "\$CONTAINER_NAME" 2>/dev/null || true
        sudo docker run -d --name "\$CONTAINER_NAME" "\$IMAGE_NAME"
    fi
    cp "\$NEW_VERSION_TMP" "\$LOCAL_VERSION"
    echo "Update complete."
else
    echo "No update needed."
fi
EOF

echo "=== INIT DONE ==="
