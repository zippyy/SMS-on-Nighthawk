#!/bin/sh
set -eu

RC="/etc/rc.local"
[ -f "$RC" ] || { echo "No /etc/rc.local found."; exit 0; }

sed -i '/busybox httpd -p .* -h \/www/d' "$RC" 2>/dev/null || true
sed -i '/pkill httpd 2>\/dev\/null; busybox httpd -p .* -h \/www \&/d' "$RC" 2>/dev/null || true

echo "Disabled start-on-boot (removed matching lines from $RC)."
