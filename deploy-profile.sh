#!/usr/bin/env bash
# Profile-based wrapper around deploy.sh.
# Reads profiles from ./profiles/ in the current working directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILES_DIR="${PROFILES_DIR:-./profiles}"
DEPLOYER="$SCRIPT_DIR/deploy.sh"

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

exec "$DEPLOYER" "$DEVICE_IP" "$ROOT_PASSWORD"
