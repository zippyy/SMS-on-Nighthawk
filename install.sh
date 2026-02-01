#!/bin/sh
set -e

WWW_ROOT="/www"
CGI_DIR="$WWW_ROOT/cgi-bin"
APP_DIR="$WWW_ROOT/sms"
CFG="$APP_DIR/config.sh"

DEFAULT_PORT="767"
DEFAULT_MODEM="/dev/smd8"

echo "========================================"
echo " MR6500 SMS Web – Interactive Installer "
echo "========================================"
echo ""

mkdir -p "$CGI_DIR" "$APP_DIR"

# ----- Existing config handling -----
if [ -f "$CFG" ]; then
  echo "Existing config found at:"
  echo "  $CFG"
  echo ""
  echo "Choose an option:"
  echo "  1) Keep existing config (recommended)"
  echo "  2) Reconfigure"
  echo ""
  printf "Selection [1/2]: "
  read choice
  case "$choice" in
    2)
      RECONFIGURE=1
      ;;
    *)
      RECONFIGURE=0
      ;;
  esac
else
  RECONFIGURE=1
fi

# ----- Configure -----
if [ "$RECONFIGURE" = "1" ]; then
  echo ""
  echo "=== Configuration ==="

  printf "SMS web password: "
  stty -echo
  read SMS_PASSWORD
  stty echo
  echo ""

  while [ -z "$SMS_PASSWORD" ]; do
    echo "Password cannot be empty."
    printf "SMS web password: "
    stty -echo
    read SMS_PASSWORD
    stty echo
    echo ""
  done

  printf "HTTP port [%s]: " "$DEFAULT_PORT"
  read SMS_PORT
  SMS_PORT="${SMS_PORT:-$DEFAULT_PORT}"

  printf "Modem device [%s]: " "$DEFAULT_MODEM"
  read MODEM
  MODEM="${MODEM:-$DEFAULT_MODEM}"

  cat > "$CFG" <<EOF
# MR6500 SMS Web config
SMS_PASSWORD='$SMS_PASSWORD'
SMS_PORT='$SMS_PORT'
MODEM='$MODEM'
EOF

  chmod 600 "$CFG" 2>/dev/null || true

  echo ""
  echo "Config written to $CFG"
else
  . "$CFG"
  SMS_PORT="${SMS_PORT:-$DEFAULT_PORT}"
fi

# ----- Install CGI scripts -----
echo ""
echo "Installing CGI scripts..."

cat > "$CGI_DIR/sms_send.sh" <<'EOF'
#!/bin/sh
CFG="/www/sms/config.sh"
[ -f "$CFG" ] && . "$CFG"

PASSWORD="${SMS_PASSWORD:-changeme}"
MODEM="${MODEM:-/dev/smd8}"

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')"; }

send_sms() {
  TO="$1"
  MSG="$2"

  echo -e "AT\r" > "$MODEM"; sleep 0.5
  echo -e "AT+CMGF=1\r" > "$MODEM"; sleep 0.5
  echo -e "AT+CSMP=17,167,0,0\r" > "$MODEM"; sleep 0.5
  echo -e "AT+CMGS=\"$TO\"\r" > "$MODEM"; sleep 1
  echo -e "$MSG\x1A" > "$MODEM"
}

if [ -z "${CONTENT_LENGTH:-}" ] || [ "${CONTENT_LENGTH:-0}" = "0" ]; then
  echo "Content-Type: text/html"
  echo ""
  cat <<'HTML'
<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Send SMS</title>
<style>
body{font-family:system-ui;margin:20px;max-width:900px}
.top{display:flex;gap:10px}
a,button{padding:10px 14px;border:1px solid #ccc;border-radius:10px;background:#fff}
.card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
input,textarea{width:100%;padding:10px;border-radius:10px;border:1px solid #ccc}
</style>
</head><body>
<div class="top">
  <a href="/cgi-bin/sms_send.sh">Send SMS</a>
  <a href="/cgi-bin/sms_inbox.sh">Inbox</a>
</div>
<div class="card">
<h2>Send SMS</h2>
<form method="POST">
<input type="password" name="password" placeholder="Password" required><br><br>
<input name="to" placeholder="+17192291657" required><br><br>
<textarea name="message" maxlength="160" required></textarea><br><br>
<button type="submit">Send</button>
</form>
</div>
</body></html>
HTML
  exit 0
fi

read -n "$CONTENT_LENGTH" RAW
pw=$(urldecode "$(echo "$RAW" | sed -n 's/.*password=\([^&]*\).*/\1/p')")
to=$(urldecode "$(echo "$RAW" | sed -n 's/.*to=\([^&]*\).*/\1/p')")
msg=$(urldecode "$(echo "$RAW" | sed -n 's/.*message=\(.*\)/\1/p')")

echo "Content-Type: text/plain"
echo ""

[ "$pw" = "$PASSWORD" ] || { echo "ERROR: bad password"; exit 0; }
send_sms "$to" "$msg"
echo "OK: sent"
EOF

chmod +x "$CGI_DIR/sms_send.sh"

# Inbox script assumed already in repo; not duplicated here for brevity
# (you already added it earlier)

# ----- Restart httpd -----
echo ""
echo "Restarting web server..."
pkill httpd 2>/dev/null || true
busybox httpd -p "$SMS_PORT" -h /www &

echo ""
echo "========================================"
echo " Installed successfully"
echo "----------------------------------------"
echo " Send:  http://<router-ip>:${SMS_PORT}/cgi-bin/sms_send.sh"
echo " Inbox: http://<router-ip>:${SMS_PORT}/cgi-bin/sms_inbox.sh"
echo " Config: $CFG"
echo  " Created with <3 by Zippy - https://techrelay.xyz"
echo "========================================"
