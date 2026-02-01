#!/bin/sh
set -eu

CFG="/www/sms/config.sh"
[ -f "$CFG" ] || { echo "Missing $CFG. Run install.sh first."; exit 1; }
. "$CFG"

RC="/etc/rc.local"
[ -f "$RC" ] || { echo "No /etc/rc.local on this firmware. You'll need a different boot hook."; exit 1; }

LINE="pkill httpd 2>/dev/null; busybox httpd -p ${SMS_PORT:-767} -h /www &"

grep -q "busybox httpd -p .* -h /www" "$RC" 2>/dev/null || \
  sed -i "/^exit 0/i $LINE\n" "$RC"

echo "Enabled start-on-boot via $RC"
