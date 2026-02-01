#!/bin/sh
set -eu

CFG="/www/sms/config.sh"
[ -f "$CFG" ] || { echo "Missing $CFG. Run install.sh first."; exit 1; }
. "$CFG"

pkill httpd 2>/dev/null || true
busybox httpd -p "${SMS_PORT:-767}" -h /www &
echo "Started httpd on port ${SMS_PORT:-767}"
