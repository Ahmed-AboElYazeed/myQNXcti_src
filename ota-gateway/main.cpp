#include "TcpReceiver.hpp"
#include "ImageVerifier.hpp"
#include "YoctoForwarder.hpp"
#include "StatusReporter.hpp"
#include <iostream>
#include <cstdio>
#include <string>

static const uint16_t    LISTEN_PORT   = 55000;
static const std::string STAGING_FILE  = "/var/ota_staging/update.img";
static const std::string CAPI_DOMAIN   = "local";
static const std::string CAPI_INSTANCE = "com.myapp.ota.OtaUpdate";
static const std::string YOCTO_IP      = "192.168.50.50";

// Read a field from a JSON string — reused from TcpReceiver
static std::string jsonGet(const std::string &json, const std::string &key) {
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "unknown";
    size_t colon = json.find(':', pos + search.size());
    size_t q1    = json.find('"', colon + 1);
    size_t q2    = json.find('"', q1 + 1);
    if (q1 == std::string::npos || q2 == std::string::npos) return "unknown";
    return json.substr(q1 + 1, q2 - q1 - 1);
}

static void queryYoctoVersion() {
    std::string cmd = "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "
                      "root@" + YOCTO_IP +
                      " cat /mydata/update-status.json 2>/dev/null";
    FILE *fp = popen(cmd.c_str(), "r");
    if (!fp) return;

    std::string json;
    char buf[256];
    while (fgets(buf, sizeof(buf), fp)) json += buf;
    pclose(fp);

    if (json.empty()) {
        StatusReporter::instance().pushLog(
            "[GW] Could not read Yocto version info");
        return;
    }

    StatusReporter::instance().setVersionInfo(
        jsonGet(json, "active_slot"),
        jsonGet(json, "version_a"),
        jsonGet(json, "version_b"));

    StatusReporter::instance().pushLog(
        "[GW] Yocto: slot=" + jsonGet(json, "active_slot") +
        " vA=" + jsonGet(json, "version_a") +
        " vB=" + jsonGet(json, "version_b"));
}

int main() {
    std::cout << "[OTA-GW] Starting OTA Gateway\n";

    // Start status reporter immediately — Qt app can connect at any time
    StatusReporter::instance().start();
    StatusReporter::instance().setState("idle");
    StatusReporter::instance().pushLog("[GW] OTA Gateway started");

    // Query Yocto version info at startup
    queryYoctoVersion();

    TcpReceiver    receiver(LISTEN_PORT, STAGING_FILE);
    YoctoForwarder forwarder(CAPI_DOMAIN, CAPI_INSTANCE);

    while (true) {
        StatusReporter::instance().setState("idle");
        std::cout << "[OTA-GW] Waiting for laptop...\n";

        AnnounceHeader hdr;
        if (!receiver.waitForUpdate(hdr)) {
            StatusReporter::instance().setState("failed");
            StatusReporter::instance().pushLog("[GW] Receive failed");
            continue;
        }

        StatusReporter::instance().setState("verifying");
        StatusReporter::instance().pushLog("[GW] Verifying SHA256...");

        if (!ImageVerifier::verify(STAGING_FILE, hdr.sha256)) {
            StatusReporter::instance().setState("failed");
            StatusReporter::instance().pushLog("[GW] SHA256 mismatch — rejected");
            continue;
        }

        StatusReporter::instance().pushLog("[GW] Image verified OK");

        if (!forwarder.forward(STAGING_FILE, hdr.version, hdr.sha256)) {
            StatusReporter::instance().setState("failed");
            StatusReporter::instance().pushLog("[GW] Forward to ECU failed");
            continue;
        }

        StatusReporter::instance().setState("complete");
        StatusReporter::instance().pushLog("[GW] Update complete — ECU rebooting");

        // Re-query version after update completes (give ECU time to reboot)
        std::this_thread::sleep_for(std::chrono::seconds(15));
        queryYoctoVersion();
    }
    return 0;
}
