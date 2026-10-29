#!/usr/bin/env bash
# collect-wayland-logs.sh
# Safely dump and inspect GNOME Wayland login failure logs with basic credential redaction warning.

set -euo pipefail

SINCE="${1:-10 minutes ago}"
UNTIL="${2:-now}"
OUTPUT_FILE="${3:-wayland_failure_inspect.log}"

echo "=== Collecting logs between '${SINCE}' and '${UNTIL}' ==="

{
    echo "=== SYSTEM JOURNAL (Wayland / GDM / Mutter / DRM) ==="
    journalctl -b --since "${SINCE}" --until "${UNTIL}" --no-pager | \
        grep -Ei 'gnome-shell|mutter|wayland|gdm|drm|i915|xe|segfault|core|failed' || true

    echo ""
    echo "=== USER JOURNAL (Session & Shell Services) ==="
    journalctl --user -b --since "${SINCE}" --until "${UNTIL}" --no-pager | \
        grep -Ei 'gnome-shell|mutter|wayland|failed|error|segfault|core' || true
} > "${OUTPUT_FILE}"

echo "Log extracted to: ${OUTPUT_FILE} ($(wc -l < "${OUTPUT_FILE}") lines)"

echo ""
echo "=== Safety Check: Scanning for sensitive keywords (passwords, tokens, UUIDs) ==="
if grep -Ei 'password|token|uuid|private|secret|vless|vmess|shadowsocks' "${OUTPUT_FILE}" > /dev/null 2>&1; then
    echo "⚠️  WARNING: Sensitive keywords detected in log! DO NOT paste this log publicly before manual redaction."
    grep -Ein 'password|token|uuid|private|secret|vless|vmess|shadowsocks' "${OUTPUT_FILE}" | head -n 10
else
    echo "✅ No obvious credentials/tokens detected in basic keyword scan."
fi
