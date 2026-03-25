#import "coreaudio_backend.h"
#import "dop_encoder.h"
#import <Foundation/Foundation.h>
#include <algorithm>
#include <cstring>

namespace dsd {

// ---- RingBuffer ----

void CoreAudioBackend::RingBuffer::allocate(size_t size) {
    buffer.resize(size, 0.0f);
    capacity = size;
    write_pos = read_pos = used = 0;
}

size_t CoreAudioBackend::RingBuffer::write(const float* data, size_t count) {
    std::lock_guard<std::mutex> lock(mutex);
    size_t to_write = std::min(count, capacity - used);
    if (to_write == 0) return 0;

    size_t first = std::min(to_write, capacity - write_pos);
    std::memcpy(buffer.data() + write_pos, data, first * sizeof(float));
    if (to_write > first)
        std::memcpy(buffer.data(), data + first, (to_write - first) * sizeof(float));

    write_pos = (write_pos + to_write) % capacity;
    used += to_write;
    return to_write;
}

size_t CoreAudioBackend::RingBuffer::read(float* data, size_t count) {
    std::lock_guard<std::mutex> lock(mutex);
    size_t to_read = std::min(count, used);
    if (to_read == 0) return 0;

    size_t first = std::min(to_read, capacity - read_pos);
    std::memcpy(data, buffer.data() + read_pos, first * sizeof(float));
    if (to_read > first)
        std::memcpy(data + first, buffer.data(), (to_read - first) * sizeof(float));

    read_pos = (read_pos + to_read) % capacity;
    used -= to_read;
    return to_read;
}

void CoreAudioBackend::RingBuffer::clear() {
    std::lock_guard<std::mutex> lock(mutex);
    write_pos = read_pos = used = 0;
}

// ---- CoreAudioBackend ----

CoreAudioBackend::CoreAudioBackend() = default;
CoreAudioBackend::~CoreAudioBackend() { close(); }

// ---- Device enumeration (unchanged) ----

std::vector<AudioDeviceInfo> CoreAudioBackend::enumerate_devices() {
    std::vector<AudioDeviceInfo> devices;
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 data_size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &prop, 0, nullptr, &data_size) != noErr || data_size == 0)
        return devices;

    std::vector<AudioDeviceID> ids(data_size / sizeof(AudioDeviceID));
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop, 0, nullptr, &data_size, ids.data()) != noErr)
        return devices;

    for (AudioDeviceID dev_id : ids) {
        AudioObjectPropertyAddress sp = {
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 ss = 0;
        if (AudioObjectGetPropertyDataSize(dev_id, &sp, 0, nullptr, &ss) != noErr || ss == 0)
            continue;
        AudioDeviceInfo info = get_device_info(dev_id);
        if (info.max_channels > 0)
            devices.push_back(std::move(info));
    }
    return devices;
}

AudioDeviceInfo CoreAudioBackend::get_default_device() {
    AudioDeviceID default_id = kAudioObjectUnknown;
    UInt32 size = sizeof(default_id);
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop, 0, nullptr, &size, &default_id) != noErr)
        return {};
    return get_device_info(default_id);
}

AudioDeviceInfo CoreAudioBackend::get_device_info(AudioDeviceID device_id) {
    AudioDeviceInfo info = {};
    info.device_id = device_id;

    CFStringRef name_ref = nullptr;
    UInt32 size = sizeof(name_ref);
    AudioObjectPropertyAddress prop = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(device_id, &prop, 0, nullptr, &size, &name_ref) == noErr && name_ref) {
        char buf[256];
        if (CFStringGetCString(name_ref, buf, sizeof(buf), kCFStringEncodingUTF8))
            info.name = buf;
        CFRelease(name_ref);
    }

    CFStringRef uid_ref = nullptr;
    size = sizeof(uid_ref);
    prop.mSelector = kAudioDevicePropertyDeviceUID;
    prop.mScope = kAudioObjectPropertyScopeGlobal;
    if (AudioObjectGetPropertyData(device_id, &prop, 0, nullptr, &size, &uid_ref) == noErr && uid_ref) {
        char buf[256];
        if (CFStringGetCString(uid_ref, buf, sizeof(buf), kCFStringEncodingUTF8))
            info.uid = buf;
        CFRelease(uid_ref);
    }

    prop.mSelector = kAudioDevicePropertyStreamConfiguration;
    prop.mScope = kAudioObjectPropertyScopeOutput;
    UInt32 config_size = 0;
    if (AudioObjectGetPropertyDataSize(device_id, &prop, 0, nullptr, &config_size) == noErr && config_size > 0) {
        std::vector<uint8_t> buf(config_size);
        auto* bl = reinterpret_cast<AudioBufferList*>(buf.data());
        if (AudioObjectGetPropertyData(device_id, &prop, 0, nullptr, &config_size, bl) == noErr)
            for (UInt32 i = 0; i < bl->mNumberBuffers; ++i)
                info.max_channels += bl->mBuffers[i].mNumberChannels;
    }

    prop.mSelector = kAudioDevicePropertyAvailableNominalSampleRates;
    UInt32 rates_size = 0;
    if (AudioObjectGetPropertyDataSize(device_id, &prop, 0, nullptr, &rates_size) == noErr && rates_size > 0) {
        std::vector<AudioValueRange> ranges(rates_size / sizeof(AudioValueRange));
        if (AudioObjectGetPropertyData(device_id, &prop, 0, nullptr, &rates_size, ranges.data()) == noErr) {
            const uint32_t dop_rates[] = { 176400, 352800, 705600 };
            for (auto& r : ranges)
                for (uint32_t rate : dop_rates)
                    if (rate >= r.mMinimum && rate <= r.mMaximum) {
                        info.supported_pcm_rates.push_back(rate);
                        info.supports_dop = true;
                    }
        }
    }
    return info;
}

// ---- Open / Close using AudioQueue ----

bool CoreAudioBackend::open(AudioDeviceID device_id, const OutputConfig& config) {
    close();

    m_device_info = get_device_info(device_id);
    m_config = config;

    // Set device sample rate - critical for DoP (must be exact, no SRC allowed)
    Float64 desired_rate = static_cast<Float64>(config.sample_rate);
    AudioObjectPropertyAddress rate_prop = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    Float64 current_rate = 0;
    UInt32 rate_size = sizeof(current_rate);
    AudioObjectGetPropertyData(device_id, &rate_prop, 0, nullptr, &rate_size, &current_rate);

    if (current_rate != desired_rate) {
        NSLog(@"[DSD Output] Switching device rate: %.0f -> %.0f", current_rate, desired_rate);
        OSStatus rs = AudioObjectSetPropertyData(device_id, &rate_prop, 0, nullptr,
                                                  sizeof(desired_rate), &desired_rate);
        if (rs != noErr) {
            NSLog(@"[DSD Output] WARNING: Failed to set device rate to %.0f (err=%d)", desired_rate, (int)rs);
        }

        // Wait for the rate to actually change (up to 500ms)
        for (int retry = 0; retry < 10; ++retry) {
            usleep(50000); // 50ms
            current_rate = 0;
            AudioObjectGetPropertyData(device_id, &rate_prop, 0, nullptr, &rate_size, &current_rate);
            if (current_rate == desired_rate) break;
        }

        AudioObjectGetPropertyData(device_id, &rate_prop, 0, nullptr, &rate_size, &current_rate);
        NSLog(@"[DSD Output] Device rate now: %.0f (wanted %.0f)", current_rate, desired_rate);

        if (current_rate != desired_rate) {
            NSLog(@"[DSD Output] WARNING: Device rate mismatch! Audio may not play correctly.");
        }
    } else {
        NSLog(@"[DSD Output] Device already at %.0fHz", current_rate);
    }

    // Create AudioQueue with float32 interleaved format
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate = config.sample_rate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel = 32;
    fmt.mChannelsPerFrame = config.channels;
    fmt.mBytesPerFrame = config.channels * sizeof(float);
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = fmt.mBytesPerFrame;

    // Use NULL runloop -> AudioQueue creates its own internal thread for callbacks
    OSStatus status = AudioQueueNewOutput(&fmt, aq_callback, this,
                                          NULL, NULL,
                                          0, &m_queue);
    if (status != noErr) {
        NSLog(@"[DSD Output] AudioQueueNewOutput failed: %d", (int)status);
        return false;
    }

    // Set the output device on the queue
    CFStringRef uid_str = CFStringCreateWithCString(kCFAllocatorDefault,
                                                     m_device_info.uid.c_str(),
                                                     kCFStringEncodingUTF8);
    if (uid_str) {
        AudioQueueSetProperty(m_queue, kAudioQueueProperty_CurrentDevice,
                              &uid_str, sizeof(uid_str));
        CFRelease(uid_str);
    }

    // Allocate buffers
    UInt32 buf_size = BUFFER_FRAMES * fmt.mBytesPerFrame;
    for (int i = 0; i < NUM_BUFFERS; ++i) {
        status = AudioQueueAllocateBuffer(m_queue, buf_size, &m_buffers[i]);
        if (status != noErr) {
            NSLog(@"[DSD Output] AudioQueueAllocateBuffer failed: %d", (int)status);
            AudioQueueDispose(m_queue, true);
            m_queue = nullptr;
            return false;
        }
    }

    // Ring buffer: generous size
    size_t ring_samples = config.sample_rate * config.channels * 2; // 2 seconds
    m_ring_buffer.allocate(ring_samples);

    m_total_written = 0;
    m_total_played = 0;
    m_is_dsd = (config.sample_rate == 176400 || config.sample_rate == 352800 || config.sample_rate == 705600);
    m_is_open = true;

    // Enable hog mode (exclusive access) to prevent other apps from interfering
    set_hog_mode(true);

    NSLog(@"[DSD Output] Opened: %s, rate=%u, ch=%u, dsd=%d (AudioQueue)",
          m_device_info.name.c_str(), config.sample_rate, config.channels, m_is_dsd);
    return true;
}

void CoreAudioBackend::close() {
    if (!m_is_open) return;
    stop();
    set_hog_mode(false);
    if (m_queue) {
        AudioQueueDispose(m_queue, true);
        m_queue = nullptr;
    }
    m_ring_buffer.clear();
    m_is_open = false;
    NSLog(@"[DSD Output] Closed");
}

void CoreAudioBackend::set_hog_mode(bool enable) {
    if (enable == m_hog_mode) return;
    if (m_device_info.device_id == kAudioObjectUnknown) return;

    AudioObjectPropertyAddress prop = {
        kAudioDevicePropertyHogMode,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    if (enable) {
        pid_t pid = getpid();
        OSStatus status = AudioObjectSetPropertyData(m_device_info.device_id, &prop,
                                                      0, nullptr, sizeof(pid), &pid);
        if (status == noErr) {
            m_hog_mode = true;
            NSLog(@"[DSD Output] Hog mode enabled (exclusive access)");
        } else {
            NSLog(@"[DSD Output] Hog mode failed: %d (non-fatal)", (int)status);
        }
    } else {
        if (m_hog_mode) {
            pid_t pid = -1;
            AudioObjectSetPropertyData(m_device_info.device_id, &prop,
                                       0, nullptr, sizeof(pid), &pid);
            m_hog_mode = false;
            NSLog(@"[DSD Output] Hog mode released");
        }
    }
}

// ---- AudioQueue callback ----

void CoreAudioBackend::aq_callback(void* userData, AudioQueueRef aq, AudioQueueBufferRef buf) {
    auto* self = static_cast<CoreAudioBackend*>(userData);
    self->fill_buffer(buf);
}

void CoreAudioBackend::fill_buffer(AudioQueueBufferRef buf) {
    size_t samples_needed = buf->mAudioDataBytesCapacity / sizeof(float);
    float* out = static_cast<float*>(buf->mAudioData);

    if (m_is_paused) {
        std::memset(out, 0, samples_needed * sizeof(float));
    } else {
        size_t read = m_ring_buffer.read(out, samples_needed);

        // Apply volume
        if (m_volume < 0.999f) {
            for (size_t i = 0; i < read; ++i)
                out[i] *= m_volume;
        }

        // Zero-fill remaining
        if (read < samples_needed)
            std::memset(out + read, 0, (samples_needed - read) * sizeof(float));

        m_total_played += read / m_config.channels;
    }

    buf->mAudioDataByteSize = static_cast<UInt32>(samples_needed * sizeof(float));
    AudioQueueEnqueueBuffer(m_queue, buf, 0, nullptr);
}

// ---- Playback control ----

bool CoreAudioBackend::start() {
    if (!m_is_open || m_is_playing || !m_queue) return false;

    // Prime buffers from ring buffer (or silence if not enough data yet)
    for (int i = 0; i < NUM_BUFFERS; ++i) {
        fill_buffer(m_buffers[i]);
    }

    OSStatus status = AudioQueueStart(m_queue, nullptr);
    if (status != noErr) {
        NSLog(@"[DSD Output] AudioQueueStart failed: %d", (int)status);
        return false;
    }

    m_is_playing = true;
    m_is_paused = false;
    NSLog(@"[DSD Output] Started (ring_buf=%zu samples)", m_ring_buffer.available());
    return true;
}

bool CoreAudioBackend::stop() {
    if (!m_is_open || !m_is_playing || !m_queue) return false;
    AudioQueueStop(m_queue, true);
    m_is_playing = false;
    NSLog(@"[DSD Output] Stopped");
    return true;
}

bool CoreAudioBackend::pause(bool paused) {
    if (!m_queue) return false;
    if (paused) {
        AudioQueuePause(m_queue);
        set_hog_mode(false);
    } else {
        set_hog_mode(true);
        AudioQueueStart(m_queue, nullptr);
    }
    m_is_paused = paused;
    return true;
}

// ---- Write ----

bool CoreAudioBackend::write_double(const double* data, size_t frames, uint32_t channels) {
    if (!m_is_open || !data || frames == 0) return false;

    size_t total = frames * channels;
    const size_t CHUNK = 4096;
    float fbuf[CHUNK];
    size_t offset = 0;

    while (offset < total) {
        size_t n = std::min(CHUNK, total - offset);
        for (size_t i = 0; i < n; ++i) {
            double v = data[offset + i];
            if (v > 1.0) v = 1.0;
            else if (v < -1.0) v = -1.0;
            fbuf[i] = static_cast<float>(v);
        }
        m_ring_buffer.write(fbuf, n);
        offset += n;
    }

    m_total_written += frames;
    return true;
}

void CoreAudioBackend::flush() {
    m_ring_buffer.clear();
    if (m_queue) {
        AudioQueueStop(m_queue, true); // immediate stop
        m_is_playing = false;
    }
    m_total_written = 0;
    m_total_played = 0;
}

double CoreAudioBackend::get_latency() const {
    if (!m_is_open || m_config.sample_rate == 0 || m_config.channels == 0) return 0.0;
    size_t buffered = m_ring_buffer.available();
    if (buffered == 0) return 0.0; // ring buffer empty = no pending data
    size_t frames = buffered / m_config.channels;
    return static_cast<double>(frames) / m_config.sample_rate;
}

bool CoreAudioBackend::set_volume(float volume) {
    m_volume = std::clamp(volume, 0.0f, 1.0f);
    if (m_queue) {
        AudioQueueSetParameter(m_queue, kAudioQueueParam_Volume, m_volume);
    }
    return true;
}

float CoreAudioBackend::get_volume() const {
    return m_volume;
}

} // namespace dsd
