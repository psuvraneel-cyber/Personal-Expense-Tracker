#!/usr/bin/env bash
# CI Safeguard Script: Check for raw Log.* calls or sensitive logcat interpolation in native Kotlin code.

echo "Checking native Kotlin layer for raw Log.* or sensitive logcat interpolation..."

MATCHES=$(grep -rnE "(^|[^a-zA-Z0-9_])Log\.(d|i|w|e|v)\(" android/app/src/main/kotlin | grep -v "SafeLog\.kt")

if [ -n "$MATCHES" ]; then
    echo "[FAIL] Found raw Log.* calls in native Kotlin code:"
    echo "$MATCHES"
    echo "Please migrate all native logging to SafeLog object (com.pet.tracker.pet.SafeLog)."
    exit 1
fi

echo "[PASS] No raw Log.* calls found in native Kotlin codebase."
exit 0
