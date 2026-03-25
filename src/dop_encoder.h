#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>

namespace dsd {

// DSD format types
enum class DSDFormat : uint32_t {
    DSD64  = 2822400,   // 2.8224 MHz
    DSD128 = 5644800,   // 5.6448 MHz
    DSD256 = 11289600,  // 11.2896 MHz
    DSD512 = 22579200,  // 22.5792 MHz
};

// DoP marker bytes (alternating per frame)
static constexpr uint8_t DOP_MARKER_EVEN = 0x05;
static constexpr uint8_t DOP_MARKER_ODD  = 0xFA;

// Get the corresponding PCM sample rate for DoP transport
inline uint32_t dop_pcm_rate(DSDFormat format) {
    switch (format) {
        case DSDFormat::DSD64:  return 176400;
        case DSDFormat::DSD128: return 352800;
        case DSDFormat::DSD256: return 705600;
        case DSDFormat::DSD512: return 705600; // DSD512 uses double-rate DoP
        default: return 176400;
    }
}

// Get DSD format from sample rate
inline DSDFormat dsd_format_from_rate(uint32_t rate) {
    if (rate <= 2822400)  return DSDFormat::DSD64;
    if (rate <= 5644800)  return DSDFormat::DSD128;
    if (rate <= 11289600) return DSDFormat::DSD256;
    return DSDFormat::DSD512;
}

// Check if a sample rate is a DSD rate
inline bool is_dsd_rate(uint32_t rate) {
    return rate == 2822400 || rate == 5644800 ||
           rate == 11289600 || rate == 22579200;
}

class DoPEncoder {
public:
    DoPEncoder();
    ~DoPEncoder();

    // Reset encoder state (call when starting a new stream)
    void reset();

    // Set the DSD format being encoded
    void set_format(DSDFormat format, uint32_t channels);

    // Encode DSD data to DoP PCM frames
    // Input:  raw DSD bytes (interleaved per channel)
    //         Each byte = 8 DSD samples for one channel
    // Output: 24-bit PCM samples in 32-bit containers (interleaved)
    //         Each output sample = marker byte (MSB) + 2 DSD bytes
    // Returns number of PCM frames written
    size_t encode(const uint8_t* dsd_data, size_t dsd_bytes,
                  int32_t* pcm_output, size_t max_pcm_frames);

    // Convenience: encode to a vector
    std::vector<int32_t> encode(const uint8_t* dsd_data, size_t dsd_bytes);

    // Get current DoP marker state (for synchronization)
    bool is_even_frame() const { return m_even_frame; }

    // Get the PCM sample rate for current DSD format
    uint32_t get_pcm_rate() const { return dop_pcm_rate(m_format); }

    uint32_t get_channels() const { return m_channels; }

private:
    DSDFormat m_format;
    uint32_t  m_channels;
    bool      m_even_frame; // toggles per DoP frame for marker selection
};

} // namespace dsd
