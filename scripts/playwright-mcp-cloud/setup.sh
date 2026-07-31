#!/usr/bin/env bash
# =====================================================================
# Trisshul — Cloud Playwright MCP (one-time setup)
#
# Chalao / Run:  bash setup.sh
#
# Ye script ek Linux VM (Google Compute Engine, etc.) par Playwright MCP
# ko HTTP (streamable) mode me khada karti hai, taaki Claude app se — phone
# se bhi — remote browser testing ho sake. Reboot pe bhi chalta rahega.
#
# SECURITY MODEL (secret-URL + auto-open firewall):
#   - MCP sirf localhost par sunta hai (bahar se seedhe nahi milta).
#   - Saamne Caddy reverse-proxy hai jo SIRF ek lambe secret path ko
#     forward karta hai; baaki sab 404. Bina secret URL koi ghus nahi sakta.
#   - Firewall port apne-aap khul jaata hai (0.0.0.0/0), isliye phone ka IP
#     badle tab bhi firewall kabhi chhoona nahi padta — poori tarah automatic.
#   Connector URL:  http://<VM-IP>:<PORT>/<secret>/mcp
#
# Tested on: Debian/Ubuntu (apt). Run as a normal sudo-capable user, NOT root.
# =====================================================================
set -euo pipefail

# --- Config (override via env: PORT=443 bash setup.sh) ----------------
PW_MCP_VERSION="${PW_MCP_VERSION:-0.0.78}"   # match repo's .mcp.json
PORT="${PORT:-8931}"                         # public port (Caddy)
INTERNAL_PORT="${INTERNAL_PORT:-8930}"       # MCP, localhost-only
FW_RULE="pw-mcp-${PORT}"

if [[ "${EUID}" -eq 0 ]]; then
  echo "!! Isko root se mat chalao. Ek normal (sudo-capable) user se chalao."
  echo "!! Do not run as root — use a normal sudo-capable user so the service"
  echo "   runs unprivileged."
  exit 1
fi

echo "==> 1/7  System update + Node install"
sudo apt-get update -y
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
echo "    node $(node -v)"

echo "==> 2/7  Playwright MCP + Chromium install"
sudo npm install -g "@playwright/mcp@${PW_MCP_VERSION}"
# Chromium + system deps (headless). Downloads for the invoking user; the
# systemd service below runs as this same user so it finds the same cache.
npx --yes playwright install --with-deps chromium

echo "==> 3/7  Secret URL banao (yahi aapki asli suraksha hai)"
# Long, URL-safe, unguessable path segment. Isi ke bina koi endpoint tak
# nahi pahunch sakta. This secret IS the auth — keep it private.
SECRET="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
echo "${SECRET}" > "${HOME}/pw-mcp-secret.txt"
chmod 600 "${HOME}/pw-mcp-secret.txt"
echo "    Secret saved: ${HOME}/pw-mcp-secret.txt"

echo "==> 4/7  MCP systemd service (localhost-only, auto-restart, boot pe bhi)"
sudo tee /etc/systemd/system/pw-mcp.service >/dev/null << UNIT
[Unit]
Description=Playwright MCP (Trisshul) — localhost backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
Environment=NODE_OPTIONS=--max-old-space-size=1024
ExecStart=/usr/bin/npx --yes @playwright/mcp@${PW_MCP_VERSION} --headless --host 127.0.0.1 --port ${INTERNAL_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable pw-mcp
sudo systemctl restart pw-mcp

echo "==> 5/7  Caddy reverse-proxy (sirf secret path ko maane)"
if ! command -v caddy >/dev/null 2>&1; then
  sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y caddy
fi

# Only /<SECRET>/* is forwarded (prefix stripped → backend sees /mcp).
# Everything else → 404. So the public port is useless without the secret.
sudo tee /etc/caddy/Caddyfile >/dev/null << CADDY
:${PORT} {
	handle_path /${SECRET}/* {
		reverse_proxy 127.0.0.1:${INTERNAL_PORT}
	}
	handle {
		respond "Not found" 404
	}
}
CADDY

sudo systemctl enable caddy
sudo systemctl restart caddy
sleep 3
echo "    --- pw-mcp ---"; sudo systemctl status pw-mcp --no-pager | head -n 4 || true
echo "    --- caddy  ---"; sudo systemctl status caddy  --no-pager | head -n 4 || true

echo "==> 6/7  Firewall auto-open (port ${PORT} → 0.0.0.0/0; secret URL guards it)"
if command -v gcloud >/dev/null 2>&1; then
  if gcloud compute firewall-rules describe "${FW_RULE}" >/dev/null 2>&1; then
    gcloud compute firewall-rules update "${FW_RULE}" \
      --allow="tcp:${PORT}" --source-ranges=0.0.0.0/0 \
      || echo "    !! firewall update failed (permissions?) — kholni padegi manually"
  else
    gcloud compute firewall-rules create "${FW_RULE}" \
      --allow="tcp:${PORT}" --source-ranges=0.0.0.0/0 \
      --description="Playwright MCP (Trisshul) — secret-URL protected" \
      || echo "    !! firewall create failed (permissions?) — kholni padegi manually"
  fi
else
  echo "    gcloud nahi mila. Port manually kholo:"
  echo "      gcloud compute firewall-rules create ${FW_RULE} \\"
  echo "        --allow=tcp:${PORT} --source-ranges=0.0.0.0/0"
fi

echo "==> 7/7  Ho gaya! / Done"
IP="$(curl -s ifconfig.me || echo "<VM-EXTERNAL-IP>")"
cat << DONE
======================================================
  MCP URL (Claude app > Connectors me daalo / add here):
     http://${IP}:${PORT}/${SECRET}/mcp

  Ye URL hi aapki chaabi hai — kisi ke saath share mat karo.
  This full URL (with the secret) IS the credential — keep it private.

  Secret file:  ${HOME}/pw-mcp-secret.txt

  Useful:
     sudo systemctl status pw-mcp caddy   # service state
     sudo journalctl -u pw-mcp -f         # MCP logs
     sudo journalctl -u caddy -f          # proxy logs
     sudo systemctl restart pw-mcp caddy  # restart both
======================================================
DONE
