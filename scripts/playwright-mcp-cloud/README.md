# Cloud Playwright MCP (Trisshul)

Stand up **Playwright MCP in HTTP mode** on a cloud Linux VM (Google Compute
Engine or any Debian/Ubuntu host) so the **Claude app — including from your
phone — can connect over the network and drive a real headless Chromium**.

This complements the repo's local Playwright MCP (`.mcp.json`, bundled Chromium
over stdio). Use this when the browser needs to live on an always-on host you
can reach from anywhere, not just inside a single session.

## What `setup.sh` does

1. Installs Node 20 (via NodeSource) if missing.
2. Installs `@playwright/mcp` (pinned to `0.0.78`, matching the repo's
   `.mcp.json`) and headless Chromium with its system deps.
3. Generates a marker token at `~/pw-mcp-token.txt` (see **Security** below).
4. Registers a **systemd service** (`pw-mcp`) that runs the MCP server in HTTP
   mode, auto-restarts on crash, and starts on boot.
5. Prints the exact `gcloud` firewall command to open the port.
6. Prints the **MCP URL** to paste into the Claude app.

## Run

On the VM (as a normal **sudo-capable** user, *not* root):

```bash
bash setup.sh
```

Override defaults with env vars if needed:

```bash
PORT=9000 PW_MCP_VERSION=0.0.78 bash setup.sh
```

When it finishes it prints:

```
http://<VM-EXTERNAL-IP>:8931/mcp
```

## Connect from the Claude app

1. Open **Settings → Connectors** (desktop or mobile).
2. Add a custom connector with the printed URL: `http://<VM-EXTERNAL-IP>:8931/mcp`.
3. The Playwright browser tools become available in your Claude sessions — now
   driving the cloud VM's Chromium.

## Open the firewall (GCP)

The MCP port must be reachable from your client. **Restrict the source range to
your own IP** — anyone who can reach the port can drive your browser.

```bash
MY_IP=$(curl -s ifconfig.me)
gcloud compute firewall-rules create pw-mcp-8931 \
  --allow=tcp:8931 \
  --source-ranges=${MY_IP}/32 \
  --description="Playwright MCP (Trisshul) — restrict to my IP"
```

Use `--source-ranges=0.0.0.0/0` only if you truly need it open to the world
(**not recommended**).

## Security

- **The token is a marker, not auth.** `@playwright/mcp`'s HTTP endpoint does
  not enforce bearer-token authentication in this version, so `~/pw-mcp-token.txt`
  is just a label. **Your real security boundary is the GCP firewall source
  range** — keep it scoped to your IP.
- A phone/laptop on a changing IP will need the firewall rule updated when the
  IP changes (`gcloud compute firewall-rules update pw-mcp-8931
  --source-ranges=<new-ip>/32`).
- The service runs **unprivileged** (as the invoking user), headless, and with a
  1 GB Node heap cap.

## Operate the service

```bash
sudo systemctl status pw-mcp      # is it running?
sudo journalctl -u pw-mcp -f      # live logs
sudo systemctl restart pw-mcp     # restart
sudo systemctl disable --now pw-mcp   # stop + don't start on boot
```

To tear down completely:

```bash
sudo systemctl disable --now pw-mcp
sudo rm /etc/systemd/system/pw-mcp.service
sudo systemctl daemon-reload
gcloud compute firewall-rules delete pw-mcp-8931   # if you created it
```

## Notes

- HTTP mode uses the streamable-HTTP MCP transport; the endpoint path is `/mcp`.
- Navigation to public sites depends on the **VM's** egress, not your phone's —
  the browser runs on the VM.
- Keep `PW_MCP_VERSION` aligned with the repo's `.mcp.json` so local and cloud
  browsers behave the same.
