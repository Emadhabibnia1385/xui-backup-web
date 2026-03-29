#!/bin/bash
# ============================================================
#  XUI Backup Hub v3.2
#  GitHub  : https://github.com/Emadhabibnia1385
#  Telegram: https://t.me/EmadHabibnia
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

print_banner() {
  clear; echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║        XUI Backup Hub v2 - Production Ready              ║"
  echo "  ║    Backup · Monitor · Auto-Register                      ║"
  echo "  ╠══════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${MAGENTA}Telegram : @EmadHabibnia${CYAN}                                ║"
  echo -e "  ║  ${MAGENTA}GitHub   : @Emadhabibnia1385${CYAN}                            ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_ok()   { echo -e "${GREEN}  [OK] $1${NC}"; }
print_info() { echo -e "${YELLOW}  [..] $1${NC}"; }
print_err()  { echo -e "${RED}  [!!] $1${NC}"; }
print_sep()  { echo -e "${CYAN}  ──────────────────────────────────────────────────────${NC}"; }


require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    print_err "This script must be run as root."
    exit 1
  fi
}

pause() { echo ""; read -rp "  Press Enter to continue..." _; }

# ════════════════════════════════════════════════════════════
    # main_menu function ends here
# 1. INSTALL HUB
# ════════════════════════════════════════════════════════════
install_hub() {
  require_root
  print_banner; print_sep
  echo -e "  ${BOLD}Install Backup Hub v3.2${NC}"
  print_sep
  echo ""
  echo -e "  ${YELLOW}X-UI servers will be auto-registered when they send their first backup.${NC}"
  echo ""

  read -rp "  Upload token (all clients use this) [default: xui2024]: " INPUT_TOKEN
  UPLOAD_TOKEN="${INPUT_TOKEN:-xui2024}"

  read -rp "  Service port [default: 8080]: " INPUT_PORT
  HUB_PORT="${INPUT_PORT:-8080}"

  read -rp "  Max backups per server [default: 10]: " INPUT_MAX
  MAX_BACKUPS="${INPUT_MAX:-10}"

  echo ""
  echo -e "  ${BOLD}Web panel login:${NC}"
  read -rp "  Username [default: admin]: " INPUT_USER
  WEB_USER="${INPUT_USER:-admin}"

  while true; do
    read -rsp "  Password: " INPUT_PASS; echo ""
    if [ -z "$INPUT_PASS" ]; then
      print_err "Password cannot be empty."
      continue
    fi
    read -rsp "  Confirm password: " INPUT_PASS2; echo ""
    if [ "$INPUT_PASS" = "$INPUT_PASS2" ]; then
      WEB_PASS="$INPUT_PASS"
      break
    fi
    print_err "Passwords do not match."
  done

  export _SETUP_PASS="$WEB_PASS"
  WEB_PASS_HASH=$(python3 -c "
import hashlib, uuid, os
p = os.environ.get('_SETUP_PASS','')
s = uuid.uuid4().hex
h = hashlib.sha256((s+p).encode()).hexdigest()
print(f'{s}:{h}')
")
  unset _SETUP_PASS

  echo ""
  print_info "Creating directories..."
  mkdir -p /root/backup-hub/data/backups /root/backup-hub/logs

  cat > /root/backup-hub/data/config.json << CONFIG_EOF
{
  "upload_token": "${UPLOAD_TOKEN}",
  "web_user": "${WEB_USER}",
  "web_pass_hash": "${WEB_PASS_HASH}",
  "max_backups": ${MAX_BACKUPS},
  "servers": []
}
CONFIG_EOF
  print_ok "config.json written."

  print_info "Writing backup_hub.py ..."

  # Write hub Python file directly (no Python-in-Python)
  cat > /root/backup-hub/backup_hub.py << 'PYEOF'
#!/usr/bin/env python3
import os, re, cgi, json, html, shutil, uuid, hashlib, time, threading, logging, base64
from datetime import datetime
from zoneinfo import ZoneInfo
from urllib.parse import urlparse, parse_qs, unquote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.request

HOST = "0.0.0.0"
PORT = __PORT__
TZ = ZoneInfo("Asia/Tehran")

BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(BASE_DIR, "data")
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
CONFIG_FILE= os.path.join(DATA_DIR, "config.json")
LOG_DIR    = os.path.join(BASE_DIR, "logs")
os.makedirs(BACKUP_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, "hub.log")),
        logging.StreamHandler()
    ]
)
log = logging.getLogger("hub")

# ── Sessions ──────────────────────────────────────────────
_sessions = {}
_slock = threading.Lock()
SESSION_TTL = 3600

def make_session():
    sid = uuid.uuid4().hex
    with _slock: _sessions[sid] = time.time()
    return sid

def valid_session(sid):
    with _slock:
        ts = _sessions.get(sid)
        if ts is None: return False
        if time.time() - ts > SESSION_TTL:
            del _sessions[sid]; return False
        _sessions[sid] = time.time()
        return True

def del_session(sid):
    with _slock: _sessions.pop(sid, None)

# ── Password ──────────────────────────────────────────────
def verify_password(p, stored):
    try:
        s, h = stored.split(":", 1)
        return hashlib.sha256((s + p).encode()).hexdigest() == h
    except:
        return False

# ── Config ────────────────────────────────────────────────
_cfg_lock = threading.Lock()
DCFG = {"upload_token": "xui2024", "web_user": "admin",
        "web_pass_hash": "", "max_backups": 10, "servers": []}

def load_config():
    with _cfg_lock:
        try:
            with open(CONFIG_FILE) as f:
                return {**DCFG, **json.load(f)}
        except:
            return dict(DCFG)

def save_config(cfg):
    with _cfg_lock:
        tmp = CONFIG_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        os.replace(tmp, CONFIG_FILE)

def find_server(ip=None, sid=None):
    for s in load_config().get("servers", []):
        if ip and s.get("ip") == ip: return s
        if sid and s.get("id") == sid: return s
    return None

def auto_register(ip):
    cfg = load_config()
    if find_server(ip=ip): return
    sid = "srv_" + ip.replace(".", "_")
    new_srv = {"id": sid, "name": ip, "ip": ip, "agent_port": 8081}
    cfg.setdefault("servers", []).append(new_srv)
    save_config(cfg)
    log.info(f"Auto-registered server: {ip}")

# ── Heartbeat ─────────────────────────────────────────────
_hb = {}
_hb_lock = threading.Lock()

def beat(ip):
    with _hb_lock: _hb[ip] = time.time()

def get_status(ip):
    with _hb_lock: ts = _hb.get(ip)
    if ts is None: return "unknown"
    return "online" if time.time() - ts < 180 else "offline"

def last_seen_fmt(ip):
    with _hb_lock: ts = _hb.get(ip)
    if ts is None: return "Never"
    return datetime.fromtimestamp(ts, TZ).strftime("%Y-%m-%d %H:%M:%S")

# ── Backup helpers ────────────────────────────────────────
def safe_name(n):
    return re.sub(r"[^a-zA-Z0-9._-]", "_", n)

def now_stamp():
    return datetime.now(TZ).strftime("%Y%m%d_%H%M%S")

def fmt_time(e):
    return datetime.fromtimestamp(e, TZ).strftime("%Y-%m-%d %H:%M:%S")

def fmt_size(n):
    if n < 1024: return f"{n} B"
    if n < 1048576: return f"{n/1024:.1f} KB"
    return f"{n/1048576:.2f} MB"

def list_backups():
    items = []
    sm = {s["ip"]: s for s in load_config().get("servers", [])}
    for name in os.listdir(BACKUP_DIR):
        if not name.endswith(".db"): continue
        full = os.path.join(BACKUP_DIR, name)
        if not os.path.isfile(full): continue
        st = os.stat(full)
        m = re.match(r"^backup__(.+?)__\d{8}_\d{6}\.db$", name)
        ip = m.group(1).replace("_", ".") if m else "unknown"
        srv = sm.get(ip, {})
        items.append({
            "name": name, "path": full, "ip": ip,
            "srv_id": srv.get("id", ""),
            "size": st.st_size, "mtime": st.st_mtime
        })
    return sorted(items, key=lambda x: x["mtime"], reverse=True)

def grouped():
    g = {}
    for b in list_backups(): g.setdefault(b["ip"], []).append(b)
    return g

def prune():
    cfg = load_config()
    mx = cfg.get("max_backups", 10)
    by_ip = {}
    for b in list_backups(): by_ip.setdefault(b["ip"], []).append(b)
    for ip, arr in by_ip.items():
        for old in sorted(arr, key=lambda x: x["mtime"], reverse=True)[mx:]:
            try: os.remove(old["path"]); log.info(f"Pruned: {old['name']}")
            except Exception as e: log.error(f"Prune error: {e}")

def total_size():
    return sum(b["size"] for b in list_backups())

def del_server_backups(ip):
    n = 0
    for b in list_backups():
        if b["ip"] == ip:
            try: os.remove(b["path"]); n += 1
            except: pass
    return n

# ── CSS ───────────────────────────────────────────────────
CSS = """
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{
  background:#0a0a0a;
  color:#d4d4d4;
  font-family:'Inter','Segoe UI',Arial,sans-serif;
  min-height:100vh;
  padding:20px;
  line-height:1.6;
}
.wrap{max-width:960px;margin:0 auto}

/* ── Cards & Panels ── */
.hdr,.login-box,.card{
  background:#111111;
  border:1px solid #1e1e1e;
  border-radius:12px;
  margin-bottom:16px;
  padding:24px;
}

/* ── Header ── */
.hdr-top{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px}
.hdr h1{font-size:20px;font-weight:700;color:#39ff14;letter-spacing:-0.3px}
.hdr-sub{color:#666;font-size:12px;margin-top:2px;font-weight:500}

/* ── Stats ── */
.stats{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.stat{
  background:#0a0a0a;
  border:1px solid #1e1e1e;
  border-radius:10px;
  padding:14px 18px;
  flex:1;
  min-width:100px;
  text-align:center;
}
.stat-n{font-size:24px;color:#39ff14;font-weight:800;line-height:1}
.stat-l{color:#555;font-size:11px;margin-top:4px;text-transform:uppercase;letter-spacing:0.5px;font-weight:600}

/* ── Server Cards ── */
.card{padding:20px 24px}
.card-hdr{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:16px;padding-bottom:14px;border-bottom:1px solid #1e1e1e}
.srv-name{font-size:15px;font-weight:700;color:#e5e5e5;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.srv-ip{color:#39ff14;font-size:11px;margin-top:3px;font-family:'SF Mono','Fira Code',monospace;font-weight:500}
.srv-detail{color:#555;font-size:11px;margin-top:2px}

/* ── Badges ── */
.badge{display:inline-block;padding:3px 10px;border-radius:6px;font-size:11px;font-weight:700;letter-spacing:0.3px}
.badge-on{background:rgba(57,255,20,0.1);color:#39ff14;border:1px solid rgba(57,255,20,0.25)}
.badge-off{background:rgba(255,50,50,0.08);color:#ff4444;border:1px solid rgba(255,50,50,0.2)}
.badge-unk{background:rgba(100,100,100,0.1);color:#888;border:1px solid rgba(100,100,100,0.25)}

/* ── Backup Rows ── */
.bk-row{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;padding:12px 16px;border:1px solid #1a1a1a;border-radius:8px;background:#0d0d0d;margin-bottom:6px;transition:border-color .15s}
.bk-row:hover{border-color:#39ff14}
.bk-info{flex:1;min-width:0}
.bk-name{font-size:12px;color:#ccc;word-break:break-all;font-family:'SF Mono','Fira Code',monospace}
.bk-meta{color:#555;font-size:11px;margin-top:3px}
.bk-actions{display:flex;gap:6px}

/* ── Buttons ── */
.btn,.btn-dl,.btn-del,.btn-out{
  background:#39ff14;
  color:#0a0a0a;
  border:none;
  border-radius:8px;
  padding:8px 18px;
  font-size:13px;
  font-weight:700;
  cursor:pointer;
  transition:all .15s;
  font-family:inherit;
}
.btn:hover,.btn-dl:hover{background:#2dd610;}
.btn-del{background:transparent;color:#ff4444;border:1px solid #ff4444;}
.btn-del:hover{background:#ff4444;color:#0a0a0a;}
.btn-out{background:transparent;color:#555;border:1px solid #333;padding:8px 16px;}
.btn-out:hover{border-color:#39ff14;color:#39ff14;}
.btn-more{background:transparent;color:#39ff14;border:1px solid #1e1e1e;width:100%;padding:10px;border-radius:8px;margin-top:6px;cursor:pointer;font-size:12px;font-family:inherit;transition:.15s;text-align:center;font-weight:600}
.btn-more:hover{border-color:#39ff14;background:rgba(57,255,20,0.05)}

/* ── Empty State ── */
.empty{border:1px dashed #333;border-radius:8px;padding:32px;text-align:center;color:#555;font-size:13px;background:#0d0d0d}

/* ── Footer ── */
.footer{text-align:center;color:#444;font-size:12px;margin-top:24px;padding-top:16px;border-top:1px solid #1a1a1a}
.footer a{color:#39ff14;text-decoration:none;font-weight:600}.footer a:hover{text-decoration:underline}
.footer span{color:#333;margin:0 8px}

/* ── Modal ── */
.modal-bg{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:100;align-items:center;justify-content:center;backdrop-filter:blur(4px)}
.modal-bg.open{display:flex}
.modal{background:#111;border:1px solid #1e1e1e;border-radius:12px;padding:28px;max-width:420px;width:92%;box-shadow:0 20px 60px rgba(0,0,0,.6)}
.modal h3{color:#39ff14;margin-bottom:6px;font-size:16px}
.modal-sub{color:#666;font-size:12px;margin-bottom:16px;line-height:1.7;word-break:break-all}
.srv-list{display:flex;flex-direction:column;gap:6px;margin-bottom:16px;max-height:240px;overflow-y:auto}
.srv-opt{display:flex;align-items:center;gap:10px;padding:12px 14px;border:1px solid #1e1e1e;border-radius:8px;cursor:pointer;transition:.15s}
.srv-opt:hover{border-color:#39ff14}
.srv-opt.selected{border-color:#39ff14;background:rgba(57,255,20,0.05)}
.srv-opt-name{color:#ccc;font-size:14px;font-weight:600}
.srv-opt-ip{color:#39ff14;font-size:11px;font-family:'SF Mono','Fira Code',monospace;margin-top:1px}
.modal-actions{display:flex;gap:8px;justify-content:flex-end}

/* ── Toast ── */
.toast{position:fixed;bottom:20px;right:20px;background:#111;border:1px solid #39ff14;border-radius:8px;padding:12px 20px;font-size:13px;z-index:200;opacity:0;transition:opacity .3s;pointer-events:none;max-width:300px;color:#39ff14;font-weight:600}
.toast.show{opacity:1}
.toast.ok{border-color:#39ff14;color:#39ff14}
.toast.err{border-color:#ff4444;color:#ff4444}

/* ── Login Page ── */
body.login-body{display:flex;align-items:center;justify-content:center;padding:20px;background:#0a0a0a}
.login-box{max-width:380px;width:100%}
.login-box h1{color:#39ff14;font-size:22px;text-align:center;margin-bottom:4px;font-weight:800}
.login-box .sub{color:#555;font-size:13px;text-align:center;margin-bottom:28px}
.login-box label{display:block;color:#888;font-size:11px;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.5px;font-weight:600}
.login-box input{width:100%;background:#0a0a0a;border:1px solid #1e1e1e;border-radius:8px;padding:12px 14px;color:#e5e5e5;font-size:14px;font-family:inherit;outline:none;margin-bottom:16px;transition:border .15s}
.login-box input:focus{border-color:#39ff14}
.login-box button{width:100%;background:#39ff14;color:#0a0a0a;border:none;border-radius:8px;padding:12px;font-size:15px;font-weight:800;cursor:pointer;transition:.15s;font-family:inherit}
.login-box button:hover{background:#2dd610}
.err-box{background:rgba(255,50,50,0.06);border:1px solid rgba(255,50,50,0.2);color:#ff4444;border-radius:8px;padding:10px 16px;font-size:13px;margin-bottom:16px;text-align:center}
.login-footer{text-align:center;color:#444;font-size:12px;margin-top:24px;padding-top:16px;border-top:1px solid #1a1a1a}
.login-footer a{color:#39ff14;text-decoration:none;font-weight:600}.login-footer a:hover{text-decoration:underline}
.login-footer span{color:#333;margin:0 8px}

@media (max-width: 700px) {
  body{padding:12px}
  .card,.login-box,.hdr{padding:16px}
  .btn,.btn-dl{width:100%;text-align:center;padding:10px 0}
  .stats{flex-direction:column;gap:8px}
  .card-hdr,.hdr-top{flex-direction:column;align-items:flex-start;gap:10px}
  .bk-row{flex-direction:column;align-items:flex-start}
  .bk-actions{width:100%;justify-content:flex-end}
}
"""

# ── JS Template (plain string, no f-string — {} are safe) ─
JS_TEMPLATE = """
<script>
const SERVERS = __SRVS__;

let _file = null;
let _sid  = null;

// ── Event delegation ──────────────────────────────────────
document.addEventListener('click', function(e) {

  // Expand / collapse more backups
  var mBtn = e.target.closest('.btn-more');
  if (mBtn) {
    var uid = mBtn.dataset.uid;
    var box = document.getElementById('more-' + uid);
    if (box) {
      var open = box.style.display !== 'none';
      box.style.display = open ? 'none' : 'block';
      mBtn.textContent = open ? mBtn.dataset.label : '▲ بستن';
    }
    return;
  }

  // Delete server
  var dBtn = e.target.closest('.btn-del-srv');
  if (dBtn) {
    var ip   = dBtn.dataset.ip;
    var name = dBtn.dataset.name || ip;
    if (!confirm('حذف سرور ' + name + ' و همه بکاپ‌هایش؟')) return;
    fetch('/api/delete-server', {
      method: 'POST', credentials: 'same-origin',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ip: ip})
    }).then(function(r){ return r.json(); }).then(function(d){
      if (d.ok) { toast(d.deleted + ' بکاپ حذف شد'); setTimeout(function(){ location.reload(); }, 900); }
      else toast('خطا: ' + (d.error || ''), 'err');
    }).catch(function(){ toast('خطای اتصال', 'err'); });
    return;
  }


});

// ── Restore modal ─────────────────────────────────────────


function toast(msg, type) {
  var el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast show ' + (type || 'ok');
  setTimeout(function(){ el.className = 'toast'; }, 3500);
}
</script>
"""

# ── HTML pages ────────────────────────────────────────────
def login_page(err=""):
    e = '<div class="err-box">' + html.escape(err) + '</div>' if err else ""
    return (
      '<!doctype html><html lang="en" dir="ltr"><head>'
      '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>XUI Backup Hub</title>'
      '<style>' + CSS + '</style>'
      '</head><body class="login-body">'
      '<div class="login-box">'
      '<h1>🗄 XUI Backup Hub</h1>'
      '<div class="sub">Sign in to the management panel</div>'
      + e +
      '<form method="POST" action="/login">'
      '<label>Username</label>'
      '<input name="username" type="text" autocomplete="username">'
      '<label>Password</label>'
      '<input name="password" type="password" autocomplete="current-password">'
      '<button type="submit">Sign in →</button>'
      '</form>'
      '<div class="login-footer">'
      'Telegram: <a href="https://t.me/Emad_Habibnia" target="_blank">@Emad_Habibnia</a>'
      '<span>·</span>'
      'GitHub: <a href="https://github.com/Emadhabibnia1385" target="_blank">Emadhabibnia1385</a>'
      '</div>'
      '</div></body></html>'
    )

def mk_row(b):
    name = html.escape(b["name"])
    return (
      '<div class="bk-row">'
      '<div class="bk-info">'
      '<div class="bk-name">' + name + '</div>'
      '<div class="bk-meta">🕐 ' + fmt_time(b["mtime"]) + ' &nbsp;·&nbsp; 💾 ' + fmt_size(b["size"]) + '</div>'
      '</div>'
      '<div class="bk-actions">'
      '<a class="btn btn-dl" href="/download?file=' + name + '">⬇ Download</a>'
      '</div>'
      '</div>'
    )

def dashboard_page():

    cfg     = load_config()
    grps    = grouped()
    servers = cfg.get("servers", [])
    reg_ips = {s["ip"] for s in servers}
    MAX_SHOW = 2

    tot_b    = sum(len(v) for v in grps.values())
    tot_s    = fmt_size(total_size())
    online_n = sum(1 for s in servers if get_status(s["ip"]) == "online")

    import json
    srv_json = json.dumps(servers, ensure_ascii=False)

    cards = ""

    for srv in servers:
      ip  = srv.get("ip", "")
      sid = srv.get("id", "")
      nm  = srv.get("name", ip)
      st  = get_status(ip)
      ls  = last_seen_fmt(ip)
      items = grps.get(ip, [])
      last_bk = fmt_time(items[0]["mtime"]) if items else "—"

      bc = {"online": "badge-on", "offline": "badge-off"}.get(st, "badge-unk")
      bl = {"online": "🟢 Online", "offline": "🔴 Offline"}.get(st, "⚪ Unknown")

      visible = items[:MAX_SHOW]
      hidden  = items[MAX_SHOW:]

      rows = "".join(mk_row(b) for b in visible)

      expand = ""
      if hidden:
        uid   = re.sub(r"[^a-zA-Z0-9]", "_", sid)
        label = "▼ Show " + str(len(hidden)) + " more backups"
        hrows = "".join(mk_row(b) for b in hidden)
        expand = (
          '<button class="btn-more" data-uid="' + uid + '" data-label="' + label + '">' + label + '</button>'
          '<div id="more-' + uid + '" style="display:none">' + hrows + '</div>'
        )

      if not rows and not expand:
        rows = '<div class="empty">No backups received yet</div>'

      cards += (
        '<div class="card">'
        '<div class="card-hdr">'
        '<div>'
        '<div class="srv-name">' + html.escape(nm) + ' <span class="badge ' + bc + '">' + bl + '</span></div>'
        '<div class="srv-ip">' + html.escape(ip) + '</div>'
        '<div class="srv-detail">Last backup: ' + last_bk + ' &nbsp;·&nbsp; Last seen: ' + ls + '</div>'
        '</div>'
        '<button class="btn btn-del btn-del-srv" data-ip="' + html.escape(ip) + '" data-name="' + html.escape(nm) + '">🗑 Delete</button>'
        '</div>'
        + rows + expand +
        '</div>'
      )

    # Servers not in registry yet (uploaded but not in config)
    for ip, items in sorted(grps.items()):
      if ip in reg_ips: continue
      visible = items[:MAX_SHOW]
      hidden  = items[MAX_SHOW:]
      rows = "".join(mk_row(b) for b in visible)
      expand = ""
      if hidden:
        uid   = re.sub(r"[^a-zA-Z0-9]", "_", ip.replace(".", "_"))
        label = "▼ Show " + str(len(hidden)) + " more backups"
        hrows = "".join(mk_row(b) for b in hidden)
        expand = (
          '<button class="btn-more" data-uid="u' + uid + '" data-label="' + label + '">' + label + '</button>'
          '<div id="more-u' + uid + '" style="display:none">' + hrows + '</div>'
        )
      cards += (
        '<div class="card">'
        '<div class="card-hdr">'
        '<div>'
        '<div class="srv-name">' + html.escape(ip) + ' <span class="badge badge-unk">⚙ Auto-registered</span></div>'
        '<div class="srv-detail">Backups received from this IP — auto-registered</div>'
        '</div>'
        '<button class="btn btn-del btn-del-srv" data-ip="' + html.escape(ip) + '" data-name="">🗑 Delete</button>'
        '</div>'
        + rows + expand +
        '</div>'
      )

    if not cards:
      cards = '<div class="empty" style="padding:40px;font-size:14px">No backups received yet.<br>Install the client on your X-UI servers.</div>'

    js = JS_TEMPLATE.replace("__SRVS__", srv_json)

    return (
      '<!doctype html><html lang="en" dir="ltr"><head>'
      '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>XUI Backup Hub</title>'
      '<style>' + CSS + '</style>'
      '</head><body>'
      '<div class="wrap">'
      '<div class="hdr">'
      '<div class="hdr-top">'
      '<div><h1>🗄 XUI Backup Hub</h1>'
      '<div class="hdr-sub">Backup · Monitor · Auto-Register</div>'
      '</div>'
      '<button type="button" class="btn-out" onclick="fetch(\'/logout\',{method:\'POST\',credentials:\'same-origin\'}).then(function(){window.location.href=\'/login\'}).catch(function(){window.location.href=\'/login\'})">Logout</button>'
      '</div>'
      '<div class="stats">'
      '<div class="stat"><div class="stat-n">' + str(len(servers)) + '</div><div class="stat-l">Servers</div></div>'
      '<div class="stat"><div class="stat-n">' + str(online_n) + '</div><div class="stat-l">Online</div></div>'
      '<div class="stat"><div class="stat-n">' + str(tot_b) + '</div><div class="stat-l">Total backups</div></div>'
      '<div class="stat"><div class="stat-n">' + tot_s + '</div><div class="stat-l">Total size</div></div>'
      '</div>'
      '</div>'
      + cards +
      '<div class="footer">'
      'Telegram: <a href="https://t.me/Emad_Habibnia" target="_blank">@Emad_Habibnia</a>'
      '<span>·</span>'
      'GitHub: <a href="https://github.com/Emadhabibnia1385" target="_blank">Emadhabibnia1385</a>'
      '</div>'
      '</div>'
      '<div class="toast" id="toast"></div>'
      + js +
      '</body></html>'
    )

# ── HTTP Handler ──────────────────────────────────────────
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def get_session(self):
        for c in self.headers.get("Cookie", "").split(";"):
            c = c.strip()
            if c.startswith("session="): return c[8:]
        return None

    def is_auth(self):
        sid = self.get_session()
        return sid and valid_session(sid)

    def redirect(self, loc, extra_headers=None):
        self.send_response(302)
        self.send_header("Location", loc)
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()

    def send_html(self, body, code=200):
        d = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html;charset=utf-8")
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)

    def send_json(self, obj, code=200):
        d = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)

    def read_body(self):
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n)

    def read_json(self):
        return json.loads(self.read_body())

    def do_GET(self):
        parsed = urlparse(self.path)
        qs     = parse_qs(parsed.query)
        path   = parsed.path

        if path == "/login":
            self.send_html(login_page()); return

        if path == "/logout":
            del_session(self.get_session())
            self.redirect("/login", {"Set-Cookie": "session=;Max-Age=0;Path=/"})
            return

        if path in ("/", "/dashboard"):
            if not self.is_auth():
                self.redirect("/login"); return
            self.send_html(dashboard_page()); return

        if path == "/download":
            if not self.is_auth():
                self.redirect("/login"); return
            fname = os.path.basename(unquote(qs.get("file", [""])[0]))
            fpath = os.path.join(BACKUP_DIR, fname)
            if not os.path.isfile(fpath):
                self.send_html("<h1>Not Found</h1>", 404); return
            st = os.stat(fpath)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
            self.send_header("Content-Length", str(st.st_size))
            self.end_headers()
            with open(fpath, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        self.send_html("<h1>Not Found</h1>", 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path

        # ── Login ──
        if path == "/login":
            params = {}
            for x in self.read_body().decode().split("&"):
                if "=" in x:
                    k, v = x.split("=", 1)
                    params[k] = unquote(v.replace("+", " "))
            cfg = load_config()
            u   = params.get("username", "")
            pw  = params.get("password", "")
            if u == cfg.get("web_user", "") and verify_password(pw, cfg.get("web_pass_hash", "")):
                sid = make_session()
                log.info(f"Login: {u} from {self.client_address[0]}")
                self.redirect("/", {"Set-Cookie": f"session={sid};HttpOnly;Path=/;Max-Age=3600"})
            else:
                log.warning(f"Failed login: {u} from {self.client_address[0]}")
                self.send_html(login_page("نام کاربری یا رمز عبور اشتباه است."))
            return

        # ── Logout ──
        if path == "/logout":
            del_session(self.get_session())
            self.redirect("/login", {"Set-Cookie": "session=;Max-Age=0;Path=/"})
            return

        # ── Upload (no session needed, token auth) ──
        if path == "/upload":
            qs    = parse_qs(parsed.query)
            token = qs.get("token", [""])[0].strip()
            cfg   = load_config()
            if token != cfg.get("upload_token", ""):
                self.send_json({"ok": False, "error": "invalid token"}, 403)
                log.warning(f"Bad token from {self.client_address[0]}")
                return

            ctype, _ = cgi.parse_header(self.headers.get("Content-Type", ""))
            if ctype != "multipart/form-data":
                self.send_json({"ok": False, "error": "multipart required"}, 400); return

            form = cgi.FieldStorage(
                fp=self.rfile, headers=self.headers,
                environ={"REQUEST_METHOD": "POST",
                         "CONTENT_TYPE": self.headers.get("Content-Type")}
            )

            if "file" not in form:
                self.send_json({"ok": False, "error": "file field missing"}, 400); return

            up = form["file"]
            explicit_ip = form.getvalue("server_ip", "").strip()
            server_ip   = explicit_ip or self.client_address[0]

            orig = os.path.basename(getattr(up, "filename", "") or "")
            if not orig.lower().endswith(".db"):
                self.send_json({"ok": False, "error": "only .db files allowed"}, 400); return

            if not getattr(up, "file", None):
                self.send_json({"ok": False, "error": "invalid upload"}, 400); return

            content = up.file.read()
            if len(content) < 100:
                self.send_json({"ok": False, "error": "file too small / corrupt"}, 400); return
            if len(content) > 10 * 1024 * 1024:
                self.send_json({"ok": False, "error": "file too large (max 10MB)"}, 400); return

            ip_safe  = safe_name(server_ip.replace(".", "_"))
            filename = "backup__" + ip_safe + "__" + now_stamp() + ".db"
            tmp_path = os.path.join(BACKUP_DIR, filename + ".tmp")

            with open(tmp_path, "wb") as f:
                f.write(content)
            os.replace(tmp_path, os.path.join(BACKUP_DIR, filename))

            # Auto-register new server
            auto_register(server_ip)
            beat(server_ip)
            prune()

            log.info(f"Backup saved: {filename} ({fmt_size(len(content))})")
            self.send_json({"ok": True, "saved_as": filename, "server_ip": server_ip})
            return

        # ── Heartbeat (no session needed, token auth) ──
        if path == "/api/heartbeat":
            try:
                d     = self.read_json()
                token = d.get("token", "")
                cfg   = load_config()
                if token != cfg.get("upload_token", ""):
                    self.send_json({"ok": False, "error": "unauthorized"}, 403); return
                ip = d.get("server_ip", self.client_address[0])
                beat(ip)
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return

        # ── Auth required from here ──
        if not self.is_auth():
            self.send_json({"error": "unauthorized"}, 401); return

        # ── Delete server ──
        if path == "/api/delete-server":
            try:
                d   = self.read_json()
                ip  = d.get("ip", "").strip()
                if not ip:
                    self.send_json({"ok": False, "error": "ip required"}); return
                deleted = del_server_backups(ip)
                cfg = load_config()
                cfg["servers"] = [s for s in cfg.get("servers", []) if s.get("ip") != ip]
                save_config(cfg)
                log.info(f"Deleted server: {ip} ({deleted} backups)")
                self.send_json({"ok": True, "deleted": deleted})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return



        self.send_html("<h1>Not Found</h1>", 404)

def main():
    if not os.path.exists(CONFIG_FILE):
        save_config(DCFG)
    log.info(f"XUI Backup Hub v3.2 → http://{HOST}:{PORT}")
    server = ThreadingHTTPServer((HOST, PORT), H)
    server.serve_forever()

if __name__ == "__main__":
    main()
PYEOF

  # Inject the actual port number
  sed -i "s/__PORT__/${HUB_PORT}/" /root/backup-hub/backup_hub.py
  print_ok "backup_hub.py written."

  # Systemd service
  cat > /etc/systemd/system/backup-hub.service << 'SVCEOF'
[Unit]
Description=XUI Backup Hub v3.2
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
SVCEOF

  systemctl daemon-reload
  systemctl enable backup-hub
  systemctl restart backup-hub
  sleep 2

  if systemctl is-active --quiet backup-hub; then
    print_ok "backup-hub service running."
  else
    print_err "Service failed. Check: journalctl -u backup-hub -n 30"
  fi

  echo ""
  print_sep
  SERVER_IP_DISP=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo -e "${GREEN}${BOLD}  Hub installation complete!${NC}"
  echo ""
  echo -e "  ${BOLD}Web panel  :${NC}  http://${SERVER_IP_DISP}:${HUB_PORT}"
  echo -e "  ${BOLD}Username   :${NC}  ${WEB_USER}"
  echo -e "  ${BOLD}Password   :${NC}  ${WEB_PASS}"
  echo -e "  ${BOLD}Token      :${NC}  ${UPLOAD_TOKEN}  <- share this token with client servers"
  echo -e "  ${BOLD}Max backups:${NC}  ${MAX_BACKUPS} per server"
  echo ""
  echo -e "  ${YELLOW}Servers auto-register when they send their first backup.${NC}"
  print_sep
  pause
}

# ════════════════════════════════════════════════════════════
# SHARED: Write client agent file and restart service
# ════════════════════════════════════════════════════════════
write_client_agent() {
  # Can be called from install_client OR from manage_services → update
  mkdir -p /opt/xui-client
  # (در صورت نیاز، کد اضافه شود)
}

# ════════════════════════════════════════════════════════════
# 2. INSTALL CLIENT
# ════════════════════════════════════════════════════════════
install_client() {
  require_root
  print_banner; print_sep
  echo -e "  ${BOLD}Install Backup Client v3.2 (X-UI Server)${NC}"
  print_sep
  echo ""

  read -rp "  Hub server IP: " HUB_IP
  if [ -z "$HUB_IP" ]; then
    print_err "Hub IP required."; pause; return
  fi

  read -rp "  Hub port [default: 8080]: " HUB_PORT_IN
  HUB_PORT_CLIENT="${HUB_PORT_IN:-8080}"

  read -rp "  Token (configured during Hub installation): " SRV_TOKEN
  if [ -z "$SRV_TOKEN" ]; then
    print_err "Token required."; pause; return
  fi

  read -rp "  Backup interval in minutes [default: 2]: " INTERVAL_IN
  INTERVAL="${INTERVAL_IN:-2}"

  SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  HUB_URL="http://${HUB_IP}:${HUB_PORT_CLIENT}"

  print_info "Writing config..."
  mkdir -p /opt/xui-client

  cat > /etc/xui-backup-client.json << CONFIG_EOF
{
  "hub_url": "${HUB_URL}",
  "token": "${SRV_TOKEN}",
  "server_ip": "${SERVER_IP}",
  "agent_port": 8081
}
CONFIG_EOF
  print_ok "Config: /etc/xui-backup-client.json"

  print_info "Writing push script..."
  # Note: ${HUB_URL}, ${SRV_TOKEN}, ${SERVER_IP} are expanded NOW (install time)
  # \$(date ...) and \${STAMP} etc. are runtime variables
  cat > /usr/local/bin/xui-push-http.sh << SHEOF
#!/bin/bash
export TZ=Asia/Tehran

HUB_URL="${HUB_URL}"
TOKEN="${SRV_TOKEN}"
SERVER_IP="${SERVER_IP}"
LOG="/var/log/xui-push-http.log"
STAMP="\$(date '+%Y%m%d_%H%M%S')"
TMP_FILE="/tmp/xui_backup_\${STAMP}.db"

DB_PATH=""
for p in /etc/x-ui/x-ui.db /usr/local/x-ui/x-ui.db \
          /etc/3x-ui/x-ui.db /usr/local/3x-ui/x-ui.db \
          /opt/x-ui/x-ui.db /opt/3x-ui/x-ui.db; do
  if [ -f "\$p" ]; then DB_PATH="\$p"; break; fi
done

if [ -z "\$DB_PATH" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: XUI DB not found" >> "\$LOG"
  exit 1
fi

if ! cp "\$DB_PATH" "\$TMP_FILE" 2>/dev/null; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Cannot copy DB" >> "\$LOG"
  exit 1
fi

FILE_SIZE=\$(stat -c%s "\$TMP_FILE" 2>/dev/null || echo 0)
if [ "\$FILE_SIZE" -lt 100 ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: DB too small (\${FILE_SIZE}B)" >> "\$LOG"
  rm -f "\$TMP_FILE"; exit 1
fi

SUCCESS=0
for ATTEMPT in 1 2 3; do
  RESULT=\$(curl -s --max-time 30 -X POST \
    -F "server_ip=\${SERVER_IP}" \
    -F "file=@\${TMP_FILE}" \
    "\${HUB_URL}/upload?token=\${TOKEN}" 2>&1)
  CURL_EXIT=\$?
  if [ \$CURL_EXIT -ne 0 ]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ATTEMPT \${ATTEMPT}/3 curl error (\${CURL_EXIT})" >> "\$LOG"
  elif echo "\$RESULT" | grep -q '"ok":true'; then
    SUCCESS=1; break
  else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ATTEMPT \${ATTEMPT}/3 server error: \$RESULT" >> "\$LOG"
  fi
  [ "\$ATTEMPT" -lt 3 ] && sleep 5
done

rm -f "\$TMP_FILE"

if [ "\$SUCCESS" = "1" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] OK uploaded \${FILE_SIZE}B" >> "\$LOG"
else
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] FAIL all 3 attempts failed" >> "\$LOG"
fi

# Heartbeat
curl -s --max-time 10 -X POST \
  -H "Content-Type: application/json" \
  -d "{\"server_ip\":\"\${SERVER_IP}\",\"token\":\"\${TOKEN}\"}" \
  "\${HUB_URL}/api/heartbeat" > /dev/null 2>&1 || true
SHEOF
  chmod +x /usr/local/bin/xui-push-http.sh
  print_ok "Push script: /usr/local/bin/xui-push-http.sh"

  write_client_agent

  # Systemd: push timer
  cat > /etc/systemd/system/xui-push-backup.service << 'SVCEOF'
[Unit]
Description=XUI DB Push Backup
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/xui-push-http.sh
User=root
SVCEOF

  cat > /etc/systemd/system/xui-push-backup.timer << TIMEREOF
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
TIMEREOF



  echo ""
  print_info "Running initial backup test..."
  if /usr/local/bin/xui-push-http.sh; then
    print_ok "Test backup sent successfully."
  else
    print_err "Test failed. See: tail -10 /var/log/xui-push-http.log"
  fi

  echo ""
  print_sep
  echo -e "${GREEN}${BOLD}  Client installation complete!${NC}"
  echo ""
  echo -e "  ${BOLD}Hub URL     :${NC}  ${HUB_URL}"
  echo -e "  ${BOLD}Token       :${NC}  ${SRV_TOKEN}"
  echo -e "  ${BOLD}This IP     :${NC}  ${SERVER_IP}"
  echo -e "  ${BOLD}Interval    :${NC}  every ${INTERVAL} min"
  echo -e "  ${BOLD}Push log    :${NC}  /var/log/xui-push-http.log"

  print_sep
  pause
}

# ════════════════════════════════════════════════════════════
# 3. MANAGE SERVICES
# ════════════════════════════════════════════════════════════
manage_services() {
  while true; do
    print_banner; print_sep
    echo -e "  ${BOLD}Manage Services${NC}"; print_sep
    echo "   1) Hub status"
    echo "   2) Restart Hub"
    echo "   3) Stop / Start Hub"
    echo "   ──────────────────────────────────"
    echo "   4) Client timer status"
    echo "   5) Restart timer"
    echo "   6) Stop / Start timer"

    echo "   9) Send backup manually NOW"
    echo "  10) Update client agent code + restart"
    echo "   ──────────────────────────────────"
    echo "   0) Back"
    print_sep
    read -rp "  Choice: " SC
    case "$SC" in
      1) echo ""; systemctl status backup-hub --no-pager -l 2>/dev/null || print_err "Not installed."; pause ;;
      2) if systemctl restart backup-hub; then print_ok "Restarted."; else print_err "Failed."; fi; pause ;;
      3) if systemctl is-active --quiet backup-hub; then
           if systemctl stop backup-hub; then print_ok "Stopped."; else print_err "Failed."; fi
         else
           if systemctl start backup-hub; then print_ok "Started."; else print_err "Failed."; fi
         fi; pause ;;
      4) echo ""; systemctl status xui-push-backup.timer --no-pager 2>/dev/null || print_err "Not installed."
         echo ""; systemctl list-timers --all 2>/dev/null | grep -i xui || true; pause ;;
      5) if systemctl restart xui-push-backup.timer; then print_ok "Restarted."; else print_err "Failed."; fi; pause ;;
      6) if systemctl is-active --quiet xui-push-backup.timer; then
           if systemctl stop xui-push-backup.timer; then print_ok "Stopped."; else print_err "Failed."; fi
         else
           if systemctl start xui-push-backup.timer; then print_ok "Started."; else print_err "Failed."; fi
         fi; pause ;;

      9) if [ -f /usr/local/bin/xui-push-http.sh ]; then
           print_info "Sending backup..."
           if /usr/local/bin/xui-push-http.sh; then print_ok "Done."; else print_err "Failed."; fi

           print_err "Push script not found. Install client first."
         fi; pause ;;
     10) write_client_agent; pause ;;
      0) break ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════
# 4. LOGS
# ════════════════════════════════════════════════════════════
show_logs() {
  while true; do
    print_banner; print_sep
    echo -e "  ${BOLD}Logs${NC}"; print_sep
    echo "   1) Hub live log        (Ctrl+C to exit)"
    echo "   2) Hub last 50 lines"
    echo "   3) Hub log file        (last 50)"
    echo "   4) Client push live    (Ctrl+C to exit)"
    echo "   5) Client push last 50"
    echo "   6) Client push log file"

    echo "   0) Back"
    print_sep
    read -rp "  Choice: " LC
    case "$LC" in
      1) journalctl -u backup-hub -f ;;
      2) journalctl -u backup-hub -n 50 --no-pager; pause ;;
      3) if [ -f /root/backup-hub/logs/hub.log ]; then tail -50 /root/backup-hub/logs/hub.log; else print_err "Not found."; fi; pause ;;
      4) journalctl -u xui-push-backup.service -f ;;
      5) journalctl -u xui-push-backup.service -n 50 --no-pager; pause ;;
      6) if [ -f /var/log/xui-push-http.log ]; then tail -50 /var/log/xui-push-http.log; else print_err "Not found."; fi; pause ;;

      0) break ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════
# 5. UNINSTALL
# ════════════════════════════════════════════════════════════
uninstall() {
  require_root
  print_banner; print_sep
  echo -e "  ${RED}${BOLD}Uninstall${NC}"; print_sep
  echo "   1) Remove Backup Hub"
  echo "   2) Remove Client (timer)"
  echo "   3) Remove both"
  echo "   0) Back"
  print_sep
  read -rp "  Choice: " UC

  case "$UC" in
    1|3)
      print_info "Removing Hub..."
      systemctl stop backup-hub 2>/dev/null || true
      systemctl disable backup-hub 2>/dev/null || true
      rm -f /etc/systemd/system/backup-hub.service
      systemctl daemon-reload
      read -rp "  Delete /root/backup-hub and ALL backups? [y/N]: " DD
      if [[ "$DD" =~ ^[Yy]$ ]]; then
        rm -rf /root/backup-hub
        print_ok "All backup data deleted."
      fi
      print_ok "Hub removed."
      ;;
  esac

  case "$UC" in
    2|3)
      print_info "Removing client..."
      systemctl stop xui-push-backup.timer 2>/dev/null || true
      systemctl disable xui-push-backup.timer 2>/dev/null || true
      rm -f /etc/systemd/system/xui-push-backup.timer
      rm -f /etc/systemd/system/xui-push-backup.service
      rm -f /usr/local/bin/xui-push-http.sh
      rm -rf /opt/xui-client
      rm -f /etc/xui-backup-client.json
      rm -f /var/log/xui-push-http.log
      systemctl daemon-reload
      print_ok "Client removed."
      ;;
  esac

  if [ "$UC" != "0" ]; then
    print_ok "Uninstall complete."
  fi
  pause
}

# ════════════════════════════════════════════════════════════
# MAIN MENU
# ════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    print_banner; print_sep
    echo -e "  ${BOLD}Main Menu${NC}"; print_sep
    echo "   1) Install Backup Hub      (central server)"
    echo "   2) Install Backup Client   (X-UI server)"
    echo "   ─────────────────────────────────────────"
    echo "   3) Manage services"
    echo "   4) View logs"
    echo "   5) Uninstall"
    echo "   6) Update"
    echo "   ─────────────────────────────────────────"
    echo "   0) Exit"
    print_sep
    read -rp "  Your choice: " CHOICE
    case "$CHOICE" in
      1) install_hub ;;
      2) install_client ;;
      3) manage_services ;;
      4) show_logs ;;
      5) uninstall ;;
      6) update_menu ;;
      0) echo ""; print_ok "Goodbye."; echo ""; exit 0 ;;
      *) print_err "Invalid choice."; sleep 1 ;;
    esac
  done
}

# =============================
# Update Menu
# =============================
update_menu() {
  print_banner; print_sep
  echo -e "  ${BOLD}Update Options${NC}"
  print_sep
  echo "   1) Update from local file"
  echo "   2) Update from GitHub"
  echo "   3) Update from direct link (URL)"
  echo "   0) Back"
  print_sep
  read -rp "  Your choice: " UPD
  case "$UPD" in
    1)
      echo "Restarting current script (no file copy, always use this file as the source of truth)..."
      chmod +x "$0"
      exec "$0"
      ;;
    2)
      TMPF="/tmp/xui-backup-setup-latest.sh"
      echo "Downloading latest script from GitHub..."
      curl -fsSL -o "$TMPF" "https://raw.githubusercontent.com/Emadhabibnia1385/xui-backup-web/main/xui-backup-setup.sh" || { print_err "Download failed."; pause; return; }
      cp "$TMPF" "$0"
      chmod +x "$0"
      echo "Script updated from GitHub. Restarting..."
      exec "$0"
      ;;
    3)
      read -rp "Enter direct URL to new script: " URL
      TMPF="/tmp/xui-backup-setup-url.sh"
      curl -fsSL -o "$TMPF" "$URL" || { print_err "Download failed."; pause; return; }
      cp "$TMPF" "$0"
      chmod +x "$0"
      echo "Script updated from URL. Restarting..."
      exec "$0"
      ;;
    0) return ;;
    *) print_err "Invalid choice."; sleep 1 ;;
  esac
}

main_menu
