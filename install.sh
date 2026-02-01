#!/bin/sh
set -eu

: "${SMS_PORT:=767}"
: "${SMS_PASSWORD:=changeme}"

WWW_ROOT="/www"
CGI_DIR="$WWW_ROOT/cgi-bin"
APP_DIR="$WWW_ROOT/sms"
CFG="$APP_DIR/config.sh"

# If run from wget pipe, we won't have local files.
# Detect and self-fetch the repo scripts (raw GitHub) if needed.
# NOTE: users should run the one-liner from README which executes this file directly from GitHub,
# so local files are not present; we install embedded CGI payload below.

mkdir -p "$CGI_DIR" "$APP_DIR"

# Create config if missing (don’t overwrite existing)
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<EOF
# MR6500 SMS Web config
SMS_PASSWORD='${SMS_PASSWORD}'
SMS_PORT='${SMS_PORT}'
MODEM='/dev/smd8'
EOF
  chmod 600 "$CFG" 2>/dev/null || true
fi

# Install sms_send.sh
cat > "$CGI_DIR/sms_send.sh" <<'EOF_SEND'
#!/bin/sh
# MR6500 SMS Sender – paced AT commands (BusyBox httpd CGI)

CFG="/www/sms/config.sh"
[ -f "$CFG" ] && . "$CFG"

PASSWORD="${SMS_PASSWORD:-changeme}"
MODEM="${MODEM:-/dev/smd8}"

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')"; }

send_sms() {
  TO="$1"
  MSG="$2"

  echo -e "AT\r" > "$MODEM"
  sleep 0.5
  echo -e "AT+CMGF=1\r" > "$MODEM"
  sleep 0.5
  echo -e "AT+CSMP=17,167,0,0\r" > "$MODEM"
  sleep 0.5
  echo -e "AT+CMGS=\"$TO\"\r" > "$MODEM"
  sleep 1
  echo -e "$MSG\x1A" > "$MODEM"
}

# GET: UI
if [ -z "${CONTENT_LENGTH:-}" ] || [ "${CONTENT_LENGTH:-0}" = "0" ]; then
  echo "Content-Type: text/html"
  echo ""
  cat <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MR6500 SMS Sender</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn, button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
  .card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
  .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  label{font-size:13px;color:#555}
  input,textarea{width:100%;padding:10px;border:1px solid #ccc;border-radius:10px;font-size:16px}
  textarea{min-height:110px;resize:vertical}
  .muted{color:#666;font-size:13px}
  pre{background:#f6f6f6;border-radius:10px;padding:12px;white-space:pre-wrap}
</style>
</head>
<body>
  <div class="top">
    <a class="btn" href="/cgi-bin/sms_send.sh">Send SMS</a>
    <a class="btn" href="/cgi-bin/sms_inbox.sh">Inbox</a>
  </div>

  <div class="card">
    <h2>Send SMS</h2>
    <p class="muted">E.164 number required (e.g. +17192291657). Uses paced AT commands.</p>

    <form method="POST">
      <div class="row">
        <div>
          <label>Password</label>
          <input type="password" name="password" required>
        </div>
        <div>
          <label>To (E.164)</label>
          <input type="text" name="to" placeholder="+17192291657" maxlength="16" required>
        </div>
      </div>

      <label>Message (1–160)</label>
      <textarea name="message" maxlength="160" required></textarea>

      <button type="submit">Send SMS</button>
      <p class="muted">Created with <3 by Zippy -  <a href="https://techrelay.xyz">Tech Relay</p>
    </form>
  </div>
</body>
</html>
HTML
  exit 0
fi

# POST
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
<title>MR6500 SMS Sender</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn, button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
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
echo "$to" | grep -qE '^\+[0-9]{8,15}$' || fail "ERROR: invalid number (use +###########)"
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

# Install sms_inbox.sh
cat > "$CGI_DIR/sms_inbox.sh" <<'EOF_INBOX'
#!/bin/sh
# MR6500 SMS Inbox Viewer (BusyBox httpd CGI)

CFG="/www/sms/config.sh"
[ -f "$CFG" ] && . "$CFG"

PASSWORD="${SMS_PASSWORD:-changeme}"
MODEM="${MODEM:-/dev/smd8}"

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')"; }

get_qs() {
  echo "${REQUEST_URI#*\?}" | grep -q '=' && echo "${REQUEST_URI#*\?}" || echo ""
}

qs_get() {
  KEY="$1"
  echo "$QS" | tr '&' '\n' | sed -n "s/^${KEY}=//p" | head -n 1
}

read_modem_block() {
  i=0
  while [ $i -lt 80 ]; do
    if read -t 0.2 line < "$MODEM"; then
      echo "$line"
    fi
    i=$((i+1))
  done
}

at_cmd() {
  CMD="$1"
  echo -e "${CMD}\r" > "$MODEM"
  sleep 0.4
  read_modem_block
}

escape_html() { echo "$1" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

echo "Content-Type: text/html"
echo ""

QS="$(get_qs)"
pw="$(urldecode "$(qs_get password)")"
del="$(urldecode "$(qs_get delete)")"

cat <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MR6500 SMS Inbox</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;max-width:900px}
  .top{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  a.btn, button{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:10px;text-decoration:none;color:#111;background:#fff;cursor:pointer}
  .card{border:1px solid #ddd;border-radius:12px;padding:16px;margin-top:14px}
  input{padding:10px;border:1px solid #ccc;border-radius:10px;font-size:16px}
  pre{background:#f6f6f6;border-radius:10px;padding:12px;white-space:pre-wrap;overflow:auto}
  .muted{color:#666;font-size:13px}
  .danger{border-color:#f3b3b3}
</style>
</head>
<body>
  <div class="top">
    <a class="btn" href="/cgi-bin/sms_send.sh">Send SMS</a>
    <a class="btn" href="/cgi-bin/sms_inbox.sh">Inbox</a>
  </div>
HTML

if [ -z "$pw" ]; then
  cat <<'HTML'
  <div class="card">
    <h2>Inbox</h2>
    <p class="muted">Enter password to view messages.</p>
    <form method="GET" action="/cgi-bin/sms_inbox.sh" class="top">
      <input type="password" name="password" placeholder="Password" required>
      <button type="submit">View Inbox</button>
    </form>
  </div>
</body></html>
HTML
  exit 0
fi

if [ "$pw" != "$PASSWORD" ]; then
  cat <<'HTML'
  <div class="card danger">
    <h2>Inbox</h2>
    <p><b>ERROR:</b> bad password</p>
    <a class="btn" href="/cgi-bin/sms_inbox.sh">Try again</a>
  </div>
</body></html>
HTML
  exit 0
fi

DELETE_RESULT=""
if echo "$del" | grep -qE '^[0-9]+$'; then
  OUTD="$(at_cmd "AT+CMGD=$del")"
  DELETE_RESULT="$(echo "$OUTD" | grep -E 'OK|ERROR|\+CMS ERROR' | tail -n 3)"
fi

OUT1="$(at_cmd 'AT+CMGF=1')"
OUT2="$(at_cmd 'AT+CMGL="ALL"')"

cat <<HTML
<div class="card">
  <h2>Inbox</h2>
  <p class="muted">Raw output from <code>AT+CMGL="ALL"</code>. Delete uses the index from <code>+CMGL: &lt;idx&gt;</code>.</p>

  <div class="top">
    <a class="btn" href="/cgi-bin/sms_inbox.sh?password=$(printf "%s" "$pw" | sed 's/ /%20/g')">Refresh</a>
  </div>
HTML

if [ -n "$DELETE_RESULT" ]; then
  echo "<p class=\"muted\"><b>Delete result:</b></p><pre>$(escape_html "$DELETE_RESULT")</pre>"
fi

cat <<'HTML'
  <form method="GET" action="/cgi-bin/sms_inbox.sh" class="top" style="margin-top:12px">
    <input type="hidden" name="password" value="">
    <script>
      (function(){
        const params = new URLSearchParams(location.search);
        const pw = params.get('password') || '';
        document.querySelector('input[type="hidden"][name="password"]').value = pw;
      })();
    </script>
    <input name="delete" placeholder="Delete index (e.g. 3)">
    <button type="submit">Delete</button>
  </form>

  <h3>Raw output</h3>
HTML

RAW="$(printf "%s\n%s\n" "$OUT1" "$OUT2")"
echo "<pre>$(escape_html "$RAW")</pre>"
echo "</div></body></html>"
EOF_INBOX

chmod +x "$CGI_DIR/sms_inbox.sh"

# Restart httpd cleanly
pkill httpd 2>/dev/null || true
busybox httpd -p "$SMS_PORT" -h "$WWW_ROOT" &

echo "Installed MR6500 SMS Web."
echo "Config: $CFG"
echo "Send:  http://<router-ip>:${SMS_PORT}/cgi-bin/sms_send.sh"
echo "Inbox: http://<router-ip>:${SMS_PORT}/cgi-bin/sms_inbox.sh"
echo "Created with <3 by Zippy -  <a href="https://techrelay.xyz">Tech Relay"
