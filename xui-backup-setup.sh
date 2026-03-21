#!/bin/bash
# ============================================================
#  XUI Backup Hub - Centralized X-UI Backup System
#  Version 2.0
#
#  GitHub  : https://github.com/Emadhabibnia1385
#  Telegram: https://t.me/EmadHabibnia
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
  clear
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║         XUI Backup Hub - Centralized Backup System       ║"
  echo "  ║        Automatic X-UI database backup management         ║"
  echo "  ╠══════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${MAGENTA}Telegram : @EmadHabibnia${CYAN}                                   ║"
  echo -e "  ║  ${MAGENTA}GitHub   : @Emadhabibnia1385${CYAN}                               ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_ok()   { echo -e "${GREEN}  [OK] $1${NC}"; }
print_info() { echo -e "${YELLOW}  [..] $1${NC}"; }
print_err()  { echo -e "${RED}  [!!] $1${NC}"; }
print_sep()  { echo -e "${CYAN}  ──────────────────────────────────────────────────────${NC}"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    print_err "This script must be run as root. Use sudo."
    exit 1
  fi
}

pause() {
  echo ""
  read -rp "  Press Enter to go back..." _
}

# ────────────────────────────────────────────────────────────
# 1. Install Backup Hub (receiver server)
# ────────────────────────────────────────────────────────────
install_hub() {
  require_root
  print_banner
  print_sep
  echo -e "  ${BOLD}Install Backup Hub (Central Server)${NC}"
  print_sep
  echo ""

  read -rp "  Upload token [default: emad]: " INPUT_TOKEN
  UPLOAD_TOKEN="${INPUT_TOKEN:-emad}"

  read -rp "  Service port [default: 8080]: " INPUT_PORT
  HUB_PORT="${INPUT_PORT:-8080}"

  echo ""
  echo -e "  ${BOLD}Web panel login credentials:${NC}"
  read -rp "  Web panel username [default: admin]: " INPUT_USER
  WEB_USER="${INPUT_USER:-admin}"

  while true; do
    read -rsp "  Web panel password: " INPUT_PASS
    echo ""
    if [ -z "$INPUT_PASS" ]; then
      print_err "Password cannot be empty."
    else
      read -rsp "  Confirm password: " INPUT_PASS2
      echo ""
      if [ "$INPUT_PASS" = "$INPUT_PASS2" ]; then
        WEB_PASS="$INPUT_PASS"
        break
      else
        print_err "Passwords do not match. Try again."
      fi
    fi
  done

  echo ""
  print_info "Creating directories..."
  mkdir -p /root/backup-hub/data/backups

  cat > /root/backup-hub/data/config.json <<EOF
{
  "upload_token": "${UPLOAD_TOKEN}",
  "web_user": "${WEB_USER}",
  "web_pass": "${WEB_PASS}"
}
EOF
  print_ok "config.json created."

  print_info "Writing backup_hub.py ..."

  cat > /root/backup-hub/backup_hub.py <<'PYEOF'
#!/usr/bin/env python3
import os, re, cgi, json, html, base64, shutil
from datetime import datetime
from zoneinfo import ZoneInfo
from urllib.parse import urlparse, parse_qs, unquote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
_PORT_PLACEHOLDER_
TZ = ZoneInfo("Asia/Tehran")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
os.makedirs(BACKUP_DIR, exist_ok=True)

def load_config():
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {"upload_token": "emad", "web_user": "admin", "web_pass": "admin"}

def safe_name(n): return re.sub(r"[^a-zA-Z0-9._-]", "_", n)
def detect_ip(h, e=""): return (e or "").strip() or h.client_address[0]
def now_stamp(): return datetime.now(TZ).strftime("%Y%m%d_%H%M%S")
def fmt_time(e): return datetime.fromtimestamp(e, TZ).strftime("%Y-%m-%d %H:%M:%S")
def fmt_size(n):
    if n < 1024: return f"{n} B"
    if n < 1048576: return f"{n/1024:.1f} KB"
    return f"{n/1048576:.2f} MB"

def list_backups():
    items = []
    for name in os.listdir(BACKUP_DIR):
        if not name.endswith(".db"): continue
        full = os.path.join(BACKUP_DIR, name)
        if not os.path.isfile(full): continue
        st = os.stat(full)
        m = re.match(r"^backup__(.+?)__(\d{8}_\d{6})\.db$", name)
        ip = m.group(1).replace("_", ".") if m else "unknown"
        items.append({"name": name, "path": full, "ip": ip,
                       "size": st.st_size, "mtime": st.st_mtime})
    return sorted(items, key=lambda x: x["mtime"], reverse=True)

def prune_old_backups():
    by_ip = {}
    for item in list_backups():
        by_ip.setdefault(item["ip"], []).append(item)
    for ip, arr in by_ip.items():
        for extra in sorted(arr, key=lambda x: x["mtime"], reverse=True)[5:]:
            try: os.remove(extra["path"])
            except: pass

def grouped_backups():
    g = {}
    for item in list_backups():
        g.setdefault(item["ip"], []).append(item)
    return g

def delete_ip_backups(ip):
    deleted = 0
    for item in list_backups():
        if item["ip"] == ip:
            try: os.remove(item["path"]); deleted += 1
            except: pass
    return deleted

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass

    def check_auth(self):
        conf = load_config()
        ah = self.headers.get("Authorization", "")
        if not ah.startswith("Basic "): return False
        try:
            u, p = base64.b64decode(ah[6:]).decode().split(":", 1)
            return u == conf.get("web_user","admin") and p == conf.get("web_pass","admin")
        except: return False

    def require_auth(self):
        if not self.check_auth():
            body = b"<h1>401 Unauthorized</h1>"
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="XUI Backup Hub"')
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return False
        return True

    def send_html(self, body, code=200):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/":
            if not self.require_auth(): return
            groups = grouped_backups()
            ips = sorted(groups.keys())
            total_servers = len(ips)
            total_backups = sum(len(v) for v in groups.values())
            cards = []
            if not ips:
                cards.append('<div class="empty">هنوز بکاپی ثبت نشده.</div>')
            else:
                for ip in ips:
                    items = groups[ip][:5]
                    rows = "".join(f"""
                      <div class="backup-row">
                        <div class="backup-info">
                          <div class="title">{html.escape(b['name'])}</div>
                          <div class="meta">🕐 {fmt_time(b['mtime'])} &nbsp; 💾 {fmt_size(b['size'])}</div>
                        </div>
                        <a class="btn btn-dl" href="/download?file={html.escape(b['name'])}">⬇ دانلود</a>
                      </div>""" for b in items)
                    ip_e = html.escape(ip)
                    cards.append(f"""
                    <div class="card">
                      <div class="card-header">
                        <div>
                          <div class="ip-title">🖥 {ip_e}</div>
                          <div class="small">حداکثر ۵ بکاپ آخر نگه داشته می‌شود</div>
                        </div>
                        <button class="btn btn-del" onclick="delIP('{ip_e}')">🗑 حذف IP</button>
                      </div>
                      <div style="margin-top:14px">{rows}</div>
                    </div>""")

            page = f"""<!doctype html>
<html lang="fa" dir="rtl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>XUI Backup Hub</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:#0f172a;color:#e5e7eb;font-family:tahoma,Arial,sans-serif;padding:20px}}
.wrap{{max-width:1100px;margin:auto}}
.header{{background:linear-gradient(135deg,#1e293b,#0f172a);border:1px solid #334155;border-radius:18px;padding:24px;margin-bottom:20px;box-shadow:0 10px 40px rgba(0,0,0,.3)}}
.header h1{{font-size:24px;margin-bottom:6px;color:#38bdf8}}
.stats{{display:flex;gap:16px;margin-top:14px;flex-wrap:wrap}}
.stat{{background:#0f172a;border:1px solid #334155;border-radius:12px;padding:10px 20px;font-size:13px;color:#94a3b8}}
.stat span{{color:#38bdf8;font-weight:bold;font-size:20px;display:block}}
.card{{background:#111827;border:1px solid #334155;border-radius:18px;padding:20px;margin-bottom:18px;box-shadow:0 6px 24px rgba(0,0,0,.2)}}
.card-header{{display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:10px;margin-bottom:4px}}
.ip-title{{font-size:17px;font-weight:bold;color:#f1f5f9}}
.backup-row{{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;padding:12px 14px;border:1px solid #1e293b;border-radius:12px;background:#0b1220;margin-bottom:8px;transition:.15s}}
.backup-row:hover{{border-color:#334155}}
.backup-info{{flex:1;min-width:0}}
.title{{font-weight:bold;font-size:13px;color:#cbd5e1;word-break:break-all}}
.meta{{color:#64748b;font-size:12px;margin-top:4px}}
.small{{color:#475569;font-size:12px;margin-top:3px}}
.btn{{padding:9px 16px;border-radius:10px;font-size:13px;cursor:pointer;border:none;text-decoration:none;display:inline-block;white-space:nowrap;font-family:inherit}}
.btn-dl{{background:#0ea5e9;color:#fff}}.btn-dl:hover{{background:#0284c7}}
.btn-del{{background:#dc2626;color:#fff}}.btn-del:hover{{background:#b91c1c}}
.empty{{border:1px dashed #334155;border-radius:14px;padding:40px;text-align:center;color:#475569;font-size:15px}}
.footer{{text-align:center;color:#334155;font-size:12px;margin-top:30px;padding-top:20px;border-top:1px solid #1e293b}}
.footer a{{color:#475569;text-decoration:none}}.footer a:hover{{color:#94a3b8}}
</style></head><body>
<div class="wrap">
  <div class="header">
    <h1>🗄 مرکز بکاپ X-UI</h1>
    <div class="small">فقط فایل‌های دیتابیس .db ذخیره می‌شوند</div>
    <div class="stats">
      <div class="stat"><span>{total_servers}</span>سرور فعال</div>
      <div class="stat"><span>{total_backups}</span>بکاپ ذخیره شده</div>
    </div>
  </div>
  {''.join(cards)}
  <div class="footer">
    <a href="https://t.me/EmadHabibnia" target="_blank">Telegram: @EmadHabibnia</a> &nbsp;|&nbsp;
    <a href="https://github.com/Emadhabibnia1385" target="_blank">GitHub: @Emadhabibnia1385</a>
  </div>
</div>
<script>
function delIP(ip) {{
  if (!confirm('Delete all backups for IP: ' + ip + '\\nThis cannot be undone!')) return;
  fetch('/delete-ip', {{method:'POST', credentials:'same-origin',
    headers:{{'Content-Type':'application/json'}},
    body: JSON.stringify({{ip: ip}})
  }}).then(r=>r.json()).then(d=>{{
    alert(d.ok ? d.deleted + ' backup(s) deleted.' : 'Error: ' + d.error);
    if(d.ok) location.reload();
  }}).catch(()=>alert('Connection error'));
}}
</script>
</body></html>"""
            self.send_html(page)
            return

        if parsed.path == "/download":
            if not self.require_auth(): return
            qs = parse_qs(parsed.query)
            name = os.path.basename(unquote(qs.get("file", [""])[0]))
            full = os.path.join(BACKUP_DIR, name)
            if not os.path.isfile(full):
                self.send_html("<h1>File not found</h1>", 404); return
            st = os.stat(full)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f'attachment; filename="{name}"')
            self.send_header("Content-Length", str(st.st_size))
            self.end_headers()
            with open(full, "rb") as f: shutil.copyfileobj(f, self.wfile)
            return

        if parsed.path == "/api/list":
            if not self.require_auth(): return
            self.send_json({"items": list_backups()}); return

        self.send_html("<h1>Not Found</h1>", 404)

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == "/upload":
            qs = parse_qs(parsed.query)
            token = qs.get("token", [""])[0].strip()
            if token != load_config().get("upload_token", ""):
                self.send_json({"ok": False, "error": "invalid token"}, 403); return
            ctype, _ = cgi.parse_header(self.headers.get("Content-Type", ""))
            if ctype != "multipart/form-data":
                self.send_json({"ok": False, "error": "multipart required"}, 400); return
            form = cgi.FieldStorage(fp=self.rfile, headers=self.headers,
                environ={"REQUEST_METHOD":"POST","CONTENT_TYPE":self.headers.get("Content-Type")})
            if "file" not in form:
                self.send_json({"ok": False, "error": "file missing"}, 400); return
            upload = form["file"]
            server_ip = detect_ip(self, form.getvalue("server_ip", ""))
            ip_safe = safe_name(server_ip.replace(".", "_"))
            if not getattr(upload, "file", None):
                self.send_json({"ok": False, "error": "invalid upload"}, 400); return
            orig = os.path.basename(getattr(upload, "filename", "") or "")
            if not orig.endswith(".db"):
                self.send_json({"ok": False, "error": "only .db files allowed"}, 400); return
            filename = f"backup__{ip_safe}__{now_stamp()}.db"
            with open(os.path.join(BACKUP_DIR, filename), "wb") as f:
                shutil.copyfileobj(upload.file, f)
            prune_old_backups()
            self.send_json({"ok": True, "saved_as": filename, "server_ip": server_ip})
            return

        if parsed.path == "/delete-ip":
            if not self.require_auth(): return
            try:
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                ip = json.loads(body).get("ip", "").strip()
                if not ip:
                    self.send_json({"ok": False, "error": "ip missing"}, 400); return
                self.send_json({"ok": True, "deleted": delete_ip_backups(ip), "ip": ip})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return

        self.send_html("<h1>Not Found</h1>", 404)

def main():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    print(f"Backup Hub running on http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

if __name__ == "__main__":
    main()
PYEOF

  sed -i "s/_PORT_PLACEHOLDER_/PORT = ${HUB_PORT}/" /root/backup-hub/backup_hub.py
  print_ok "backup_hub.py written."

  cat > /etc/systemd/system/backup-hub.service <<EOF
[Unit]
Description=XUI Backup Hub - Central Backup Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/backup-hub
ExecStart=/usr/bin/python3 /root/backup-hub/backup_hub.py
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable backup-hub
  systemctl restart backup-hub
  sleep 2

  if systemctl is-active --quiet backup-hub; then
    print_ok "backup-hub service started successfully."
  else
    print_err "Service failed to start. Check: journalctl -u backup-hub -n 30"
  fi

  echo ""
  print_sep
  SERVER_IP_DISPLAY=$(hostname -I | awk '{print $1}')
  echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
  echo ""
  echo -e "  ${BOLD}Web panel URL :${NC}  http://${SERVER_IP_DISPLAY}:${HUB_PORT}"
  echo -e "  ${BOLD}Username      :${NC}  ${WEB_USER}"
  echo -e "  ${BOLD}Password      :${NC}  ${WEB_PASS}"
  echo -e "  ${BOLD}Upload token  :${NC}  ${UPLOAD_TOKEN}"
  echo -e "  ${BOLD}Upload URL    :${NC}  http://${SERVER_IP_DISPLAY}:${HUB_PORT}/upload?token=${UPLOAD_TOKEN}"
  print_sep
  pause
}

# ────────────────────────────────────────────────────────────
# 2. Install Client (X-UI sender server)
# ────────────────────────────────────────────────────────────
install_client() {
  require_root
  print_banner
  print_sep
  echo -e "  ${BOLD}Install Backup Client (X-UI Server)${NC}"
  print_sep
  echo ""

  read -rp "  Backup Hub server IP: " HUB_IP
  if [ -z "$HUB_IP" ]; then
    print_err "IP address is required."
    pause; return
  fi

  read -rp "  Backup Hub port [default: 8080]: " HUB_PORT_INPUT
  HUB_PORT="${HUB_PORT_INPUT:-8080}"

  read -rp "  Upload token [default: emad]: " TOKEN_INPUT
  HUB_TOKEN="${TOKEN_INPUT:-emad}"

  read -rp "  Backup interval in minutes [default: 2]: " INTERVAL_INPUT
  INTERVAL="${INTERVAL_INPUT:-2}"

  BACKUP_URL="http://${HUB_IP}:${HUB_PORT}/upload?token=${HUB_TOKEN}"

  print_info "Writing push script..."
  mkdir -p /usr/local/bin

  cat > /usr/local/bin/xui-push-http.sh <<SHEOF
#!/bin/bash
set -e
export TZ=Asia/Tehran

BACKUP_URL="${BACKUP_URL}"
SERVER_IP="\$(hostname -I | awk '{print \$1}')"
STAMP="\$(date +%Y%m%d_%H%M%S)"
TMP_FILE="/tmp/xui_\${SERVER_IP}_\${STAMP}.db"
LOG="/var/log/xui-push-http.log"

DB_PATH=""
for p in \\
  /etc/x-ui/x-ui.db \\
  /usr/local/x-ui/x-ui.db \\
  /etc/3x-ui/x-ui.db \\
  /usr/local/3x-ui/x-ui.db \\
  /opt/x-ui/x-ui.db \\
  /opt/3x-ui/x-ui.db
do
  if [ -f "\$p" ]; then DB_PATH="\$p"; break; fi
done

if [ -z "\$DB_PATH" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: XUI DB NOT FOUND" >> "\$LOG"
  exit 1
fi

cp "\$DB_PATH" "\$TMP_FILE"
RESULT=\$(curl -s --max-time 30 -X POST \\
  -F "server_ip=\${SERVER_IP}" \\
  -F "file=@\${TMP_FILE}" \\
  "\$BACKUP_URL" 2>&1)
rm -f "\$TMP_FILE"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$RESULT" >> "\$LOG"
SHEOF

  chmod +x /usr/local/bin/xui-push-http.sh
  print_ok "Script created: /usr/local/bin/xui-push-http.sh"

  cat > /etc/systemd/system/xui-push-backup.service <<'EOF'
[Unit]
Description=Push XUI DB backup to central backup server
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xui-push-http.sh
User=root
EOF

  cat > /etc/systemd/system/xui-push-backup.timer <<EOF
[Unit]
Description=XUI Backup push every ${INTERVAL} minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=${INTERVAL}min
AccuracySec=10s
Unit=xui-push-backup.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now xui-push-backup.timer
  sleep 1

  if systemctl is-active --quiet xui-push-backup.timer; then
    print_ok "Timer enabled successfully."
  else
    print_err "Timer failed to start."
  fi

  echo ""
  print_info "Running initial backup test..."
  /usr/local/bin/xui-push-http.sh 2>/dev/null && print_ok "Test successful." || print_err "Test failed. Check: tail -5 /var/log/xui-push-http.log"

  echo ""
  print_sep
  echo -e "${GREEN}${BOLD}  Client installation complete!${NC}"
  echo ""
  echo -e "  ${BOLD}Hub server    :${NC}  ${HUB_IP}:${HUB_PORT}"
  echo -e "  ${BOLD}Token         :${NC}  ${HUB_TOKEN}"
  echo -e "  ${BOLD}Interval      :${NC}  every ${INTERVAL} minute(s)"
  echo -e "  ${BOLD}Log file      :${NC}  /var/log/xui-push-http.log"
  print_sep
  pause
}

# ────────────────────────────────────────────────────────────
# 3. Manage Services
# ────────────────────────────────────────────────────────────
manage_services() {
  while true; do
    print_banner
    print_sep
    echo -e "  ${BOLD}Manage Services${NC}"
    print_sep
    echo "   1) Backup Hub status"
    echo "   2) Restart Backup Hub"
    echo "   3) Stop / Start Backup Hub"
    echo "   ─────────────────────────────────"
    echo "   4) Client timer status"
    echo "   5) Restart client timer"
    echo "   6) Stop / Start client timer"
    echo "   7) Send backup manually right now"
    echo "   ─────────────────────────────────"
    echo "   0) Back"
    print_sep
    read -rp "  Choice: " SC

    case "$SC" in
      1) echo ""; systemctl status backup-hub --no-pager -l 2>/dev/null || print_err "Service not found."; pause ;;
      2) systemctl restart backup-hub && print_ok "Restarted." || print_err "Failed."; pause ;;
      3)
        if systemctl is-active --quiet backup-hub; then
          systemctl stop backup-hub && print_ok "Stopped." || print_err "Failed."
        else
          systemctl start backup-hub && print_ok "Started." || print_err "Failed."
        fi; pause ;;
      4) echo ""; systemctl status xui-push-backup.timer --no-pager 2>/dev/null || print_err "Timer not found."
         echo ""; systemctl list-timers --all 2>/dev/null | grep -i xui || true; pause ;;
      5) systemctl restart xui-push-backup.timer && print_ok "Restarted." || print_err "Failed."; pause ;;
      6)
        if systemctl is-active --quiet xui-push-backup.timer; then
          systemctl stop xui-push-backup.timer && print_ok "Stopped." || print_err "Failed."
        else
          systemctl start xui-push-backup.timer && print_ok "Started." || print_err "Failed."
        fi; pause ;;
      7)
        if [ -f /usr/local/bin/xui-push-http.sh ]; then
          print_info "Sending backup now..."
          /usr/local/bin/xui-push-http.sh && print_ok "Done." || print_err "Failed."
        else
          print_err "Client script not found. Install client first."
        fi; pause ;;
      0) break ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

# ────────────────────────────────────────────────────────────
# 4. Show Logs
# ────────────────────────────────────────────────────────────
show_logs() {
  while true; do
    print_banner
    print_sep
    echo -e "  ${BOLD}Logs${NC}"
    print_sep
    echo "   1) Live log - Backup Hub      (Ctrl+C to exit)"
    echo "   2) Last 50 lines - Backup Hub"
    echo "   3) Live log - Client          (Ctrl+C to exit)"
    echo "   4) Last 50 lines - Client"
    echo "   5) Client log file (/var/log/xui-push-http.log)"
    echo "   0) Back"
    print_sep
    read -rp "  Choice: " LC

    case "$LC" in
      1) journalctl -u backup-hub -f ;;
      2) journalctl -u backup-hub -n 50 --no-pager; pause ;;
      3) journalctl -u xui-push-backup.service -f ;;
      4) journalctl -u xui-push-backup.service -n 50 --no-pager; pause ;;
      5)
        if [ -f /var/log/xui-push-http.log ]; then tail -50 /var/log/xui-push-http.log
        else print_err "Log file not found yet."; fi; pause ;;
      0) break ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

# ────────────────────────────────────────────────────────────
# 5. Uninstall
# ────────────────────────────────────────────────────────────
uninstall() {
  require_root
  print_banner
  print_sep
  echo -e "  ${RED}${BOLD}Uninstall Backup System${NC}"
  print_sep
  echo "   1) Remove Backup Hub (central server)"
  echo "   2) Remove Client (X-UI server)"
  echo "   3) Remove both"
  echo "   0) Back"
  print_sep
  read -rp "  Choice: " UC

  case "$UC" in
    1|3)
      print_info "Removing Backup Hub..."
      systemctl stop backup-hub 2>/dev/null || true
      systemctl disable backup-hub 2>/dev/null || true
      rm -f /etc/systemd/system/backup-hub.service
      systemctl daemon-reload
      read -rp "  Also delete /root/backup-hub and all backups? [y/N]: " DD
      [[ "$DD" =~ ^[Yy]$ ]] && rm -rf /root/backup-hub && print_ok "Data deleted."
      print_ok "Backup Hub removed." ;;
  esac

  case "$UC" in
    2|3)
      print_info "Removing client..."
      systemctl stop xui-push-backup.timer 2>/dev/null || true
      systemctl disable xui-push-backup.timer 2>/dev/null || true
      rm -f /etc/systemd/system/xui-push-backup.timer
      rm -f /etc/systemd/system/xui-push-backup.service
      rm -f /usr/local/bin/xui-push-http.sh
      rm -f /var/log/xui-push-http.log
      systemctl daemon-reload
      print_ok "Client removed." ;;
  esac

  [ "$UC" != "0" ] && print_ok "Uninstall complete."
  pause
}

# ────────────────────────────────────────────────────────────
# Main Menu
# ────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    print_banner
    print_sep
    echo -e "  ${BOLD}Main Menu${NC}"
    print_sep
    echo "   1) Install Backup Hub  (central receiver server)"
    echo "   2) Install Client      (X-UI sender server)"
    echo "   ─────────────────────────────────────────────"
    echo "   3) Manage services"
    echo "   4) View logs"
    echo "   5) Uninstall"
    echo "   ─────────────────────────────────────────────"
    echo "   0) Exit"
    print_sep
    read -rp "  Your choice: " CHOICE

    case "$CHOICE" in
      1) install_hub ;;
      2) install_client ;;
      3) manage_services ;;
      4) show_logs ;;
      5) uninstall ;;
      0) echo ""; print_ok "Goodbye."; echo ""; exit 0 ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

main_menu
