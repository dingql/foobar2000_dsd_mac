#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <memory>
#include <mutex>
#include <atomic>
#include <string>
#include <vector>

namespace dsd {

struct AudioDeviceInfo {
    AudioDeviceID device_id = kAudioObjectUnknown;
    std::string   name;
    std::string   uid;
    uint32_t      max_channels = 0;
    bool          supports_dop = false;
    bool          supports_native_dsd = false;
    std::vector<uint32_t> supported_pcm_rates;
    std::vector<uint32_t> supported_dsd_rates;
};

enum class OutputMode { DoP, NativeDSD, Auto };

struct OutputConfig {
    uint32_t   sample_rate = 44100;
    uint32_t   channels = 2;
    uint32_t   bits_per_sample = 32;
    OutputMode mode = OutputMode::Auto;
    uint32_t   buffer_size_ms = 200;
};

class CoreAudioBackend {
public:
    CoreAudioBackend();
    ~CoreAudioBackend();

    CoreAudioBackend(const CoreAudioBackend&) = delete;
    CoreAudioBackend& operator=(const CoreAudioBackend&) = delete;

    static std::vector<AudioDeviceInfo> enumerate_devices();
    static AudioDeviceInfo get_default_device();
    static AudioDeviceInfo get_device_info(AudioDeviceID device_id);

    bool open(AudioDeviceID device_id, const OutputConfig& config);
    void close();
    bool is_open() const { return m_is_open; }

    bool start();
    bool stop();
    bool pause(bool paused);
    bool is_playing() const { return m_is_playing; }

    // Write double samples (foobar2000 audio_sample = double on 64-bit)
    bool write_double(const double* data, size_t frames, uint32_t channels);

    void flush();
    double get_latency() const;

    bool set_volume(float volume);
    float get_volume() const;

    const AudioDeviceInfo& get_device_info() const { return m_device_info; }
    const OutputConfig& get_config() const { return m_config; }

private:
    static void aq_callback(void* userData, AudioQueueRef aq, AudioQueueBufferRef buf);
    void fill_buffer(AudioQueueBufferRef buf);

    // Ring buffer (float samples)
    struct RingBuffer {
        std::vector<float> buffer;
        size_t write_pos = 0, read_pos = 0, used = 0, capacity = 0;
        std::mutex mutex;

        void allocate(size_t size);
        size_t write(const float* data, size_t count);
        size_t read(float* data, size_t count);
        void clear();
        size_t available() const { return used; }
    };

    static constexpr int NUM_BUFFERS = 3;
    static constexpr int BUFFER_FRAMES = 4096;

    void set_hog_mode(bool enable);

    AudioDeviceInfo     m_device_info;
    OutputConfig        m_config;
    AudioQueueRef       m_queue = nullptr;
    AudioQueueBufferRef m_buffers[NUM_BUFFERS] = {};
    RingBuffer          m_ring_buffer;
    float               m_volume = 1.0f;
    bool                m_is_open = false;
    bool                m_is_playing = false;
    bool                m_is_paused = false;
    bool                m_hog_mode = false;
    bool                m_is_dsd = false; // DSD/DoP mode
    std::atomic<size_t> m_total_written{0};
    std::atomic<size_t> m_total_played{0};
};

} // namespace dsd
