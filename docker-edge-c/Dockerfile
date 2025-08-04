FROM arm32v7/debian:bullseye-slim
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y build-essential && gcc main.c -o main
CMD ["./main"]
