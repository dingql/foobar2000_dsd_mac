#include <SDK/foobar2000-lite.h>
#include <SDK/componentversion.h>
#include <SDK/output.h>
#include <SDK/component.h>

#import <Foundation/Foundation.h>

#include "dsd_output.h"
#include "dsd_device_manager.h"
#include "dsd_config.h"

// ========================================================================
// Component version declaration
// ========================================================================
DECLARE_COMPONENT_VERSION(
    "DSD Output",
    "1.0.0",
    "DSD Output Component for foobar2000 macOS\n"
    "Supports DSD over PCM (DoP) and Native DSD output\n"
    "via CoreAudio to compatible USB DAC devices.\n\n"
    "Supported formats:\n"
    "  - DSD64  (2.8224 MHz) -> DoP @ 176.4 kHz\n"
    "  - DSD128 (5.6448 MHz) -> DoP @ 352.8 kHz\n"
    "  - DSD256 (11.2896 MHz) -> DoP @ 705.6 kHz\n\n"
    "Output modes:\n"
    "  - DoP: DSD over PCM (widest compatibility)\n"
    "  - Native DSD: Direct bitstream (best quality)\n"
    "  - Auto: Automatically select based on DAC capability"
);

VALIDATE_COMPONENT_FILENAME("foo_dsd_output.component");

// ========================================================================
// initquit - component lifecycle
// ========================================================================
class dsd_output_initquit : public initquit {
public:
    void on_init() override {
        NSLog(@"[DSD Output] Initializing...");
        dsd::DSDDeviceManager::instance().initialize();

        auto devices = dsd::DSDDeviceManager::instance().get_dsd_capable_devices();
        NSLog(@"[DSD Output] Found %lu DSD-capable devices", (unsigned long)devices.size());
        for (const auto& dev : devices) {
            NSLog(@"[DSD Output]   %s (DoP=%d, NativeDSD=%d)",
                  dev.name.c_str(), dev.supports_dop, dev.supports_native_dsd);
        }
    }

    void on_quit() override {
        NSLog(@"[DSD Output] Shutting down...");
        dsd::DSDDeviceManager::instance().shutdown();
    }
};

static initquit_factory_t<dsd_output_initquit> g_dsd_initquit;
