#pragma once
#include <string>
#include <cstdint>
#include <vector>

struct AnnounceHeader {
    std::string version;
    uint64_t    imageSize;
    std::string sha256;
    std::string signature;
};

class TcpReceiver {
public:
    explicit TcpReceiver(uint16_t port, const std::string &stagingPath);
    bool waitForUpdate(AnnounceHeader &outHeader);

private:
    uint16_t    port_;
    std::string stagingPath_;

    bool parseHeader(int connFd, AnnounceHeader &hdr);
    bool receiveImage(int connFd, uint64_t imageSize);
};
