#pragma once

#include "coreaudio_backend.h"
#include "dop_encoder.h"
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace dsd {

// Callback for device list changes
using DeviceChangeCallback = std::function<void()>;

class DSDDeviceManager {
public:
    static DSDDeviceManager& instance();

    // Prevent copying
    DSDDeviceManager(const DSDDeviceManager&) = delete;
    DSDDeviceManager& operator=(const DSDDeviceManager&) = delete;

    // Initialize/shutdown
    void initialize();
    void shutdown();

    // Get all output devices
    std::vector<AudioDeviceInfo> get_devices() const;

    // Get default output device
    AudioDeviceInfo get_default_device() const;

    // Find device by UID
    AudioDeviceInfo find_device(const std::string& uid) const;

    // Find device by ID
    AudioDeviceInfo find_device(AudioDeviceID device_id) const;

    // Get devices that support DSD (either DoP or native)
    std::vector<AudioDeviceInfo> get_dsd_capable_devices() const;

    // Determine the best output mode for a device
    OutputMode best_mode_for_device(const AudioDeviceInfo& device, DSDFormat format) const;

    // Refresh device list
    void refresh();

    // Register callback for device changes (hotplug)
    void set_change_callback(DeviceChangeCallback callback);

private:
    DSDDeviceManager();
    ~DSDDeviceManager();

    // CoreAudio property listener for device changes
    static OSStatus device_change_listener(AudioObjectID object_id,
                                           UInt32 num_addresses,
                                           const AudioObjectPropertyAddress addresses[],
                                           void* user_data);

    void register_listeners();
    void unregister_listeners();

    mutable std::mutex            m_mutex;
    std::vector<AudioDeviceInfo>  m_devices;
    DeviceChangeCallback          m_change_callback;
    bool                          m_initialized;
};

} // namespace dsd
