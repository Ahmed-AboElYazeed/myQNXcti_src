#include "StatusReporter.hpp"
#include <iostream>
#include <sstream>
#include <cstring>
#include <cerrno>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>

static const uint16_t STATUS_PORT = 55001;

StatusReporter &StatusReporter::instance() {
    static StatusReporter inst;
    return inst;
}

void StatusReporter::start() {
    running_ = true;
    acceptThread_ = std::thread(&StatusReporter::acceptLoop, this);
    acceptThread_.detach();
    std::cout << "[STATUS] Listening on port " << STATUS_PORT << "\n";
}

void StatusReporter::stop() {
    running_ = false;
    if (serverFd_ >= 0) close(serverFd_);
}

void StatusReporter::acceptLoop() {
    serverFd_ = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(serverFd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(STATUS_PORT);
    bind(serverFd_, (sockaddr*)&addr, sizeof(addr));
    listen(serverFd_, 4);

    while (running_) {
        int fd = accept(serverFd_, nullptr, nullptr);
        if (fd < 0) continue;

        std::cout << "[STATUS] Qt app connected\n";

        // Send current state immediately on connect
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            std::ostringstream oss;
            oss << "{\"type\":\"state\""
                << ",\"state\":\"" << state_ << "\""
                << ",\"activeSlot\":\"" << activeSlot_ << "\""
                << ",\"versionA\":\"" << versionA_ << "\""
                << ",\"versionB\":\"" << versionB_ << "\"}\n";
            std::string msg = oss.str();
            send(fd, msg.c_str(), msg.size(), 0);
        }

        std::lock_guard<std::mutex> lk(clientsMutex_);
        clientFds_.push_back(fd);
    }
}

void StatusReporter::pushToAll(const std::string &json) {
    std::lock_guard<std::mutex> lk(clientsMutex_);
    std::vector<int> dead;
    for (int fd : clientFds_) {
        if (send(fd, json.c_str(), json.size(), 0) < 0)
            dead.push_back(fd);
    }
    for (int fd : dead) {
        close(fd);
        clientFds_.erase(
            std::remove(clientFds_.begin(), clientFds_.end(), fd),
            clientFds_.end());
    }
}

void StatusReporter::setState(const std::string &state) {
    { std::lock_guard<std::mutex> lk(stateMutex_); state_ = state; }
    std::ostringstream oss;
    oss << "{\"type\":\"state\",\"state\":\"" << state << "\"}\n";
    pushToAll(oss.str());
    pushLog("[GW] State: " + state);
}

void StatusReporter::setLaptopProgress(uint64_t received, uint64_t total) {
    uint32_t pct = total > 0 ? (uint32_t)((received * 100) / total) : 0;
    std::ostringstream oss;
    oss << "{\"type\":\"laptop_progress\""
        << ",\"received\":" << received
        << ",\"total\":"    << total
        << ",\"percent\":"  << pct << "}\n";
    pushToAll(oss.str());
}

void StatusReporter::setYoctoProgress(uint32_t percent,
                                       const std::string &msg) {
    std::ostringstream oss;
    oss << "{\"type\":\"yocto_progress\""
        << ",\"percent\":"  << percent
        << ",\"msg\":\""    << msg << "\"}\n";
    pushToAll(oss.str());
}

void StatusReporter::setVersionInfo(const std::string &activeSlot,
                                    const std::string &versionA,
                                    const std::string &versionB) {
    {
        std::lock_guard<std::mutex> lk(stateMutex_);
        activeSlot_ = activeSlot;
        versionA_   = versionA;
        versionB_   = versionB;
    }
    std::ostringstream oss;
    oss << "{\"type\":\"version\""
        << ",\"activeSlot\":\"" << activeSlot << "\""
        << ",\"versionA\":\""   << versionA   << "\""
        << ",\"versionB\":\""   << versionB   << "\"}\n";
    pushToAll(oss.str());
}

void StatusReporter::pushLog(const std::string &msg) {
    // Escape quotes minimally
    std::string safe = msg;
    for (auto &c : safe) if (c == '"') c = '\'';
    std::ostringstream oss;
    oss << "{\"type\":\"log\",\"msg\":\"" << safe << "\"}\n";
    pushToAll(oss.str());
}
