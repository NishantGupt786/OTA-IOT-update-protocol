#include <cpr/cpr.h>
#include <json/json.h>
#include <iostream>
#include <chrono>
#include <iomanip>
#include <sstream>

void send_timestamp_webhook() {
    std::string webhook_url = "https://webhook.site/6805d787-f0e8-4f13-b90f-84fe8719b06c";
    
    // Generate current timestamp
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto unix_timestamp = std::chrono::duration_cast<std::chrono::seconds>(
        now.time_since_epoch()).count();
    
    // Format timestamp string
    std::stringstream ss;
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    std::string timestamp_str = ss.str();
    
    // Create JSON payload
    Json::Value timestamp_data;
    timestamp_data["timestamp"] = timestamp_str;
    timestamp_data["unix_timestamp"] = static_cast<int64_t>(unix_timestamp);
    timestamp_data["message"] = "Code is working!";
    
    // Convert JSON to string
    Json::StreamWriterBuilder builder;
    std::string json_string = Json::writeString(builder, timestamp_data);
    
    try {
        // Send POST request
        auto response = cpr::Post(
            cpr::Url{webhook_url},
            cpr::Body{json_string},
            cpr::Header{{"Content-Type", "application/json"}}
        );
        
        if (response.status_code == 200) {
            std::cout << "Timestamp sent successfully now: " << timestamp_str << std::endl;
        } else {
            std::cout << "Failed to send timestamp: " << response.status_code << std::endl;
        }
    } catch (const std::exception& e) {
        std::cout << "Error sending timestamp: " << e.what() << std::endl;
    }
}

int main() {
    send_timestamp_webhook();
    return 0;
}
