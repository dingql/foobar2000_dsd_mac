#import "dsd_config.h"
#import <Foundation/Foundation.h>
#include <cstring>

namespace dsd {

static NSString* const kPrefsKey_OutputMode     = @"DSDOutput_Mode";
static NSString* const kPrefsKey_DeviceUID      = @"DSDOutput_DeviceUID";
static NSString* const kPrefsKey_BufferSize     = @"DSDOutput_BufferSize";
static NSString* const kPrefsKey_PreferredRate  = @"DSDOutput_PreferredRate";
static NSString* const kPrefsKey_DSDtoPCM       = @"DSDOutput_DSDtoPCM";
static NSString* const kPrefsKey_VerifyDoP      = @"DSDOutput_VerifyDoP";

// ========================================================================
// DSDConfig
// ========================================================================

DSDConfig DSDConfig::load() {
    DSDConfig config;
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    NSString* mode_str = [defaults stringForKey:kPrefsKey_OutputMode];
    if (mode_str) {
        config.output_mode = mode_from_string([mode_str UTF8String]);
    }

    NSString* device_uid = [defaults stringForKey:kPrefsKey_DeviceUID];
    if (device_uid) {
        config.device_uid = [device_uid UTF8String];
    }

    NSInteger buffer_size = [defaults integerForKey:kPrefsKey_BufferSize];
    if (buffer_size > 0) {
        config.buffer_size_ms = static_cast<uint32_t>(buffer_size);
    }

    NSInteger rate = [defaults integerForKey:kPrefsKey_PreferredRate];
    if (rate > 0) {
        config.preferred_dsd_rate = static_cast<uint32_t>(rate);
    }

    if ([defaults objectForKey:kPrefsKey_DSDtoPCM]) {
        config.dsd_to_pcm_fallback = [defaults boolForKey:kPrefsKey_DSDtoPCM];
    }

    if ([defaults objectForKey:kPrefsKey_VerifyDoP]) {
        config.verify_dop_markers = [defaults boolForKey:kPrefsKey_VerifyDoP];
    }

    return config;
}

void DSDConfig::save() const {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    [defaults setObject:@(mode_to_string(output_mode)) forKey:kPrefsKey_OutputMode];
    [defaults setObject:@(device_uid.c_str()) forKey:kPrefsKey_DeviceUID];
    [defaults setInteger:buffer_size_ms forKey:kPrefsKey_BufferSize];
    [defaults setInteger:preferred_dsd_rate forKey:kPrefsKey_PreferredRate];
    [defaults setBool:dsd_to_pcm_fallback forKey:kPrefsKey_DSDtoPCM];
    [defaults setBool:verify_dop_markers forKey:kPrefsKey_VerifyDoP];
    [defaults synchronize];
}

const char* DSDConfig::mode_to_string(OutputMode mode) {
    switch (mode) {
        case OutputMode::DoP:       return "dop";
        case OutputMode::NativeDSD: return "native";
        case OutputMode::Auto:      return "auto";
        default:                    return "auto";
    }
}

OutputMode DSDConfig::mode_from_string(const char* str) {
    if (!str) return OutputMode::Auto;
    if (std::strcmp(str, "dop") == 0)    return OutputMode::DoP;
    if (std::strcmp(str, "native") == 0) return OutputMode::NativeDSD;
    return OutputMode::Auto;
}

// ========================================================================
// DSDConfigPage
// ========================================================================

DSDConfigPage::DSDConfigPage() {
    m_config = DSDConfig::load();
    m_original = m_config;
}

DSDConfigPage::~DSDConfigPage() = default;

void DSDConfigPage::initialize() {
    m_config = DSDConfig::load();
    m_original = m_config;
}

void DSDConfigPage::apply() {
    m_config.save();
    m_original = m_config;
    NSLog(@"[DSD Output] Configuration applied: mode=%s, device=%s, buffer=%ums",
          DSDConfig::mode_to_string(m_config.output_mode),
          m_config.device_uid.empty() ? "(default)" : m_config.device_uid.c_str(),
          m_config.buffer_size_ms);
}

void DSDConfigPage::reset() {
    m_config = DSDConfig();
    m_config.save();
    m_original = m_config;
}

bool DSDConfigPage::has_changed() const {
    return m_config.output_mode != m_original.output_mode ||
           m_config.device_uid != m_original.device_uid ||
           m_config.buffer_size_ms != m_original.buffer_size_ms ||
           m_config.preferred_dsd_rate != m_original.preferred_dsd_rate ||
           m_config.dsd_to_pcm_fallback != m_original.dsd_to_pcm_fallback ||
           m_config.verify_dop_markers != m_original.verify_dop_markers;
}

} // namespace dsd
