#include <iostream>
#include <chrono>
#include <thread>

int main() {
    int counter = 0;
    while (true) {
        std::cout << "Hello from Nishant C++ app! Count: " << counter++ << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(5));
    }
    return 0;
}

