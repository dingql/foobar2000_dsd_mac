#pragma once

#include "coreaudio_backend.h"
#include <cstdint>
#include <string>

namespace dsd {

// Plugin configuration
struct DSDConfig {
    // Output mode preference
    OutputMode output_mode = OutputMode::Auto;

    // Preferred device UID (empty = default device)
    std::string device_uid;

    // Buffer size in milliseconds
    uint32_t buffer_size_ms = 200;

    // Preferred DSD sample rate (0 = auto/passthrough)
    uint32_t preferred_dsd_rate = 0;

    // Enable DSD to PCM conversion fallback
    bool dsd_to_pcm_fallback = true;

    // DoP marker verification on output
    bool verify_dop_markers = false;

    // Load config from preferences storage
    static DSDConfig load();

    // Save config to preferences storage
    void save() const;

    // Get output mode as string
    static const char* mode_to_string(OutputMode mode);

    // Parse output mode from string
    static OutputMode mode_from_string(const char* str);
};

// ========================================================================
// Configuration UI for foobar2000 preferences
// ========================================================================

class DSDConfigPage {
public:
    DSDConfigPage();
    ~DSDConfigPage();

    // Get page name for preferences tree
    static const char* get_name() { return "DSD Output"; }
    static const char* get_parent_name() { return "Output"; }

    // Initialize UI with current config values
    void initialize();

    // Apply changes
    void apply();

    // Reset to defaults
    void reset();

    // Check if configuration has changed
    bool has_changed() const;

private:
    DSDConfig m_config;
    DSDConfig m_original;
};

} // namespace dsd
