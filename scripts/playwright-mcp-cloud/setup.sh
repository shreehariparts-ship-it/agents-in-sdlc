#!/usr/bin/env bash
# =====================================================================
# Trisshul — Cloud Playwright MCP (one-time setup)
#
# Chalao / Run:  bash setup.sh
#
# Ye script ek Linux VM (Google Compute Engine, etc.) par Playwright MCP
# ko HTTP (streamable) mode me khada karti hai, taaki Claude app se — phone
# se bhi — remote browser testing ho sake. Reboot pe bhi chalta rahega
# (systemd service).
#
# This stands up Playwright MCP in HTTP mode on a Linux VM so the Claude
# app (desktop or phone) can connect over the network and drive a real
# headless Chromium. It survives reboots via a systemd service.
#
# Tested on: Debian/Ubuntu (apt). Run as a normal sudo-capable user, NOT root.
# =====================================================================
set -euo pipefail

# --- Config (override via env: PORT=9000 bash setup.sh) ---------------
PW_MCP_VERSION="${PW_MCP_VERSION:-0.0.78}"   # match repo's .mcp.json
PORT="${PORT:-8931}"
HOST="${HOST:-0.0.0.0}"

if [[ "${EUID}" -eq 0 ]]; then
  echo "!! Isko root se mat chalao. Ek normal (sudo-capable) user se chalao."
  echo "!! Do not run as root — use a normal sudo-capable user so the service"
  echo "   runs unprivileged."
  exit 1
fi

echo "==> 1/6  System update + Node install"
sudo apt-get update -y
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
echo "    node $(node -v)"

echo "==> 2/6  Playwright MCP + Chromium install"
sudo npm install -g "@playwright/mcp@${PW_MCP_VERSION}"
# Chromium + system deps (headless). This downloads the browser for the
# invoking user; the systemd service below runs as this same user so it
# finds the same browser cache.
npx --yes playwright install --with-deps chromium

echo "==> 3/6  Token banao (optional — network firewall is the real guard)"
# NOTE: @playwright/mcp ka HTTP endpoint is version me bearer-token auth
# enforce nahi karta. Asli security = GCP firewall se source IP restrict
# karna (step 5). Ye token sirf ek label/marker hai.
#
# @playwright/mcp's HTTP endpoint does NOT enforce token auth in this
# version. The real protection is restricting the firewall source range
# (step 5) — treat this token as a label, not a security boundary.
TOKEN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
echo "${TOKEN}" > "${HOME}/pw-mcp-token.txt"
chmod 600 "${HOME}/pw-mcp-token.txt"
echo "    Token saved: ${HOME}/pw-mcp-token.txt"

echo "==> 4/6  systemd service (auto-restart + reboot pe bhi chale)"
MCP_BIN="$(command -v mcp-server-playwright || echo "")"
sudo tee /etc/systemd/system/pw-mcp.service >/dev/null << UNIT
[Unit]
Description=Playwright MCP (Trisshul) — HTTP mode
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
Environment=NODE_OPTIONS=--max-old-space-size=1024
ExecStart=/usr/bin/npx --yes @playwright/mcp@${PW_MCP_VERSION} --headless --host ${HOST} --port ${PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable pw-mcp
sudo systemctl restart pw-mcp
sleep 3
sudo systemctl status pw-mcp --no-pager | head -n 8 || true

echo "==> 5/6  Firewall — port ${PORT} kholo (GCP)"
cat << FW
    GCP par port ${PORT} kholne ke liye (aur SIRF apne IP se — recommended):

      MY_IP=\$(curl -s ifconfig.me)
      gcloud compute firewall-rules create pw-mcp-\${PORT} \\
        --allow=tcp:${PORT} \\
        --source-ranges=\${MY_IP}/32 \\
        --description="Playwright MCP (Trisshul) — restrict to my IP"

    Sabko khula chahiye to --source-ranges=0.0.0.0/0 (NOT recommended —
    koi bhi aapke browser ko drive kar sakta hai).
FW

echo "==> 6/6  Ho gaya! / Done"
IP="$(curl -s ifconfig.me || echo "<VM-EXTERNAL-IP>")"
cat << DONE
======================================================
  MCP URL (Claude app > Connectors me daalo / add here):
     http://${IP}:${PORT}/mcp

  Token (agar kabhi chahiye / if ever needed):
     $(cat "${HOME}/pw-mcp-token.txt")

  Useful:
     sudo systemctl status pw-mcp     # service state
     sudo journalctl -u pw-mcp -f     # live logs
     sudo systemctl restart pw-mcp    # restart
======================================================
DONE
