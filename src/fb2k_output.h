#pragma once

#include <SDK/foobar2000-lite.h>
#include <SDK/output.h>
#include "coreaudio_backend.h"
#include "dsd_device_manager.h"
#include "dop_encoder.h"

class dsd_output_instance : public output_impl {
public:
    dsd_output_instance(const GUID& p_device, double p_buffer_length, bool p_dither, t_uint32 p_bitdepth);
    ~dsd_output_instance();

    // output_impl
    void on_update() override;
    void write(const audio_chunk& p_data) override;
    t_size can_write_samples() override;
    t_size get_latency_samples() override;
    void on_flush() override;
    void on_flush_changing_track() override;
    void open(audio_chunk::spec_t const& p_spec) override;
    void on_force_play() override;

    // output
    void pause(bool p_state) override;
    void volume_set(double p_val) override;
    bool is_progressing() override;

    // Static for output_entry
    static void g_enum_devices(output_device_enum_callback& p_callback);
    static GUID g_get_guid();
    static const char* g_get_name();
    static bool g_advanced_settings_query() { return false; }
    static bool g_needs_bitdepth_config() { return false; }
    static bool g_needs_dither_config() { return false; }
    static bool g_needs_device_list_prefixes() { return false; }
    static bool g_supports_multiple_streams() { return false; }
    static bool g_is_high_latency() { return false; }

private:
    std::string find_device_uid(const GUID& device_guid);
    AudioDeviceID find_device_id(const GUID& device_guid);

    std::unique_ptr<dsd::CoreAudioBackend> m_backend;
    GUID        m_device_guid;
    std::string m_device_uid;
    double      m_buffer_length;
    uint32_t    m_sample_rate = 0;
    uint32_t    m_channels = 0;
    bool        m_is_open = false;
    bool        m_is_paused = false;
    bool        m_is_started = false;
    bool        m_is_dsd = false;  // current stream is DSD (DoP rate)
    size_t      m_write_capacity = 0;
};
