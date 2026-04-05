#!/usr/bin/env bash
set -euo pipefail

# OpenWrt Repeater/Bridge Firmware Builder
#
# Build firmware with WiFi configuration pre-installed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help text
show_help() {
    cat << 'EOF'
OpenWrt Repeater/Bridge Firmware Builder

Usage:
  ./build.sh <mode> <uplink_ssid> <uplink_key> [options]

Modes:
  repeater-2g       Single band: 2.4GHz for uplink and AP
                    Best for: Maximum range, older devices

  repeater-5g       Single band: 5GHz for uplink and AP  
                    Best for: Better speeds, less congestion

  cross-5up         Cross-band: 5GHz uplink, 2.4+5GHz AP
                    Best for: High performance, modern clients

  cross-2up         Cross-band: 2.4GHz uplink, 2.4+5GHz AP
                    Best for: When 5GHz signal is weak

  cross-5up-2ap     Cross-band: 5GHz uplink, 2.4GHz AP only
                    Best for: 2.4GHz devices only, maximum range

  cross-2up-5ap     Cross-band: 2.4GHz uplink, 5GHz AP only
                    Best for: Isolating 5GHz clients

Options:
  --device-ip IP        Static IP in your network (default: 192.168.1.100)
  --mgmt-ip IP          Recovery IP if uplink fails (default: 192.168.2.1)
  --ap-ssid SSID        WiFi name for the repeater (default: <uplink>-EXT)
  --ap-key KEY          WiFi password for the repeater (default: same as uplink)
  --root-password PWD   Admin password for the device (default: admin)
  --ssh-pubkey KEY      SSH public key for key-based auth
  --encryption TYPE     WPA encryption: sae, psk2, sae-mixed (default: sae-mixed)
  --country CODE        Country code: US, DE, GB, etc. (default: US)
  --profile NAME        OpenWrt device profile (required)
  --target TARGET       OpenWrt target (required)

Examples:
  # Simple 2.4GHz repeater for garage
  ./build.sh repeater-2g "HomeWiFi" "mypassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic

  # High-performance cross-band (recommended)
  ./build.sh cross-5up "HomeWiFi" "mypassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --ap-ssid "UpstairsWiFi"

  # 5GHz uplink with 2.4GHz AP only (for IoT devices)
  ./build.sh cross-5up-2ap "HomeWiFi" "mypassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --ap-ssid "IoT-Network"

  # With custom IP and SSH key
  ./build.sh cross-5up "HomeWiFi" "mypassword" \
    --profile cudy_re3000-v1 --target mediatek/filogic \
    --device-ip 192.168.1.50 \
    --ssh-pubkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."

EOF
}

# Show usage error
usage_error() {
    echo -e "${RED}Error: $1${NC}"
    echo ""
    echo "Run './build.sh --help' for usage information"
    exit 1
}

# Check dependencies
check_deps() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is required but not installed${NC}"
        echo "Install from: https://docs.docker.com/get-docker/"
        exit 1
    fi
}

# Parse arguments
if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

MODE="${1:-}"
UPLINK_SSID="${2:-}"
UPLINK_KEY="${3:-}"

# Defaults
DEVICE_IP="192.168.1.100"
MGMT_IP="192.168.2.1"
AP_SSID=""
AP_KEY=""
ROOT_PASSWORD="admin"
SSH_PUBKEY=""
UPLINK_ENCRYPTION="sae-mixed"
AP_ENCRYPTION="psk2"
COUNTRY="US"
OPENWRT_VERSION="25.12.2"
OPENWRT_TARGET=""
OPENWRT_PROFILE=""

# Parse optional arguments
shift 3 || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --device-ip)
            DEVICE_IP="$2"
            shift 2
            ;;
        --mgmt-ip)
            MGMT_IP="$2"
            shift 2
            ;;
        --ap-ssid)
            AP_SSID="$2"
            shift 2
            ;;
        --ap-key)
            AP_KEY="$2"
            shift 2
            ;;
        --root-password)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        --ssh-pubkey)
            SSH_PUBKEY="$2"
            shift 2
            ;;
        --encryption)
            UPLINK_ENCRYPTION="$2"
            shift 2
            ;;
        --country)
            COUNTRY="$2"
            shift 2
            ;;
        --target)
            OPENWRT_TARGET="$2"
            shift 2
            ;;
        --profile)
            OPENWRT_PROFILE="$2"
            shift 2
            ;;
        *)
            usage_error "Unknown option: $1"
            ;;
    esac
done

# Validation
check_deps

if [[ -z "$MODE" ]]; then
    usage_error "Mode is required (e.g., cross-5up)"
fi

if [[ -z "$UPLINK_SSID" ]]; then
    usage_error "Uplink SSID is required"
fi

if [[ -z "$UPLINK_KEY" ]]; then
    usage_error "Uplink password is required"
fi

if [[ -z "$OPENWRT_PROFILE" ]]; then
    usage_error "--profile is required (e.g., cudy_re3000-v1). Find yours at: https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/"
fi

if [[ -z "$OPENWRT_TARGET" ]]; then
    usage_error "--target is required (e.g., mediatek/filogic). Find yours at: https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/"
fi

# Set defaults for AP
if [[ -z "$AP_SSID" ]]; then
    AP_SSID="${UPLINK_SSID}-EXT"
fi
if [[ -z "$AP_KEY" ]]; then
    AP_KEY="$UPLINK_KEY"
fi

# Validate mode and set radio configuration
case "$MODE" in
    repeater-2g)
        DESCRIPTION="2.4GHz single-band repeater"
        RADIO0_DISABLED="0"
        RADIO1_DISABLED="1"
        STA_DEVICE="radio0"
        AP_DEVICE="radio0"
        AP_DUAL="0"
        ;;
    repeater-5g)
        DESCRIPTION="5GHz single-band repeater"
        RADIO0_DISABLED="1"
        RADIO1_DISABLED="0"
        STA_DEVICE="radio1"
        AP_DEVICE="radio1"
        AP_DUAL="0"
        ;;
    cross-5up)
        DESCRIPTION="5GHz uplink with dual-band AP (recommended)"
        RADIO0_DISABLED="0"
        RADIO1_DISABLED="0"
        STA_DEVICE="radio1"
        AP_DUAL="1"
        AP0_DEVICE="radio0"
        AP1_DEVICE="radio1"
        ;;
    cross-2up)
        DESCRIPTION="2.4GHz uplink with dual-band AP"
        RADIO0_DISABLED="0"
        RADIO1_DISABLED="0"
        STA_DEVICE="radio0"
        AP_DUAL="1"
        AP0_DEVICE="radio0"
        AP1_DEVICE="radio1"
        ;;
    cross-5up-2ap)
        DESCRIPTION="5GHz uplink with 2.4GHz AP only"
        RADIO0_DISABLED="0"
        RADIO1_DISABLED="0"
        STA_DEVICE="radio1"
        AP_DUAL="0"
        AP_DEVICE="radio0"
        ;;
    cross-2up-5ap)
        DESCRIPTION="2.4GHz uplink with 5GHz AP only"
        RADIO0_DISABLED="0"
        RADIO1_DISABLED="0"
        STA_DEVICE="radio0"
        AP_DUAL="0"
        AP_DEVICE="radio1"
        ;;
    *)
        echo -e "${RED}Error: Unknown mode '$MODE'${NC}"
        echo ""
        echo "Valid modes:"
        echo "  repeater-2g    - 2.4GHz single-band"
        echo "  repeater-5g    - 5GHz single-band"
        echo "  cross-5up      - 5GHz uplink, dual AP"
        echo "  cross-2up      - 2.4GHz uplink, dual AP"
        echo "  cross-5up-2ap  - 5GHz uplink, 2.4GHz AP"
        echo "  cross-2up-5ap  - 2.4GHz uplink, 5GHz AP"
        exit 1
        ;;
esac

echo -e "${BLUE}=== OpenWrt Repeater Builder ===${NC}"
echo ""
echo -e "Mode: ${GREEN}$MODE${NC}"
echo "  $DESCRIPTION"
echo ""
echo "Network:"
echo "  Device IP: $DEVICE_IP"
echo "  Uplink:    $UPLINK_SSID"
echo "  AP Name:   $AP_SSID"
echo ""

# Generate UCI defaults
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-device-setup << 'BASECFG'
#!/bin/sh
# OpenWrt repeater/bridge setup
# Mode: {{MODE}}

# Cleanup
uci -q delete network.wwan
uci -q delete network.repeater_bridge
uci -q delete wireless.wwan
uci -q delete wireless.ap_extra
uci -q delete wireless.ap_extra2
uci -q delete wireless.default_radio0
uci -q delete wireless.default_radio1
uci -q delete network.lan.gateway
uci -q delete network.lan.dns

# LAN (fallback)
uci set network.lan.proto='static'
uci set network.lan.ipaddr='{{MGMT_IP}}'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.ignore='1'

# WWAN (uplink)
uci set network.wwan=interface
uci set network.wwan.proto='static'
uci set network.wwan.ipaddr='{{DEVICE_IP}}'
uci set network.wwan.netmask='255.255.255.0'

# Relay bridge
uci set network.repeater_bridge=interface
uci set network.repeater_bridge.proto='relay'
uci set network.repeater_bridge.local_addr='{{DEVICE_IP}}'
uci add_list network.repeater_bridge.network='lan'
uci add_list network.repeater_bridge.network='wwan'
uci set network.repeater_bridge.forward_bcast='1'
uci set network.repeater_bridge.forward_dhcp='1'

# Radios
uci set wireless.radio0.disabled='{{RADIO0_DISABLED}}'
uci set wireless.radio0.country='{{COUNTRY}}'
uci set wireless.radio1.disabled='{{RADIO1_DISABLED}}'
uci set wireless.radio1.country='{{COUNTRY}}'

# System
uci set system.@system[0].timezone='UTC'
uci commit system

# Station (uplink)
uci set wireless.wwan=wifi-iface
uci set wireless.wwan.device='{{STA_DEVICE}}'
uci set wireless.wwan.network='wwan'
uci set wireless.wwan.mode='sta'
uci set wireless.wwan.ssid='{{UPLINK_SSID}}'
uci set wireless.wwan.encryption='{{UPLINK_ENCRYPTION}}'
uci set wireless.wwan.key='{{UPLINK_KEY}}'
BASECFG

# Add AP configuration
if [[ "${AP_DUAL:-}" == "1" ]]; then
    # Dual-band AP
    cat >> files/etc/uci-defaults/99-device-setup << 'APCFG'

# Access Point - 2.4GHz
uci set wireless.ap_extra=wifi-iface
uci set wireless.ap_extra.device='{{AP0_DEVICE}}'
uci set wireless.ap_extra.network='lan'
uci set wireless.ap_extra.mode='ap'
uci set wireless.ap_extra.ssid='{{AP_SSID}}'
uci set wireless.ap_extra.encryption='{{AP_ENCRYPTION}}'
uci set wireless.ap_extra.key='{{AP_KEY}}'
uci set wireless.ap_extra.disassoc_low_ack='0'

# Access Point - 5GHz
uci set wireless.ap_extra2=wifi-iface
uci set wireless.ap_extra2.device='{{AP1_DEVICE}}'
uci set wireless.ap_extra2.network='lan'
uci set wireless.ap_extra2.mode='ap'
uci set wireless.ap_extra2.ssid='{{AP_SSID}}-5G'
uci set wireless.ap_extra2.encryption='{{AP_ENCRYPTION}}'
uci set wireless.ap_extra2.key='{{AP_KEY}}'
uci set wireless.ap_extra2.disassoc_low_ack='0'
APCFG
else
    # Single AP
    cat >> files/etc/uci-defaults/99-device-setup << 'APCFG'

# Access Point
uci set wireless.ap_extra=wifi-iface
uci set wireless.ap_extra.device='{{AP_DEVICE}}'
uci set wireless.ap_extra.network='lan'
uci set wireless.ap_extra.mode='ap'
uci set wireless.ap_extra.ssid='{{AP_SSID}}'
uci set wireless.ap_extra.encryption='{{AP_ENCRYPTION}}'
uci set wireless.ap_extra.key='{{AP_KEY}}'
uci set wireless.ap_extra.disassoc_low_ack='0'
APCFG
fi

# Final config
cat >> files/etc/uci-defaults/99-device-setup << 'FINAL'

# Root password
(echo '{{ROOT_PASSWORD}}'; echo '{{ROOT_PASSWORD}}') | passwd root

{{SSH_BLOCK}}

# Services
[ -f /etc/init.d/firewall ] && /etc/init.d/firewall disable
/etc/init.d/relayd enable

# Commit
uci commit network
uci commit wireless
uci commit dhcp

exit 0
FINAL

# Build SSH block
if [[ -n "$SSH_PUBKEY" ]]; then
    SSH_BLOCK="mkdir -p /etc/dropbear; echo '$SSH_PUBKEY' > /etc/dropbear/authorized_keys; chmod 600 /etc/dropbear/authorized_keys"
else
    SSH_BLOCK="# No SSH key configured"
fi

# Substitute variables
export MODE DEVICE_IP MGMT_IP UPLINK_SSID UPLINK_KEY UPLINK_ENCRYPTION \
       AP_SSID AP_KEY AP_ENCRYPTION ROOT_PASSWORD COUNTRY SSH_BLOCK \
       RADIO0_DISABLED RADIO1_DISABLED STA_DEVICE AP_DEVICE \
       AP0_DEVICE AP1_DEVICE AP_DUAL

envsubst < files/etc/uci-defaults/99-device-setup > files/etc/uci-defaults/99-device-setup.tmp
mv files/etc/uci-defaults/99-device-setup.tmp files/etc/uci-defaults/99-device-setup
chmod +x files/etc/uci-defaults/99-device-setup

# Build Docker image
TARGET_SLUG=$(echo "$OPENWRT_TARGET" | tr '/' '-')
DOCKER_TAG="openwrt-imagebuilder:${OPENWRT_VERSION}-${TARGET_SLUG}"

echo -e "${BLUE}Building ImageBuilder container...${NC}"
docker build \
    --build-arg "OPENWRT_VERSION=$OPENWRT_VERSION" \
    --build-arg "OPENWRT_TARGET=$OPENWRT_TARGET" \
    -t "$DOCKER_TAG" \
    -f - . << 'DOCKERFILE' 2>&1 | while read line; do echo "  $line"; done
FROM alpine:latest
ARG OPENWRT_VERSION
ARG OPENWRT_TARGET
RUN apk add --no-cache bash coreutils make gcc g++ musl-dev ncurses-dev zlib-dev \
    gawk git gettext openssl-dev libxslt rsync wget unzip python3 file perl \
    findutils grep tar zstd patch diffutils bzip2 gzip xz zstd 2>/dev/null
RUN adduser -D builder
USER builder
WORKDIR /builder
RUN TARGET_PATH=$(echo "${OPENWRT_TARGET}" | tr '/' '-') && \
    URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${OPENWRT_TARGET}/openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET_PATH}.Linux-x86_64.tar.zst" && \
    wget -q "$URL" -O imagebuilder.tar.zst && \
    tar --zstd -xf imagebuilder.tar.zst --strip-components=1 && \
    rm imagebuilder.tar.zst
ENTRYPOINT ["/bin/bash", "-c"]
DOCKERFILE

# Run ImageBuilder
mkdir -p output

echo ""
echo -e "${BLUE}Building firmware...${NC}"
echo "  Profile: $OPENWRT_PROFILE"
echo "  Target:  $OPENWRT_TARGET"
echo ""

docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "$(pwd)/files:/builder/custom-files:ro" \
    -v "$(pwd)/output:/output" \
    "$DOCKER_TAG" \
    "make image PROFILE='${OPENWRT_PROFILE}' PACKAGES='-wpad-basic-mbedtls wpad-mbedtls -dnsmasq -firewall4 -nftables -kmod-nft-offload -ppp -ppp-mod-pppoe relayd luci-proto-relay luci' FILES='/builder/custom-files' BIN_DIR='/output'" 2>&1 | while read line; do echo "  $line"; done

echo ""
echo -e "${GREEN}=== Build complete ===${NC}"
echo ""
echo "Firmware files:"
ls -lh output/*.bin 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (check output/ directory)"
echo ""
echo "Next steps:"
echo "  1. Flash the firmware to your device"
echo "  2. Device will boot with WiFi configured"
echo "  3. Access at http://$DEVICE_IP"
