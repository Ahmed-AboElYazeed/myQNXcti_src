#pragma once
#include <string>
#include <cstdint>

class YoctoForwarder {
public:
    YoctoForwarder(const std::string &domain,
                   const std::string &instance);

    bool forward(const std::string &imagePath,
                 const std::string &version,
                 const std::string &sha256);

private:
    std::string domain_;
    std::string instance_;
    static constexpr size_t CHUNK_SIZE = 512 * 1024;
};
