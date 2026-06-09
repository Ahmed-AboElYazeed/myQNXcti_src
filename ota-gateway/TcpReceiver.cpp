#include "TcpReceiver.hpp"
#include "StatusReporter.hpp"
#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>
#include <cerrno>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

static std::string jsonGetString(const std::string &json,
                                 const std::string &key) {
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "";
    size_t colon = json.find(':', pos + search.size());
    if (colon == std::string::npos) return "";
    size_t q1 = json.find('"', colon + 1);
    if (q1 == std::string::npos) return "";
    size_t q2 = json.find('"', q1 + 1);
    if (q2 == std::string::npos) return "";
    return json.substr(q1 + 1, q2 - q1 - 1);
}

static uint64_t jsonGetUint64(const std::string &json,
                              const std::string &key) {
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return 0;
    size_t colon = json.find(':', pos + search.size());
    if (colon == std::string::npos) return 0;
    size_t num = json.find_first_not_of(" \t\r\n", colon + 1);
    if (num == std::string::npos) return 0;
    return std::stoull(json.substr(num));
}

TcpReceiver::TcpReceiver(uint16_t port, const std::string &stagingPath)
    : port_(port), stagingPath_(stagingPath) {}

bool TcpReceiver::waitForUpdate(AnnounceHeader &hdr) {
    int serverFd = socket(AF_INET, SOCK_STREAM, 0);
    if (serverFd < 0) {
        std::cerr << "[RX] socket() failed: " << strerror(errno) << "\n";
        return false;
    }

    int opt = 1;
    setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(port_);

    if (bind(serverFd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "[RX] bind() failed: " << strerror(errno) << "\n";
        close(serverFd);
        return false;
    }

    listen(serverFd, 1);
    std::cout << "[RX] Listening on port " << port_ << "...\n";
    StatusReporter::instance().pushLog("[GW] Listening for laptop on port "
                                       + std::to_string(port_));

    int connFd = accept(serverFd, nullptr, nullptr);
    close(serverFd);
    if (connFd < 0) {
        std::cerr << "[RX] accept() failed: " << strerror(errno) << "\n";
        return false;
    }

    std::cout << "[RX] Laptop connected.\n";
    StatusReporter::instance().pushLog("[GW] Laptop connected");
    StatusReporter::instance().setState("receiving_from_laptop");

    if (!parseHeader(connFd, hdr)) {
        close(connFd);
        StatusReporter::instance().setState("failed");
        StatusReporter::instance().pushLog("[GW] Header parse failed");
        return false;
    }

    std::cout << "[RX] Header: version=" << hdr.version
              << " size=" << hdr.imageSize
              << " sha256=" << hdr.sha256 << "\n";
    StatusReporter::instance().pushLog(
        "[GW] Announce: version=" + hdr.version +
        " size=" + std::to_string(hdr.imageSize));

    if (!receiveImage(connFd, hdr.imageSize)) {
        close(connFd);
        StatusReporter::instance().setState("failed");
        StatusReporter::instance().pushLog("[GW] Image receive failed");
        return false;
    }

    close(connFd);
    return true;
}

bool TcpReceiver::parseHeader(int connFd, AnnounceHeader &hdr) {
    uint32_t netLen = 0;
    ssize_t n = recv(connFd, &netLen, 4, MSG_WAITALL);
    if (n != 4) {
        std::cerr << "[RX] Failed to read header length\n";
        return false;
    }
    uint32_t headerLen = ntohl(netLen);
    if (headerLen == 0 || headerLen > 65536) {
        std::cerr << "[RX] Bad header length: " << headerLen << "\n";
        return false;
    }

    std::string jsonBuf(headerLen, '\0');
    n = recv(connFd, &jsonBuf[0], headerLen, MSG_WAITALL);
    if (n != (ssize_t)headerLen) {
        std::cerr << "[RX] Failed to read header JSON\n";
        return false;
    }

    hdr.version   = jsonGetString(jsonBuf, "version");
    hdr.imageSize = jsonGetUint64(jsonBuf, "imageSize");
    hdr.sha256    = jsonGetString(jsonBuf, "sha256");
    hdr.signature = jsonGetString(jsonBuf, "signature");

    if (hdr.version.empty() || hdr.imageSize == 0 || hdr.sha256.empty()) {
        std::cerr << "[RX] Incomplete header\n";
        return false;
    }
    return true;
}

bool TcpReceiver::receiveImage(int connFd, uint64_t imageSize) {
    std::ofstream out(stagingPath_, std::ios::binary | std::ios::trunc);
    if (!out) {
        std::cerr << "[RX] Cannot open staging file: " << stagingPath_
                  << " : " << strerror(errno) << "\n";
        return false;
    }

    static const size_t BUF = 512 * 1024;
    std::vector<char> buf(BUF);
    uint64_t received = 0;
    uint32_t lastPct  = 0;

    while (received < imageSize) {
        size_t  toRead = std::min((uint64_t)BUF, imageSize - received);
        ssize_t n      = recv(connFd, buf.data(), toRead, 0);
        if (n <= 0) {
            std::cerr << "[RX] Connection lost at offset " << received << "\n";
            return false;
        }
        out.write(buf.data(), n);
        received += static_cast<uint64_t>(n);

        uint32_t pct = static_cast<uint32_t>((received * 100) / imageSize);
        if (pct != lastPct) {
            lastPct = pct;
            std::cout << "\r[RX] " << received << " / " << imageSize
                      << " bytes (" << pct << "%)   " << std::flush;
            // Push progress to Qt app
            StatusReporter::instance().setLaptopProgress(received, imageSize);
        }
    }
    std::cout << "\n[RX] Image fully received.\n";
    StatusReporter::instance().pushLog("[GW] Image fully received — "
                                       + std::to_string(imageSize) + " bytes");
    out.flush();
    return true;
}
