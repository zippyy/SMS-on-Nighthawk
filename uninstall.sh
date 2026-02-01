#!/bin/sh
set -eu

WWW_ROOT="/www"
rm -f "$WWW_ROOT/cgi-bin/sms_send.sh" 2>/dev/null || true
rm -f "$WWW_ROOT/cgi-bin/sms_inbox.sh" 2>/dev/null || true
rm -rf "$WWW_ROOT/sms" 2>/dev/null || true

pkill httpd 2>/dev/null || true
echo "Uninstalled and stopped httpd (if it was ours)."
echo "Created with <3 by Zippy - https://techrelay.xyz"
