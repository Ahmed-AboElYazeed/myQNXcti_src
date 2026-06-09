#pragma once
#include <string>
#include <thread>
#include <mutex>
#include <atomic>
#include <vector>
#include <functional>

// Pushes JSON status lines to all connected Qt app clients
// Listens on port 55001
class StatusReporter {
public:
    static StatusReporter &instance();

    void start();   // call once at startup, runs in background thread
    void stop();

    // Call these from TcpReceiver and YoctoForwarder:
    void setState(const std::string &state);
    void setLaptopProgress(uint64_t received, uint64_t total);
    void setYoctoProgress(uint32_t percent, const std::string &msg);
    void setVersionInfo(const std::string &activeSlot,
                        const std::string &versionA,
                        const std::string &versionB);
    void pushLog(const std::string &msg);

private:
    StatusReporter() = default;
    void acceptLoop();
    void pushToAll(const std::string &json);

    std::thread             acceptThread_;
    std::mutex              clientsMutex_;
    std::vector<int>        clientFds_;
    std::atomic<bool>       running_{false};
    int                     serverFd_{-1};

    // Current state cache (sent to newly connected clients)
    std::mutex              stateMutex_;
    std::string             state_{"idle"};
    std::string             activeSlot_{"unknown"};
    std::string             versionA_{"unknown"};
    std::string             versionB_{"unknown"};
};
