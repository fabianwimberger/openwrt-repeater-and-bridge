#!/usr/bin/env bash
set -euo pipefail

# Deploy firmware to an existing OpenWrt device
#
# Usage: ./deploy.sh <device_ip> <root_password>
#
# Examples:
#   ./deploy.sh 192.168.1.100 admin
#   ./deploy.sh 192.168.1.50 mypassword

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << 'EOF'
Deploy firmware to an existing OpenWrt device

Usage:
  ./deploy.sh <device_ip> <root_password>

Arguments:
  device_ip      IP address of the OpenWrt device
  root_password  Root password for the device

Example:
  ./deploy.sh 192.168.1.100 admin

Requirements:
  - sshpass must be installed
  - Firmware must exist in output/ directory
  - Device must be running OpenWrt and accessible via SSH

EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

DEVICE_IP="${1:-}"
ROOT_PASSWORD="${2:-}"

# Validation
if [[ -z "$DEVICE_IP" || -z "$ROOT_PASSWORD" ]]; then
    echo -e "${RED}Error: device_ip and root_password are required${NC}"
    echo ""
    show_help
    exit 1
fi

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required${NC}"
    echo ""
    echo "Install:"
    echo "  Debian/Ubuntu: sudo apt-get install sshpass"
    echo "  macOS:         brew install sshpass"
    exit 1
fi

# Find firmware
FIRMWARE=$(find output -name '*-sysupgrade.bin' -type f 2>/dev/null | head -1)
if [[ -z "$FIRMWARE" ]]; then
    echo -e "${RED}Error: No firmware found in output/${NC}"
    echo "Run ./build.sh first to create firmware"
    exit 1
fi

FIRMWARE_NAME=$(basename "$FIRMWARE")
SSH_OPTS=(-F /dev/null -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

echo -e "${BLUE}=== Deploying Firmware ===${NC}"
echo ""
echo "Device:    $DEVICE_IP"
echo "Firmware:  $FIRMWARE_NAME"
echo ""
read -rp "Continue? [y/N] " confirm
[[ "$confirm" != [yY] ]] && echo "Aborted." && exit 0

# Test connection first
echo -n "Testing connection... "
if ! SSHPASS="$ROOT_PASSWORD" sshpass -e ssh "${SSH_OPTS[@]}" "root@${DEVICE_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
    echo -e "${RED}FAILED${NC}"
    echo ""
    echo "Could not connect to $DEVICE_IP"
    echo "Check:"
    echo "  - Is the device powered on?"
    echo "  - Is the IP address correct?"
    echo "  - Is the root password correct?"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Upload firmware
echo -n "Uploading firmware... "
if ! SSHPASS="$ROOT_PASSWORD" sshpass -e scp -O "${SSH_OPTS[@]}" "$FIRMWARE" "root@${DEVICE_IP}:/tmp/firmware.bin" 2>/dev/null; then
    echo -e "${RED}FAILED${NC}"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Flash firmware
echo "Flashing firmware (this may take a minute)..."
echo ""
SSHPASS="$ROOT_PASSWORD" sshpass -e ssh "${SSH_OPTS[@]}" "root@${DEVICE_IP}" "sysupgrade -n /tmp/firmware.bin" 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Deploy initiated ===${NC}"
echo ""
echo "The device is now flashing and will reboot automatically."
echo "This typically takes 2-3 minutes."
echo ""
echo "After reboot, the device will be available at:"
echo "  - http://${DEVICE_IP}  (if uplink connects successfully)"
echo "  - Or check your main router's DHCP leases"
