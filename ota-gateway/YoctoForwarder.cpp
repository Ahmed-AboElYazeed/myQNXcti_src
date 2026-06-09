#include "YoctoForwarder.hpp"
#include "StatusReporter.hpp"
#include <CommonAPI/CommonAPI.hpp>
#include <v1/com/myapp/ota/OtaUpdateProxy.hpp>
#include <iostream>
#include <fstream>
#include <vector>
#include <thread>
#include <chrono>
#include <iomanip>
#include <sstream>

using namespace v1::com::myapp::ota;

YoctoForwarder::YoctoForwarder(const std::string &domain,
                               const std::string &instance)
    : domain_(domain), instance_(instance) {}

bool YoctoForwarder::forward(const std::string &imagePath,
                             const std::string &version,
                             const std::string &sha256) {

    // ── Build proxy ──────────────────────────────────────────────────────
    auto runtime = CommonAPI::Runtime::get();
    auto proxy   = runtime->buildProxy<OtaUpdateProxy>(
                       domain_, instance_, "OtaGateway");

    std::cout << "[FWD] Waiting for Yocto OTA service...\n";
    StatusReporter::instance().pushLog("[GW] Connecting to Yocto ECU...");
    StatusReporter::instance().setState("connecting_to_ecu");

    int retries = 30;
    while (!proxy->isAvailable() && retries-- > 0)
        std::this_thread::sleep_for(std::chrono::seconds(1));

    if (!proxy->isAvailable()) {
        std::cerr << "[FWD] Yocto OTA service not found — timeout\n";
        StatusReporter::instance().pushLog("[GW] ECU service not found — timeout");
        StatusReporter::instance().setState("failed");
        return false;
    }

    std::cout << "[FWD] Yocto service available.\n";
    StatusReporter::instance().pushLog("[GW] ECU service available");
    StatusReporter::instance().setState("forwarding_to_ecu");

    // ── Subscribe to Yocto status events ────────────────────────────────
    proxy->getUpdateStatusEvent().subscribe(
        [](const std::string &status, const uint32_t &pct,
           const std::string &msg) {
            std::cout << "[YOCTO] " << status
                      << " (" << pct << "%) " << msg << "\n";
            StatusReporter::instance().setYoctoProgress(pct, msg);
            StatusReporter::instance().pushLog("[ECU] " + msg);
        });

    // ── Open image file ──────────────────────────────────────────────────
    std::ifstream img(imagePath, std::ios::binary | std::ios::ate);
    if (!img) {
        std::cerr << "[FWD] Cannot open staged image: " << imagePath << "\n";
        StatusReporter::instance().pushLog("[GW] Cannot open staged image");
        StatusReporter::instance().setState("failed");
        return false;
    }
    uint64_t imageSize = static_cast<uint64_t>(img.tellg());
    img.seekg(0);

    // ── AnnounceUpdate ───────────────────────────────────────────────────
    CommonAPI::CallStatus cs;
    bool        accepted = false;
    std::string message;

    proxy->AnnounceUpdate(version, imageSize, sha256, cs, accepted, message);
    if (cs != CommonAPI::CallStatus::SUCCESS || !accepted) {
        std::cerr << "[FWD] AnnounceUpdate rejected: " << message << "\n";
        StatusReporter::instance().pushLog("[GW] ECU rejected update: " + message);
        StatusReporter::instance().setState("failed");
        return false;
    }
    std::cout << "[FWD] Yocto accepted: " << message << "\n";
    StatusReporter::instance().pushLog("[GW] ECU accepted: " + message);

    // ── SendChunk loop ───────────────────────────────────────────────────
    uint64_t offset   = 0;
    uint32_t lastPct  = 0;
    std::vector<uint8_t> buf(CHUNK_SIZE);

    while (offset < imageSize) {
        size_t toRead = std::min(CHUNK_SIZE,
                                 static_cast<size_t>(imageSize - offset));
        img.read(reinterpret_cast<char*>(buf.data()), toRead);
        size_t actualRead = static_cast<size_t>(img.gcount());

        CommonAPI::ByteBuffer chunk(buf.begin(), buf.begin() + actualRead);

        int64_t nextOffset = 0;
        proxy->SendChunk(offset, chunk, cs, nextOffset);

        if (cs != CommonAPI::CallStatus::SUCCESS || nextOffset < 0) {
            std::cerr << "[FWD] SendChunk failed at offset " << offset << "\n";
            StatusReporter::instance().pushLog(
                "[GW] Chunk send failed at offset " + std::to_string(offset));
            StatusReporter::instance().setState("failed");
            return false;
        }

        if (static_cast<uint64_t>(nextOffset) != offset + actualRead) {
            std::cout << "[FWD] Resume from " << nextOffset << "\n";
            img.seekg(static_cast<std::streamoff>(nextOffset));
        }

        offset = static_cast<uint64_t>(nextOffset);

        uint32_t pct = static_cast<uint32_t>(
            (offset * 100) / imageSize);
        if (pct != lastPct) {
            lastPct = pct;
            std::cout << "\r[FWD] " << offset << " / " << imageSize
                      << " bytes (" << pct << "%)   " << std::flush;
            StatusReporter::instance().setYoctoProgress(pct,
                std::to_string(offset) + "/" + std::to_string(imageSize));
        }
    }
    std::cout << "\n[FWD] All chunks forwarded.\n";
    StatusReporter::instance().pushLog("[GW] All chunks forwarded to ECU");

    // ── FinalizeUpdate ───────────────────────────────────────────────────
    bool success = false;
    // proxy->FinalizeUpdate(sha256, cs, success, message);
    CommonAPI::CallInfo callInfo(180000*100); // 180000 == 3 minute timeout
    proxy->FinalizeUpdate(sha256, cs, success, message, &callInfo);
    if (cs != CommonAPI::CallStatus::SUCCESS || !success) {
        std::cerr << "[FWD] FinalizeUpdate failed: " << message << "\n";
        StatusReporter::instance().pushLog("[GW] Finalize failed: " + message);
        StatusReporter::instance().setState("failed");
        return false;
    }

    std::cout << "[FWD] Yocto finalizing: " << message << "\n";
    StatusReporter::instance().pushLog("[GW] ECU finalizing: " + message);
    StatusReporter::instance().setState("complete");
    return true;
}
