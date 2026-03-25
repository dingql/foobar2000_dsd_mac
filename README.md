# foo_dsd_output - DSD Output Plugin for foobar2000 macOS

A foobar2000 output component for macOS that enables DSD (Direct Stream Digital) audio playback through CoreAudio to compatible USB DAC devices.

## Features

- **DoP (DSD over PCM)**: Transmits DSD data encapsulated in PCM frames using DoP markers (0x05/0xFA). Compatible with most USB DACs.
- **Native DSD**: Direct DSD bitstream output for DACs that support native DSD via CoreAudio.
- **Auto Mode**: Automatically selects the best output mode based on DAC capabilities.
- **Hot-plug Support**: Detects USB DAC connection/disconnection events.
- **Multiple DSD Rates**: Supports DSD64, DSD128, DSD256.

## Supported DSD Formats

| Format  | DSD Sample Rate | DoP PCM Rate |
|---------|----------------|--------------|
| DSD64   | 2.8224 MHz     | 176.4 kHz   |
| DSD128  | 5.6448 MHz     | 352.8 kHz   |
| DSD256  | 11.2896 MHz    | 705.6 kHz   |

## Requirements

- macOS 11.0 (Big Sur) or later
- foobar2000 v2 for macOS
- Xcode 12+ or CMake 3.20+
- A DSD-capable USB DAC (for actual DSD playback)

## Building

### With CMake

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

### With foobar2000 SDK

1. Download the foobar2000 SDK from https://www.foobar2000.org/SDK
2. Place SDK files in the `sdk/` directory
3. Build with SDK support:

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DFB2K_SDK_PATH=../sdk
cmake --build .
```

## Installation

### Method 1: Use the .fb2k-component file

After building, the file `build/foo_dsd_output.fb2k-component` is generated.
Double-click it in Finder and foobar2000 will install it automatically.

### Method 2: Direct install via CMake

```bash
cmake --build build --target install-component
```

This copies the plugin directly to:

```
~/Library/foobar2000-v2/user-components/foo_dsd_output/foo_dsd_output.component
```

Restart foobar2000 after installation.

## Configuration

In foobar2000 Preferences > Output > DSD Output:

- **Output Mode**: Auto / DoP / Native DSD
- **Output Device**: Select your USB DAC
- **Buffer Size**: Adjust playback buffer (default: 200ms)
- **DSD Sample Rate**: Auto / DSD64 / DSD128 / DSD256

## Architecture

```
src/
├── main.mm              # Plugin entry point and service registration
├── dsd_output.h/mm      # Main output component (foobar2000 interface)
├── coreaudio_backend.h/mm  # CoreAudio HAL output engine
├── dop_encoder.h/cpp    # DoP encoding (DSD -> PCM container)
├── dsd_device_manager.h/mm # Device enumeration and capability detection
└── dsd_config.h/mm      # Configuration and preferences UI
```

## How It Works

### DoP Mode
1. foobar2000 sends DSD audio data to the output component
2. The DoP encoder packs DSD bytes into 24-bit PCM frames with DoP markers
3. CoreAudio sends the PCM frames to the USB DAC
4. The DAC recognizes DoP markers and extracts the DSD bitstream

### Native DSD Mode
1. foobar2000 sends DSD audio data to the output component
2. The raw DSD bitstream is passed directly to CoreAudio
3. CoreAudio configures the USB device for DSD format
4. The DAC receives native DSD data

## License

This project is provided as-is for educational and personal use with foobar2000.
