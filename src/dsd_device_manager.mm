#import "dsd_device_manager.h"
#import "dop_encoder.h"
#import <Foundation/Foundation.h>

namespace dsd {

DSDDeviceManager& DSDDeviceManager::instance() {
    static DSDDeviceManager mgr;
    return mgr;
}

DSDDeviceManager::DSDDeviceManager()
    : m_initialized(false)
{
}

DSDDeviceManager::~DSDDeviceManager() {
    shutdown();
}

void DSDDeviceManager::initialize() {
    if (m_initialized) return;

    refresh();
    register_listeners();
    m_initialized = true;

    NSLog(@"[DSD Output] Device manager initialized, found %lu devices",
          (unsigned long)m_devices.size());
}

void DSDDeviceManager::shutdown() {
    if (!m_initialized) return;

    unregister_listeners();
    m_initialized = false;
}

std::vector<AudioDeviceInfo> DSDDeviceManager::get_devices() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_devices;
}

AudioDeviceInfo DSDDeviceManager::get_default_device() const {
    return CoreAudioBackend::get_default_device();
}

AudioDeviceInfo DSDDeviceManager::find_device(const std::string& uid) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    for (const auto& dev : m_devices) {
        if (dev.uid == uid) return dev;
    }
    return {};
}

AudioDeviceInfo DSDDeviceManager::find_device(AudioDeviceID device_id) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    for (const auto& dev : m_devices) {
        if (dev.device_id == device_id) return dev;
    }
    return {};
}

std::vector<AudioDeviceInfo> DSDDeviceManager::get_dsd_capable_devices() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<AudioDeviceInfo> result;

    for (const auto& dev : m_devices) {
        if (dev.supports_dop || dev.supports_native_dsd) {
            result.push_back(dev);
        }
    }

    return result;
}

OutputMode DSDDeviceManager::best_mode_for_device(const AudioDeviceInfo& device, DSDFormat format) const {
    uint32_t dsd_rate = static_cast<uint32_t>(format);

    // Check if device supports native DSD at this rate
    if (device.supports_native_dsd) {
        for (uint32_t rate : device.supported_dsd_rates) {
            if (rate == dsd_rate) {
                return OutputMode::NativeDSD;
            }
        }
    }

    // Check if device supports DoP at the corresponding PCM rate
    if (device.supports_dop) {
        uint32_t pcm_rate = dop_pcm_rate(format);
        for (uint32_t rate : device.supported_pcm_rates) {
            if (rate == pcm_rate) {
                return OutputMode::DoP;
            }
        }
    }

    // Default to DoP as it has wider compatibility
    return OutputMode::DoP;
}

void DSDDeviceManager::refresh() {
    auto devices = CoreAudioBackend::enumerate_devices();

    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_devices = std::move(devices);
    }

    NSLog(@"[DSD Output] Device list refreshed:");
    for (const auto& dev : m_devices) {
        NSLog(@"  - %s [%s] ch=%u dop=%d native_dsd=%d",
              dev.name.c_str(), dev.uid.c_str(),
              dev.max_channels, dev.supports_dop, dev.supports_native_dsd);
    }
}

void DSDDeviceManager::set_change_callback(DeviceChangeCallback callback) {
    m_change_callback = std::move(callback);
}

// ---- Listeners ----

OSStatus DSDDeviceManager::device_change_listener(AudioObjectID object_id,
                                                   UInt32 num_addresses,
                                                   const AudioObjectPropertyAddress addresses[],
                                                   void* user_data) {
    auto* self = static_cast<DSDDeviceManager*>(user_data);

    NSLog(@"[DSD Output] Audio device configuration changed");
    self->refresh();

    if (self->m_change_callback) {
        self->m_change_callback();
    }

    return noErr;
}

void DSDDeviceManager::register_listeners() {
    // Listen for device list changes
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &prop,
                                   device_change_listener, this);

    // Listen for default device changes
    prop.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &prop,
                                   device_change_listener, this);
}

void DSDDeviceManager::unregister_listeners() {
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &prop,
                                      device_change_listener, this);

    prop.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &prop,
                                      device_change_listener, this);
}

} // namespace dsd
