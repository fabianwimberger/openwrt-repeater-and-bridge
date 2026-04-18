#!/usr/bin/env bash
# Builds and deploys all profiles in parallel, logging each to a separate file.
# Usage: ./upgrade-all.sh [profile1 profile2 ...]
# If no profiles are given, all profiles in ./profiles/ are built.
# Logs written to: logs/upgrade-<profile>-<timestamp>.log
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILES_DIR="${PROFILES_DIR:-./profiles}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Collect profiles
if [[ $# -gt 0 ]]; then
    PROFILES=("$@")
else
    PROFILES=()
    for f in "$PROFILES_DIR"/*.conf; do
        [[ -e "$f" ]] || continue
        name="$(basename "$f" .conf)"
        [[ "$name" == "common" ]] && continue
        PROFILES+=("$name")
    done
fi

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo "Error: no profiles found in $PROFILES_DIR"
    exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
pids=()
logs=()

for profile in "${PROFILES[@]}"; do
    log="$LOG_DIR/upgrade-${profile}-${TIMESTAMP}.log"
    logs+=("$log")
    (
        echo "=== [$(date)] START: $profile ===" | tee "$log"

        echo "--- BUILD ---" | tee -a "$log"
        "$SCRIPT_DIR/build-profile.sh" "$profile" 2>&1 | tee -a "$log"

        echo "--- DEPLOY ---" | tee -a "$log"
        "$SCRIPT_DIR/deploy-profile.sh" "$profile" 2>&1 | tee -a "$log" || true

        echo "=== [$(date)] DONE: $profile ===" | tee -a "$log"
    ) &
    pids+=($!)
    echo "Started $profile (pid $!, log: $log)"
done

echo ""
echo "All ${#PROFILES[@]} builds+deploys running in parallel. Waiting..."
echo ""

failed=()
for i in "${!pids[@]}"; do
    pid="${pids[$i]}"
    profile="${PROFILES[$i]}"
    if wait "$pid"; then
        echo "[OK]   $profile"
    else
        echo "[FAIL] $profile (exit $?)"
        failed+=("$profile")
    fi
done

echo ""
echo "=== Summary ==="
echo "Logs written to: $LOG_DIR/"
for log in "${logs[@]}"; do
    echo "  $log"
done

if [[ ${#failed[@]} -gt 0 ]]; then
    echo ""
    echo "FAILED profiles: ${failed[*]}"
    exit 1
else
    echo "All profiles upgraded successfully."
fi
