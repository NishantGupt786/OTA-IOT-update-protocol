FROM arm32v7/debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends g++ && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY main.cpp /usr/src/app/main.cpp

WORKDIR /usr/src/app

RUN g++ -o my_app main.cpp

ENTRYPOINT ["./my_app"]
