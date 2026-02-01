#!/bin/sh
set -eu

CFG="/www/sms/config.sh"
PORT=767
if [ -f "$CFG" ]; then
  . "$CFG"
  PORT="${SMS_PORT:-767}"
fi

echo "Checking port $PORT..."
netstat -an 2>/dev/null | grep ":$PORT" || echo "Not listening."
ps | grep httpd | grep -v grep || echo "httpd not running."
