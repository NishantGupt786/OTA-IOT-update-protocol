FROM arm32v7/openjdk:11-jdk-slim AS builder
WORKDIR /build
COPY . /build
RUN mkdir -p out && javac main.java -d out &&     echo "Main-Class: main" > manifest.txt &&     jar cfm main.jar manifest.txt -C out .

FROM arm32v7/openjdk:11-jre-slim
WORKDIR /app
COPY --from=builder /build/main.jar /app/main.jar
CMD ["java", "-jar", "main.jar"]
