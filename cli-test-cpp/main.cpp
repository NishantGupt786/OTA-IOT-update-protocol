#include <iostream>
#include <string>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <cstring>

void send_timestamp_webhook() {
    std::string host = "httpbin.org";  // Using httpbin.org as alternative
    std::string path = "/post";
    int port = 80;
    
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto unix_timestamp = std::chrono::duration_cast<std::chrono::seconds>(
        now.time_since_epoch()).count();
    
    // Format timestamp string
    std::stringstream ss;
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    std::string timestamp_str = ss.str();
    
    // Create JSON payload
    std::stringstream json_payload;
    json_payload << "{"
                 << "\"timestamp\":\"" << timestamp_str << "\","
                 << "\"unix_timestamp\":" << unix_timestamp << ","
                 << "\"message\":\"Code is working!\""
                 << "}";
    std::string json_data = json_payload.str();
    
    // Create HTTP request
    std::stringstream request;
    request << "POST " << path << " HTTP/1.1\r\n"
            << "Host: " << host << "\r\n"
            << "Content-Type: application/json\r\n"
            << "Content-Length: " << json_data.length() << "\r\n"
            << "Connection: close\r\n"
            << "\r\n"
            << json_data;
    
    std::string request_str = request.str();
    
    // Create socket
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        std::cout << "Error creating socket" << std::endl;
        return;
    }
    
    // Get host info
    struct hostent* server = gethostbyname(host.c_str());
    if (server == nullptr) {
        std::cout << "Error: no such host" << std::endl;
        close(sockfd);
        return;
    }
    
    // Setup address
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);
    memcpy(&serv_addr.sin_addr.s_addr, server->h_addr, server->h_length);
    
    // Connect
    if (connect(sockfd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "Error connecting to server" << std::endl;
        close(sockfd);
        return;
    }
    
    // Send request
    ssize_t bytes_sent = send(sockfd, request_str.c_str(), request_str.length(), 0);
    if (bytes_sent < 0) {
        std::cout << "Error sending request" << std::endl;
        close(sockfd);
        return;
    }
    
    // Read response
    char buffer[1024];
    ssize_t bytes_received = recv(sockfd, buffer, sizeof(buffer) - 1, 0);
    if (bytes_received > 0) {
        buffer[bytes_received] = '\0';
        std::string response(buffer);
        
        // Check if we got HTTP 200
        if (response.find("HTTP/1.1 200") != std::string::npos) {
            std::cout << "Timestamp sent successfully now: " << timestamp_str << std::endl;
        } else {
            std::cout << "Request failed. Response: " << response.substr(0, 100) << std::endl;
        }
    }
    
    close(sockfd);
}

int main() {
    send_timestamp_webhook();
    return 0;
}
