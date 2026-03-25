#import "dsd_output.h"
#import <Foundation/Foundation.h>
#include <cstring>

namespace dsd {

// ========================================================================
// DSDOutput implementation
// ========================================================================

DSDOutput::DSDOutput()
    : m_backend(std::make_unique<CoreAudioBackend>())
    , m_dop_encoder(std::make_unique<DoPEncoder>())
    , m_current_mode(OutputMode::Auto)
    , m_current_rate(0)
    , m_current_channels(0)
    , m_is_open(false)
    , m_is_dsd_stream(false)
{
    m_config = DSDConfig::load();
}

DSDOutput::~DSDOutput() {
    close();
}

std::vector<DSDOutput::DeviceDesc> DSDOutput::enumerate_output_devices() {
    std::vector<DeviceDesc> result;
    auto devices = CoreAudioBackend::enumerate_devices();
    for (const auto& dev : devices) {
        DeviceDesc desc;
        desc.name = dev.name;
        desc.uid = dev.uid;

        if (dev.supports_native_dsd) {
            desc.name += " [Native DSD]";
        } else if (dev.supports_dop) {
            desc.name += " [DoP]";
        }

        result.push_back(std::move(desc));
    }
    return result;
}

bool DSDOutput::open(const std::string& device_uid, uint32_t sample_rate,
                     uint32_t channels, bool is_dsd) {
    close();

    auto& mgr = DSDDeviceManager::instance();
    AudioDeviceInfo device;

    if (device_uid.empty()) {
        device = mgr.get_default_device();
    } else {
        device = mgr.find_device(device_uid);
        if (device.device_id == kAudioObjectUnknown) {
            device = mgr.get_default_device();
        }
    }

    if (device.device_id == kAudioObjectUnknown) {
        NSLog(@"[DSD Output] No output device available");
        return false;
    }

    m_is_dsd_stream = is_dsd;

    OutputMode mode = m_config.output_mode;
    if (m_is_dsd_stream) {
        DSDFormat dsd_fmt = dsd_format_from_rate(sample_rate);
        if (mode == OutputMode::Auto) {
            mode = mgr.best_mode_for_device(device, dsd_fmt);
        }
        if (mode == OutputMode::DoP) {
            m_dop_encoder->set_format(dsd_fmt, channels);
        }
    } else {
        mode = OutputMode::DoP;
    }

    m_current_mode = mode;

    OutputConfig out_config = {};
    out_config.channels = channels;
    out_config.buffer_size_ms = m_config.buffer_size_ms;
    out_config.mode = mode;

    if (m_is_dsd_stream && mode == OutputMode::NativeDSD) {
        out_config.sample_rate = sample_rate;
        out_config.bits_per_sample = 1;
    } else if (m_is_dsd_stream && mode == OutputMode::DoP) {
        DSDFormat dsd_fmt = dsd_format_from_rate(sample_rate);
        out_config.sample_rate = dop_pcm_rate(dsd_fmt);
        out_config.bits_per_sample = 32;
    } else {
        out_config.sample_rate = sample_rate;
        out_config.bits_per_sample = 32;
    }

    if (!m_backend->open(device.device_id, out_config)) {
        return false;
    }

    m_current_rate = sample_rate;
    m_current_channels = channels;
    m_is_open = true;

    NSLog(@"[DSD Output] Opened: %s, rate=%u, ch=%u, mode=%s, dsd=%d",
          device.name.c_str(), sample_rate, channels,
          mode == OutputMode::NativeDSD ? "NativeDSD" : "DoP",
          m_is_dsd_stream);

    return true;
}

void DSDOutput::close() {
    if (!m_is_open) return;
    m_backend->close();
    m_dop_encoder->reset();
    m_dop_buffer.clear();
    m_is_open = false;
    m_is_dsd_stream = false;
}

bool DSDOutput::write(const void* data, size_t bytes, uint32_t sample_rate,
                      uint32_t channels, bool is_dsd) {
    if (!m_is_open) return false;

    if (is_dsd) {
        if (m_current_mode == OutputMode::NativeDSD) {
            return write_dsd_native(data, bytes);
        } else {
            return write_dsd_dop(data, bytes, channels);
        }
    } else {
        return write_pcm(data, bytes);
    }
}

bool DSDOutput::write_dsd_dop(const void* data, size_t bytes, uint32_t channels) {
    // TODO: DoP encoding path - currently PCM path is used via fb2k_output
    return true;
}

bool DSDOutput::write_dsd_native(const void* data, size_t bytes) {
    return true;
}

bool DSDOutput::write_pcm(const void* data, size_t bytes) {
    return true;
}

bool DSDOutput::start() {
    if (!m_is_open) return false;
    return m_backend->start();
}

bool DSDOutput::pause(bool paused) {
    if (!m_is_open) return false;
    return m_backend->pause(paused);
}

bool DSDOutput::stop() {
    if (!m_is_open) return false;
    return m_backend->stop();
}

void DSDOutput::flush() {
    if (!m_is_open) return;
    m_backend->flush();
    m_dop_encoder->reset();
}

bool DSDOutput::is_playing() const {
    return m_is_open && m_backend->is_playing();
}

bool DSDOutput::is_paused() const {
    return m_is_open && !m_backend->is_playing() && m_backend->is_open();
}

double DSDOutput::get_latency() const {
    if (!m_is_open) return 0.0;
    return m_backend->get_latency();
}

bool DSDOutput::set_volume(float volume) {
    if (!m_is_open) return false;
    return m_backend->set_volume(volume);
}

float DSDOutput::get_volume() const {
    if (!m_is_open) return 1.0f;
    return m_backend->get_volume();
}

std::string DSDOutput::get_device_name() const {
    if (!m_is_open) return "";
    return m_backend->get_device_info().name;
}

} // namespace dsd
