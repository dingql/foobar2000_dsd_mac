#pragma once

#include "coreaudio_backend.h"
#include "dop_encoder.h"
#include "dsd_device_manager.h"
#include "dsd_config.h"
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace dsd {

// ========================================================================
// DSD Output - the audio output engine
// ========================================================================

class DSDOutput {
public:
    DSDOutput();
    ~DSDOutput();

    DSDOutput(const DSDOutput&) = delete;
    DSDOutput& operator=(const DSDOutput&) = delete;

    // Open output with specified device and format
    bool open(const std::string& device_uid, uint32_t sample_rate,
              uint32_t channels, bool is_dsd);

    void close();

    // Write raw audio data
    bool write(const void* data, size_t bytes, uint32_t sample_rate,
               uint32_t channels, bool is_dsd);

    // Playback control
    bool start();
    bool pause(bool paused);
    bool stop();
    void flush();

    bool is_open() const { return m_is_open; }
    bool is_playing() const;
    bool is_paused() const;

    double get_latency() const;

    bool set_volume(float volume);
    float get_volume() const;

    OutputMode get_output_mode() const { return m_current_mode; }
    std::string get_device_name() const;

    // Enumerate audio output devices
    struct DeviceDesc {
        std::string name;
        std::string uid;
    };
    static std::vector<DeviceDesc> enumerate_output_devices();

private:
    bool write_dsd_dop(const void* data, size_t bytes, uint32_t channels);
    bool write_dsd_native(const void* data, size_t bytes);
    bool write_pcm(const void* data, size_t bytes);

    std::unique_ptr<CoreAudioBackend> m_backend;
    std::unique_ptr<DoPEncoder>       m_dop_encoder;
    DSDConfig                         m_config;

    OutputMode  m_current_mode;
    uint32_t    m_current_rate;
    uint32_t    m_current_channels;
    bool        m_is_open;
    bool        m_is_dsd_stream;

    std::vector<int32_t> m_dop_buffer;
};

} // namespace dsd
