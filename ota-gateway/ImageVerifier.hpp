#pragma once
#include <string>

class ImageVerifier {
public:
    // Compute SHA256 of file at path, return hex string
    static std::string computeSHA256(const std::string &path);

    // Compare computed hash against expected, print result
    static bool verify(const std::string &path, const std::string &expectedHash);
};
