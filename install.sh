#!/bin/sh
set -e

WWW_ROOT="/www"
CGI_DIR="$WWW_ROOT/cgi-bin"
APP_DIR="$WWW_ROOT/sms"
CFG="$APP_DIR/config.sh"

DEFAULT_PORT="767"
DEFAULT_MODEM="/dev/smd8"

kill_port_listener() {
  PORT="$1"
  PID=""

  PID="$(netstat -anp 2>/dev/null | awk -v p=":$PORT" '
    $0 ~ p && $0 ~ /LISTEN/ {
      split($NF,a,"/");
      if (a[1] ~ /^[0-9]+$/) { print a[1]; exit }
    }')"

  if [ -z "$PID" ] && command -v ss >/dev/null 2>&1; then
    PID="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '
      $0 ~ p {
        if (match($0,/pid=([0-9]+)/,m)) { print m[1]; exit }
      }')"
  fi

  if [ -z "$PID" ] && command -v lsof >/dev/null 2>&1; then
    PID="$(lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
  fi

  if [ -n "$PID" ]; then
    echo "Port $PORT is in use by PID $PID. Killing..."
    kill "$PID" 2>/dev/null || true
    sleep 0.3
    kill -9 "$PID" 2>/dev/null || true
    sleep 0.3
    return 0
  fi

  if netstat -an 2>/dev/null | grep -q ":$PORT"; then
    echo "Port $PORT is in use but PID is unknown. Killing httpd as fallback..."
    pkill httpd 2>/dev/null || true
    pkill -9 httpd 2>/dev/null || true
    sleep 0.3
  fi
}

echo "========================================"
echo " MR6500 SMS Web – Interactive Installer "
echo "========================================"
echo ""

mkdir -p "$CGI_DIR" "$APP_DIR"

# ----- Existing config handling -----
if [ -f "$CFG" ]; then
  echo "Existing config found: $CFG"
  echo "  1) Keep existing config (recommended)"
  echo "  2) Reconfigure"
  printf "Selection [1/2]: "
  read choice
  case "$choice" in
    2) RECONFIGURE=1 ;;
    *) RECONFIGURE=0 ;;
  esac
else
  RECONFIGURE=1
fi

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
  MODEM="${MODEM:-$DEFAULT_MODEM}"
fi

echo ""
echo "Installing CGI scripts..."

# ----- sms_send.sh (HTML result + Send another button) -----
cat > "$CGI_DIR/sms_send.sh" <<'EOF_SEND'
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

# GET: UI
if [ -z "${CONTENT_LENGTH:-}" ] || [ "${CONTENT_LENGTH:-0}" = "0" ]; then
  echo "Content-Type: text/html"
  echo ""
  cat <<'HTML'
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MR6500 SMS</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn,button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
  .card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
  .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  label{font-size:13px;color:#555}
  input,textarea{width:100%;padding:10px;border:1px solid #ccc;border-radius:10px;font-size:16px}
  textarea{min-height:110px;resize:vertical}
  .muted{color:#666;font-size:13px}
  pre{background:#f6f6f6;border-radius:10px;padding:12px;white-space:pre-wrap}
</style>
</head><body>
<div class="top">
  <a class="btn" href="/cgi-bin/sms_send.sh">Send SMS</a>
  <a class="btn" href="/cgi-bin/sms_inbox.sh">Inbox</a>
</div>

<div class="card">
<h2>Send SMS</h2>
<p class="muted">E.164 required (e.g. +13038675309). Max 160 chars. Made with <3 Zippyy - <a href="https://techrelay.xyz">Tech Relay</a></p>
<form method="POST">
  <div class="row">
    <div>
      <label>Password</label>
      <input type="password" name="password" required>
    </div>
    <div>
      <label>To</label>
      <input name="to" placeholder="+13038675309" maxlength="16" required>
    </div>
  </div>
  <label>Message</label>
  <textarea name="message" maxlength="160" required></textarea>
  <button type="submit">Send SMS</button>
</form>
</div>
</body></html>
HTML
  exit 0
fi

# POST: result page with "Send another"
read -n "$CONTENT_LENGTH" RAW
pw=$(urldecode "$(echo "$RAW" | sed -n 's/.*password=\([^&]*\).*/\1/p')")
to=$(urldecode "$(echo "$RAW" | sed -n 's/.*to=\([^&]*\).*/\1/p')")
msg=$(urldecode "$(echo "$RAW" | sed -n 's/.*message=\(.*\)/\1/p')")

echo "Content-Type: text/html"
echo ""

cat <<'HTML'
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MR6500 SMS</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn,button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
  .card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
  .muted{color:#666;font-size:13px}
  pre{background:#f6f6f6;border-radius:10px;padding:12px;white-space:pre-wrap}
</style>
</head><body>
<div class="top">
  <a class="btn" href="/cgi-bin/sms_send.sh">Send SMS</a>
  <a class="btn" href="/cgi-bin/sms_inbox.sh">Inbox</a>
</div>
HTML

fail() {
  MSG="$1"
  cat <<HTML
<div class="card">
  <h2>Send SMS</h2>
  <pre>$MSG</pre>
  <p class="muted"><a class="btn" href="/cgi-bin/sms_send.sh">Back</a></p>
</div>
</body></html>
HTML
  exit 0
}

[ "$pw" = "$PASSWORD" ] || fail "ERROR: bad password"
echo "$to" | grep -qE '^\+[0-9]{8,15}$' || fail "ERROR: invalid number"
[ -n "$msg" ] || fail "ERROR: empty message"
[ "$(printf "%s" "$msg" | wc -c)" -le 160 ] || fail "ERROR: message too long"

send_sms "$to" "$msg"

cat <<'HTML'
<div class="card">
  <h2>Send SMS</h2>
  <pre>OK: sent</pre>
  <p class="muted"><a class="btn" href="/cgi-bin/sms_send.sh">Send another</a></p>
</div>
</body></html>
HTML
EOF_SEND
chmod +x "$CGI_DIR/sms_send.sh"

# ----- sms_inbox.sh -----
cat > "$CGI_DIR/sms_inbox.sh" <<'EOF_INBOX'
#!/bin/sh
CFG="/www/sms/config.sh"
[ -f "$CFG" ] && . "$CFG"

PASSWORD="${SMS_PASSWORD:-changeme}"
MODEM="${MODEM:-/dev/smd8}"

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')"; }

get_qs() { echo "${REQUEST_URI#*\?}" | grep -q '=' && echo "${REQUEST_URI#*\?}" || echo ""; }
qs_get() { KEY="$1"; echo "$QS" | tr '&' '\n' | sed -n "s/^${KEY}=//p" | head -n 1; }

read_modem_block() {
  i=0
  while [ $i -lt 80 ]; do
    if read -t 0.2 line < "$MODEM"; then echo "$line"; fi
    i=$((i+1))
  done
}

at_cmd() { CMD="$1"; echo -e "${CMD}\r" > "$MODEM"; sleep 0.4; read_modem_block; }
escape_html() { echo "$1" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

echo "Content-Type: text/html"
echo ""

QS="$(get_qs)"
pw="$(urldecode "$(qs_get password)")"
del="$(urldecode "$(qs_get delete)")"

cat <<'HTML'
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MR6500 SMS Inbox</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn,button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
  .card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
  input{padding:10px;border:1px solid #ccc;border-radius:10px;font-size:16px}
  pre{background:#f6f6f6;border-radius:10px;padding:12px;white-space:pre-wrap;overflow:auto}
  .muted{color:#666;font-size:13px}
</style>
</head><body>
<div class="top">
  <a class="btn" href="/cgi-bin/sms_send.sh">Send SMS</a>
  <a class="btn" href="/cgi-bin/sms_inbox.sh">Inbox</a>
</div>
HTML

if [ -z "$pw" ]; then
  cat <<'HTML'
<div class="card">
  <h2>Inbox</h2>
  <form method="GET" action="/cgi-bin/sms_inbox.sh" class="top">
    <input type="password" name="password" placeholder="Password" required>
    <button type="submit">View</button>
  </form>
</div></body></html>
HTML
  exit 0
fi

if [ "$pw" != "$PASSWORD" ]; then
  echo '<div class="card"><h2>Inbox</h2><pre>ERROR: bad password</pre></div></body></html>'
  exit 0
fi

DEL_OUT=""
if echo "$del" | grep -qE '^[0-9]+$'; then
  TMP="$(at_cmd "AT+CMGD=$del")"
  DEL_OUT="$(echo "$TMP" | grep -E 'OK|ERROR|\+CMS ERROR' | tail -n 3)"
fi

OUT1="$(at_cmd 'AT+CMGF=1')"
OUT2="$(at_cmd 'AT+CMGL="ALL"')"
RAW="$(printf "%s\n%s\n" "$OUT1" "$OUT2")"

cat <<HTML
<div class="card">
  <h2>Inbox</h2>
  <div class="top">
    <a class="btn" href="/cgi-bin/sms_inbox.sh?password=$(printf "%s" "$pw" | sed 's/ /%20/g')">Refresh</a>
  </div>
  <p class="muted">Delete by index shown in <code>+CMGL: &lt;idx&gt;</code></p>
  <form method="GET" action="/cgi-bin/sms_inbox.sh" class="top" style="margin-top:12px">
    <input type="hidden" name="password" value="">
    <script>
      (function(){ const p=new URLSearchParams(location.search).get('password')||''; document.querySelector('input[name=password]').value=p; })();
    </script>
    <input name="delete" placeholder="Delete index (e.g. 3)">
    <button type="submit">Delete</button>
  </form>
HTML

if [ -n "$DEL_OUT" ]; then
  echo "<p class=\"muted\"><b>Delete result:</b></p><pre>$(escape_html "$DEL_OUT")</pre>"
fi

echo "<h3>Raw output</h3><pre>$(escape_html "$RAW")</pre>"
echo "</div></body></html>"
EOF_INBOX
chmod +x "$CGI_DIR/sms_inbox.sh"

echo ""
echo "Restarting web server on port $SMS_PORT..."
kill_port_listener "$SMS_PORT"
busybox httpd -p "$SMS_PORT" -h "$WWW_ROOT" &

echo ""
echo "========================================"
echo " Installed successfully"
echo "----------------------------------------"
echo " Send:  http://<router-ip>:${SMS_PORT}/cgi-bin/sms_send.sh"
echo " Inbox: http://<router-ip>:${SMS_PORT}/cgi-bin/sms_inbox.sh"
echo " Config: $CFG"
echo " Made with <3 by Zippyy - https://techrelay.xyz"
echo "========================================"
