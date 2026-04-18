#!/usr/bin/env bash
# Profile-based wrapper around build.sh.
# Reads profiles from ./profiles/ in the current working directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILES_DIR="${PROFILES_DIR:-./profiles}"
BUILDER="$SCRIPT_DIR/build.sh"

usage() {
    echo "Usage: $0 <profile>"
    echo ""
    echo "Available profiles:"
    for f in "$PROFILES_DIR"/*.conf; do
        [[ -e "$f" ]] || continue
        name="$(basename "$f" .conf)"
        [[ "$name" == "common" ]] && continue
        echo "  $name"
    done
    exit 1
}

[[ $# -lt 1 ]] && usage

PROFILE_NAME="$1"
PROFILE_FILE="$PROFILES_DIR/${PROFILE_NAME}.conf"
COMMON_FILE="$PROFILES_DIR/common.conf"

[[ ! -f "$COMMON_FILE" ]] && echo "Error: common.conf not found in $PROFILES_DIR" && exit 1
[[ ! -f "$PROFILE_FILE" ]] && echo "Error: profile '$PROFILE_NAME' not found in $PROFILES_DIR" && exit 1

# shellcheck source=/dev/null
source "$COMMON_FILE"
# shellcheck source=/dev/null
source "$PROFILE_FILE"

# Derive mode from profile
if [[ "${RADIO0_DISABLED:-}" == "1" && "${STA_DEVICE:-}" == "radio1" ]]; then
    MODE="repeater-5g"
elif [[ "${RADIO1_DISABLED:-}" == "1" && "${STA_DEVICE:-}" == "radio0" ]]; then
    MODE="repeater-2g"
else
    echo "Error: Cannot determine repeater mode from profile."
    echo "       Expected one radio disabled matching STA_DEVICE."
    exit 1
fi

if [[ "$MODE" == "repeater-5g" ]]; then
    COUNTRY="${RADIO1_COUNTRY:-${RADIO0_COUNTRY:-AT}}"
else
    COUNTRY="${RADIO0_COUNTRY:-AT}"
fi

ARGS=(
    "$MODE"
    "$STA_SSID"
    "$STA_KEY"
    --profile "$OPENWRT_PROFILE"
    --target "$OPENWRT_TARGET"
    --device-ip "$DEVICE_IP"
    --mgmt-ip "$MGMT_FALLBACK_IP"
    --root-password "$ROOT_PASSWORD"
    --encryption "$STA_ENCRYPTION"
    --ap-encryption "${AP_ENCRYPTION:-psk2}"
    --country "$COUNTRY"
)

if [[ "${AP_ENABLED:-0}" == "1" ]]; then
    ARGS+=(--ap-ssid "$AP_SSID")
    ARGS+=(--ap-key "$AP_KEY")
else
    ARGS+=(--no-ap)
fi

if [[ -n "${SSH_PUBKEY:-}" ]]; then
    ARGS+=(--ssh-pubkey "$SSH_PUBKEY")
fi

exec "$BUILDER" "${ARGS[@]}"
