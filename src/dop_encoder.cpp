#include "dop_encoder.h"
#include <cstring>
#include <algorithm>

namespace dsd {

DoPEncoder::DoPEncoder()
    : m_format(DSDFormat::DSD64)
    , m_channels(2)
    , m_even_frame(true)
{
}

DoPEncoder::~DoPEncoder() = default;

void DoPEncoder::reset() {
    m_even_frame = true;
}

void DoPEncoder::set_format(DSDFormat format, uint32_t channels) {
    m_format = format;
    m_channels = channels;
    reset();
}

size_t DoPEncoder::encode(const uint8_t* dsd_data, size_t dsd_bytes,
                          int32_t* pcm_output, size_t max_pcm_frames) {
    if (!dsd_data || dsd_bytes == 0 || !pcm_output || max_pcm_frames == 0) {
        return 0;
    }

    // DoP encoding:
    // Each DoP PCM sample (24-bit in 32-bit container) contains:
    //   Bits [23:16] = DoP marker (0x05 or 0xFA, alternating per frame)
    //   Bits [15:8]  = DSD byte 1 (earlier in time)
    //   Bits [7:0]   = DSD byte 2 (later in time)
    //
    // For interleaved multi-channel DSD:
    //   DSD input: [ch0_byte0][ch1_byte0][ch0_byte1][ch1_byte1]...
    //   One DoP frame = one PCM sample per channel
    //   Each DoP frame consumes 2 DSD bytes per channel

    const size_t bytes_per_channel_per_frame = 2; // 2 DSD bytes per DoP frame per channel
    const size_t bytes_per_frame = bytes_per_channel_per_frame * m_channels;

    // How many complete DoP frames can we produce?
    size_t available_frames = dsd_bytes / bytes_per_frame;
    size_t frames_to_produce = std::min(available_frames, max_pcm_frames);

    size_t dsd_offset = 0;
    size_t pcm_offset = 0;

    for (size_t frame = 0; frame < frames_to_produce; ++frame) {
        uint8_t marker = m_even_frame ? DOP_MARKER_EVEN : DOP_MARKER_ODD;

        for (uint32_t ch = 0; ch < m_channels; ++ch) {
            // Read 2 DSD bytes for this channel
            // DSD data is interleaved: [ch0][ch1]...[chN][ch0][ch1]...
            uint8_t dsd_byte1 = dsd_data[dsd_offset + ch];
            uint8_t dsd_byte2 = dsd_data[dsd_offset + m_channels + ch];

            // Pack into 24-bit DoP sample (left-justified in 32-bit)
            // Format: [marker:8][dsd1:8][dsd2:8][padding:8]
            int32_t dop_sample = (static_cast<int32_t>(marker) << 24) |
                                 (static_cast<int32_t>(dsd_byte1) << 16) |
                                 (static_cast<int32_t>(dsd_byte2) << 8);

            pcm_output[pcm_offset + ch] = dop_sample;
        }

        dsd_offset += bytes_per_frame;
        pcm_offset += m_channels;
        m_even_frame = !m_even_frame;
    }

    return frames_to_produce;
}

std::vector<int32_t> DoPEncoder::encode(const uint8_t* dsd_data, size_t dsd_bytes) {
    if (!dsd_data || dsd_bytes == 0) {
        return {};
    }

    const size_t bytes_per_frame = 2 * m_channels;
    size_t max_frames = dsd_bytes / bytes_per_frame;
    size_t total_samples = max_frames * m_channels;

    std::vector<int32_t> output(total_samples);
    size_t frames = encode(dsd_data, dsd_bytes, output.data(), max_frames);
    output.resize(frames * m_channels);
    return output;
}

} // namespace dsd
