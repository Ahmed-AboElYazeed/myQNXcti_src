#include "ImageVerifier.hpp"
#include <openssl/evp.h>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <iostream>
#include <vector>

std::string ImageVerifier::computeSHA256(const std::string &path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        std::cerr << "[VERIFY] Cannot open: " << path << "\n";
        return "";
    }

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr);

    std::vector<char> buf(1024 * 1024);
    while (f.read(buf.data(), buf.size()) || f.gcount() > 0)
        EVP_DigestUpdate(ctx, buf.data(), static_cast<size_t>(f.gcount()));

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int  len = 0;
    EVP_DigestFinal_ex(ctx, digest, &len);
    EVP_MD_CTX_free(ctx);

    std::ostringstream oss;
    for (unsigned int i = 0; i < len; ++i)
        oss << std::hex << std::setw(2) << std::setfill('0')
            << static_cast<int>(digest[i]);
    return oss.str();
}

bool ImageVerifier::verify(const std::string &path,
                           const std::string &expectedHash) {
    std::cout << "[VERIFY] Computing SHA256 of staged image...\n";
    std::string computed = computeSHA256(path);
    if (computed.empty()) return false;

    std::cout << "[VERIFY] Expected: " << expectedHash << "\n";
    std::cout << "[VERIFY] Computed: " << computed    << "\n";

    if (computed != expectedHash) {
        std::cerr << "[VERIFY] HASH MISMATCH — rejecting update\n";
        return false;
    }
    std::cout << "[VERIFY] SHA256 OK\n";
    return true;
}
