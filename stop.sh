#!/bin/sh
set -eu
pkill httpd 2>/dev/null || true
echo "Stopped httpd."
