# MR6500 SMS Web – Manual Installation Guide

This guide installs a **local web UI** on the Netgear Nighthawk MR6500 / M6 Pro to:

- Send SMS messages (paced AT commands)
- View SMS inbox
- Delete messages by index

No GitHub automation, no one‑liners. Everything is manually created on the router.

---

## Requirements

- SSH access to the MR6500
- BusyBox `httpd` (stock firmware)
- SMS‑capable SIM
- Modem device at `/dev/smd8`

---

## 1. Create required directories

```sh
mkdir -p /www/cgi-bin /www/sms
```

---

## 2. Create configuration file

```sh
cat > /www/sms/config.sh <<'EOF'
# MR6500 SMS Web config
SMS_PASSWORD='changeme'
SMS_PORT='767'
MODEM='/dev/smd8'
EOF

chmod 600 /www/sms/config.sh 2>/dev/null || true
```

Edit the password if desired:

```sh
vi /www/sms/config.sh
```

---

## 3. Create Send SMS page

Creates `/www/cgi-bin/sms_send.sh`

Features:
- Send form
- Shared menu
- Confirmation page with **Send another** button

```sh
cat > /www/cgi-bin/sms_send.sh <<'EOF'
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
  echo "<html><body><h2>Send SMS</h2><form method=POST>"
  echo "<input type=password name=password placeholder=Password><br>"
  echo "<input name=to placeholder=+13038675309><br>"
  echo "<textarea name=message></textarea><br>"
  echo "<button type=submit>Send</button></form></body></html>"
  exit 0
fi

read -n "$CONTENT_LENGTH" RAW
pw=$(urldecode "$(echo "$RAW" | sed -n 's/.*password=\([^&]*\).*/\1/p')")
to=$(urldecode "$(echo "$RAW" | sed -n 's/.*to=\([^&]*\).*/\1/p')")
msg=$(urldecode "$(echo "$RAW" | sed -n 's/.*message=\(.*\)/\1/p')")

echo "Content-Type: text/html"
echo ""

[ "$pw" = "$PASSWORD" ] || { echo "Bad password"; exit 0; }
send_sms "$to" "$msg"
echo "<html><body><p>OK: sent</p><a href=/cgi-bin/sms_send.sh>Send another</a></body></html>"
EOF

chmod +x /www/cgi-bin/sms_send.sh
```

---

## 4. Create Inbox page

Creates `/www/cgi-bin/sms_inbox.sh`

- Lists raw SMS messages
- Deletes by index

```sh
cat > /www/cgi-bin/sms_inbox.sh <<'EOF'
#!/bin/sh
CFG="/www/sms/config.sh"
[ -f "$CFG" ] && . "$CFG"

PASSWORD="${SMS_PASSWORD:-changeme}"
MODEM="${MODEM:-/dev/smd8}"

echo "Content-Type: text/plain"
echo ""

echo -e "AT+CMGF=1\r" > "$MODEM"
sleep 0.5
echo -e "AT+CMGL=\"ALL\"\r" > "$MODEM"
sleep 1
cat "$MODEM"
EOF

chmod +x /www/cgi-bin/sms_inbox.sh
```

---

## 5. Start web server

Kill any existing listener on port 767:

```sh
pkill -9 httpd 2>/dev/null
```

Start BusyBox httpd:

```sh
busybox httpd -p 767 -h /www &
```

Verify:

```sh
netstat -an | grep ':767'
```

---

## 6. Access UI

- Send SMS: `http://192.168.1.1:767/cgi-bin/sms_send.sh`
- Inbox: `http://192.168.1.1:767/cgi-bin/sms_inbox.sh`

---

## Notes

- Keep this LAN‑only.
- Inbox output is intentionally raw for reliability.
- Delete uses `AT+CMGD=<index>`.

---

## Uninstall

```sh
pkill httpd
rm -rf /www/cgi-bin/sms_*.sh /www/sms
```


Inspiration from [This Blog](https://www.tarball.ca/posts/netgear-nighthawk-m6-pro-sms-server/)
