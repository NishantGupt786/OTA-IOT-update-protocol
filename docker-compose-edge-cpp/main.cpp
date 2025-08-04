#include <iostream>
#include <unistd.h>
#include <netinet/in.h>
#include <cstring>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    const int PORT = 8080;
    char buffer[1024] = {0};

    server_fd = socket(AF_INET, SOCK_STREAM, 0);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    std::cout << "Listening on port " << PORT << "...\n";
    new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
    read(new_socket, buffer, 1024);
    std::cout << "Received: " << buffer << "\n";
    std::string hello = "Hello from Raspberry Pi\n";
    send(new_socket, hello.c_str(), hello.size(), 0);

    close(new_socket);
    close(server_fd);
    return 0;
}
