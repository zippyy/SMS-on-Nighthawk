# MR6500 SMS Web (BusyBox)

A tiny web UI to **send SMS** and **view inbox** on the Netgear Nighthawk MR6500 / M6 Pro using `/dev/smd8`.

This uses **paced AT commands** (required on MR6500 firmware) via BusyBox `httpd` + CGI.

---

## Features
- ✅ Send SMS (E.164, 1–160 chars)
- ✅ Inbox viewer (`AT+CMGL="ALL"`)
- ✅ Delete SMS by index (`AT+CMGD=<idx>`)
- ✅ One-line Interactive install (wget)
- ✅ No Perl, no curl, no packages

---

## Manual Install 

[https://github.com/zippyy/SMS-on-Nighthawk/blob/main/manual-install.md]( Manual-Install instructions page)

## One-line install (wget)
Run on the router over SSH:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/zippyy/SMS-on-Nighthawk/main/install.sh)"
```
