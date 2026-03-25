#include "fb2k_output.h"
#import <Foundation/Foundation.h>

// {A1B2C3D4-D5D0-4F00-BA00-D5D0OUTPUT01}
static const GUID g_dsd_output_guid =
    { 0xA1B2C3D4, 0xD5D0, 0x4F00, { 0xBA, 0x00, 0xD5, 0xD0, 0x00, 0x00, 0x00, 0x01 } };

// Default device GUID
// {D5D0DEF0-0000-0000-0000-000000000000}
static const GUID g_default_device_guid =
    { 0xD5D0DEF0, 0x0000, 0x0000, { 0, 0, 0, 0, 0, 0, 0, 0 } };

static GUID make_device_guid(const std::string& uid) {
    uint32_t hash = 0;
    for (char c : uid) hash = hash * 31 + static_cast<uint32_t>(c);
    GUID g = { 0xD5D0DE00, 0x0000, 0x0000, { 0, 0, 0, 0, 0, 0, 0, 0 } };
    g.Data2 = static_cast<uint16_t>(hash & 0xFFFF);
    g.Data3 = static_cast<uint16_t>((hash >> 16) & 0xFFFF);
    g.Data4[0] = static_cast<uint8_t>((hash >> 24) & 0xFF);
    g.Data4[1] = static_cast<uint8_t>((hash >> 8) & 0xFF);
    return g;
}

// ========================================================================

dsd_output_instance::dsd_output_instance(const GUID& p_device, double p_buffer_length,
                                         bool p_dither, t_uint32 p_bitdepth)
    : m_device_guid(p_device)
    , m_buffer_length(p_buffer_length)
{
    m_backend = std::make_unique<dsd::CoreAudioBackend>();
    m_device_uid = find_device_uid(p_device);
    NSLog(@"[DSD Output] Created, device=%s, buffer=%.0fms",
          m_device_uid.empty() ? "(default)" : m_device_uid.c_str(),
          p_buffer_length * 1000.0);
}

dsd_output_instance::~dsd_output_instance() {
    if (m_backend) m_backend->close();
}

std::string dsd_output_instance::find_device_uid(const GUID& device_guid) {
    if (device_guid == g_default_device_guid) return ""; // use system default
    auto devices = dsd::DSDDeviceManager::instance().get_devices();
    for (const auto& dev : devices) {
        if (make_device_guid(dev.uid) == device_guid)
            return dev.uid;
    }
    return ""; // fallback to default
}

AudioDeviceID dsd_output_instance::find_device_id(const GUID& device_guid) {
    if (device_guid == g_default_device_guid) {
        return dsd::DSDDeviceManager::instance().get_default_device().device_id;
    }
    auto devices = dsd::DSDDeviceManager::instance().get_devices();
    for (const auto& dev : devices) {
        if (make_device_guid(dev.uid) == device_guid)
            return dev.device_id;
    }
    return dsd::DSDDeviceManager::instance().get_default_device().device_id;
}

void dsd_output_instance::open(audio_chunk::spec_t const& p_spec) {
    if (m_backend->is_open()) {
        m_backend->close();
        m_is_open = false;
        m_is_started = false;
    }

    m_sample_rate = p_spec.sampleRate;
    m_channels = p_spec.chanCount;
    m_is_dsd = (p_spec.sampleRate == 176400 || p_spec.sampleRate == 352800 || p_spec.sampleRate == 705600);

    NSLog(@"[DSD Output] open: rate=%u, ch=%u, mode=%s",
          p_spec.sampleRate, p_spec.chanCount, m_is_dsd ? "DSD/DoP" : "PCM");

    AudioDeviceID device_id = find_device_id(m_device_guid);
    if (device_id == kAudioObjectUnknown) {
        throw exception_output_device_not_found();
    }

    dsd::OutputConfig config = {};
    config.sample_rate = p_spec.sampleRate;
    config.channels = p_spec.chanCount;
    config.bits_per_sample = 32;
    config.buffer_size_ms = static_cast<uint32_t>(m_buffer_length * 1000.0);
    if (config.buffer_size_ms < 100) config.buffer_size_ms = 200;

    if (!m_backend->open(device_id, config)) {
        throw exception_output_device_not_found();
    }

    m_is_open = true;
    m_is_started = false;  // wait for write() to fill data before starting
    m_write_capacity = 4096;

    NSLog(@"[DSD Output] Ready: %s at %uHz (waiting for data)",
          m_is_dsd ? "DSD/DoP" : "PCM", p_spec.sampleRate);
}

void dsd_output_instance::on_update() {
    if (!m_is_open) {
        m_write_capacity = 0;
        return;
    }

    double latency = m_backend->get_latency();
    if (latency < m_buffer_length) {
        double room = m_buffer_length - latency;
        m_write_capacity = static_cast<size_t>(room * m_sample_rate);
        if (m_write_capacity < 256) m_write_capacity = 256;
    } else {
        m_write_capacity = 0;
    }
}

void dsd_output_instance::write(const audio_chunk& p_data) {
    if (!m_is_open || !m_backend) return;

    const audio_sample* samples = p_data.get_data();
    t_size sample_count = p_data.get_sample_count();
    unsigned channels = p_data.get_channel_count();

    m_backend->write_double(samples, sample_count, channels);

    // Restart if needed (after flush/seek)
    if (!m_is_started) {
        m_backend->start();
        m_is_started = true;
    }
}

t_size dsd_output_instance::can_write_samples() {
    return m_write_capacity;
}

t_size dsd_output_instance::get_latency_samples() {
    if (!m_is_open) return 0;
    return static_cast<t_size>(m_backend->get_latency() * m_sample_rate);
}

void dsd_output_instance::on_flush() {
    if (m_backend) {
        m_backend->flush();
        m_is_started = false;
    }
}

void dsd_output_instance::on_flush_changing_track() {
    on_flush();
}

void dsd_output_instance::on_force_play() {
    if (m_backend && !m_is_started) {
        m_backend->start();
        m_is_started = true;
    }
}

void dsd_output_instance::pause(bool p_state) {
    m_is_paused = p_state;
    if (m_backend) m_backend->pause(p_state);
}

void dsd_output_instance::volume_set(double p_val) {
    if (m_backend) {
        float linear = static_cast<float>(pow(10.0, p_val / 20.0));
        m_backend->set_volume(linear);
    }
}

bool dsd_output_instance::is_progressing() {
    return m_is_open && m_is_started && !m_is_paused;
}

// ---- Static ----

void dsd_output_instance::g_enum_devices(output_device_enum_callback& p_callback) {
    // Default device
    {
        const char* name = "Primary Sound Driver [DSD Auto]";
        p_callback.on_device(g_default_device_guid, name, static_cast<unsigned>(strlen(name)));
    }

    // All devices
    auto devices = dsd::DSDDeviceManager::instance().get_devices();
    for (const auto& dev : devices) {
        std::string name = dev.name + " [DSD Auto]";
        GUID guid = make_device_guid(dev.uid);
        p_callback.on_device(guid, name.c_str(), static_cast<unsigned>(name.length()));
    }
}

GUID dsd_output_instance::g_get_guid() {
    return g_dsd_output_guid;
}

const char* dsd_output_instance::g_get_name() {
    return "DSD Output";
}

// Register
static output_factory_t<dsd_output_instance> g_dsd_output_factory;
