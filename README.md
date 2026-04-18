# OpenWrt Repeater Builder

[![CI](https://github.com/fabianwimberger/openwrt-repeater-and-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/fabianwimberger/openwrt-repeater-and-bridge/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Build custom OpenWrt firmware for WiFi repeaters and bridges. Your WiFi configuration is baked into the firmware—just flash and go.

## Why This Project?

Consumer WiFi extenders are black boxes with proprietary firmware, limited control, and no transparency. OpenWrt gives you full control, but building custom firmware with your WiFi credentials baked in requires navigating the ImageBuilder, UCI scripting, and network configuration — none of which is beginner-friendly.

**Goals:**
- Eliminate manual post-flash configuration by baking WiFi credentials into the firmware
- Support multiple repeater/bridge modes for different network layouts
- Work with any OpenWrt-supported device via standard profile and target identifiers

## Security Warning

> **⚠️ IMPORTANT:** The default root password is `"admin"`. You **MUST** change this via `--root-password` for any production deployment. Leaving the default password on a network-facing device is a serious security risk.

## Quick Start

```bash
# Build firmware for a 5GHz uplink with dual-band AP (recommended)
./build.sh cross-5up "MyHomeWiFi" "mywifiPassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic

# Or with a custom AP name
./build.sh cross-5up "MyHomeWiFi" "mywifiPassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --ap-ssid "GarageWiFi"
```

The firmware will be in the `output/` directory. Flash it to your device and it will automatically connect to your main WiFi and start broadcasting the extender network.

## Modes Explained

Choose the mode that fits your setup:

### Single-Band Modes

| Mode | What It Does | Best For |
|------|--------------|----------|
| **repeater-2g** | Uses 2.4GHz for both connecting to router and for clients | Maximum range, older devices, smart home devices |
| **repeater-5g** | Uses 5GHz for both connecting to router and for clients | Better speeds, less congested, shorter range |

### Cross-Band Modes (Recommended)

These use one band to connect to your main router (uplink) and broadcast WiFi on one or both bands. This gives better performance because uplink and clients don't compete for airtime.

| Mode | Uplink | Clients Connect On | Best For |
|------|--------|-------------------|----------|
| **cross-5up** | 5GHz | 2.4GHz + 5GHz | **Most setups** - fast backhaul, serve all devices |
| **cross-2up** | 2.4GHz | 2.4GHz + 5GHz | When 5GHz signal from router is weak |
| **cross-5up-2ap** | 5GHz | 2.4GHz only | IoT devices, maximum 2.4GHz range |
| **cross-2up-5ap** | 2.4GHz | 5GHz only | Isolating 5GHz clients, gaming/streaming |

### Which Mode Should I Use?

- **Most homes**: Use `cross-5up` (5GHz uplink, both bands AP)
  - Fast connection to your main router
  - Can serve both old (2.4GHz) and new (5GHz) devices
  
- **Router is far away**: Use `cross-2up` or `repeater-2g`
  - 2.4GHz has better range and wall penetration
  
- **Only IoT/smart home devices**: Use `cross-5up-2ap`
  - Most smart home devices only use 2.4GHz anyway
  - Clean 5GHz uplink won't be slowed down by 2.4GHz traffic

## Usage

### Basic Syntax

```bash
./build.sh <mode> <uplink_ssid> <uplink_key> [options]
```

### Examples

```bash
# Simple 2.4GHz repeater for a garage
./build.sh repeater-2g "HomeWiFi" "password123" \
    --profile cudy_re3000-v1 --target mediatek/filogic

# High-performance setup with custom settings
./build.sh cross-5up "HomeWiFi" "password123" \
    --profile glinet_gl-mt3000 --target mediatek/filogic \
    --ap-ssid "UpstairsWiFi" \
    --device-ip 192.168.1.50 \
    --root-password admin123

# 5GHz uplink with 2.4GHz AP only (for smart home devices)
./build.sh cross-5up-2ap "HomeWiFi" "password123" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --ap-ssid "IoT-Network"

# With SSH key for secure management
./build.sh cross-5up "HomeWiFi" "password123" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --ssh-pubkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--ap-ssid <name>` | WiFi name for the repeater | `<uplink>-EXT` |
| `--ap-key <password>` | WiFi password for the repeater | Same as uplink |
| `--device-ip <ip>` | Static IP in your main network | 192.168.1.100 |
| `--mgmt-ip <ip>` | Recovery IP if uplink fails | 192.168.2.1 |
| `--root-password <pwd>` | Admin password for the device | admin |
| `--ssh-pubkey <key>` | SSH public key for key-based login | (none) |
| `--encryption <type>` | `sae` (WPA3), `psk2` (WPA2), `sae-mixed` | sae-mixed |
| `--ap-encryption <type>` | AP encryption (defaults to `psk2`) | psk2 |
| `--no-ap` | Bridge mode: no access point, only uplink | (AP enabled) |
| `--country <code>` | Regulatory country (US, DE, GB, etc.) | US |
| `--profile <name>` | OpenWrt device profile | **(required)** |
| `--target <target>` | OpenWrt target | **(required)** |

## Deploy to Existing Device

If you already have OpenWrt running on the device, you can deploy without re-flashing:

```bash
./deploy.sh <device_ip> <root_password>

# Example
./deploy.sh 192.168.1.100 admin
```

## Supported Devices

Works with any device supported by the OpenWrt ImageBuilder. You need to know your device's **profile** and **target** — find them at:

https://downloads.openwrt.org/releases/25.12.2/targets/

```bash
# Example: Cudy RE3000 v1
./build.sh cross-5up "MyWiFi" "pass" \
    --profile "cudy_re3000-v1" \
    --target "mediatek/filogic"

# Example: GL.iNet MT3000
./build.sh cross-5up "MyWiFi" "pass" \
    --profile "glinet_gl-mt3000" \
    --target "mediatek/filogic"
```

## Requirements

- **Docker** - for building the firmware
- **sshpass** - only needed for `deploy.sh`

Install sshpass:
```bash
# Debian/Ubuntu
sudo apt-get install sshpass

# macOS
brew install sshpass
```

## How It Works

1. You specify your WiFi credentials and mode
2. The script generates a UCI defaults script (OpenWrt's first-boot configuration)
3. OpenWrt ImageBuilder bakes this configuration into the firmware
4. You flash the firmware to your device
5. On first boot, the device automatically:
   - Connects to your main WiFi
   - Sets up the repeater/bridge
   - Starts broadcasting your extender network
   - Enables relayd hotplug recovery to fix stuck IoT DHCP after upstream AP reboots

## Reliability Features

The firmware includes several reliability improvements for repeater/bridge setups:

### Hotplug Relayd Recovery

A hotplug script (`/etc/hotplug.d/iface/99-relayd-recovery`) watches the `wwan` interface. When it comes back up after an upstream AP outage, the script:
1. Restarts relayd
2. Waits 5 seconds for relayd to settle
3. Reloads WiFi to force all AP clients to reassociate with a clean DHCP state

A 60-second cooldown prevents the script from re-triggering itself when the STA reconnects after the reload.

### `disassoc_low_ack=0`

The AP interface is configured with `disassoc_low_ack='0'` to prevent clients from being disassociated when the channel is congested. This is especially important for IoT devices that may not roam aggressively.

## Troubleshooting

### Device doesn't connect to uplink
- Check that the WiFi password is correct
- Try `repeater-2g` mode - 2.4GHz has better range
- Check if your router uses WPA3 only (use `--encryption sae`)

### Can't access the device
- The device should be at the `--device-ip` you set (default: 192.168.1.100)
- If the uplink fails, connect to the fallback network at `--mgmt-ip` (default: 192.168.2.1)

### Build fails
- Make sure Docker is running
- Check that you have enough disk space
- Try running with a stable internet connection

## License

MIT License — see [LICENSE](LICENSE) file.
