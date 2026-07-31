# Cloud Playwright MCP (Trisshul)

Stand up **Playwright MCP in HTTP mode** on a cloud Linux VM (Google Compute
Engine or any Debian/Ubuntu host) so the **Claude app — including from your
phone — can connect over the network and drive a real headless Chromium**.

This complements the repo's local Playwright MCP (`.mcp.json`, bundled Chromium
over stdio). Use this when the browser needs to live on an always-on host you
can reach from anywhere, not just inside a single session.

## Security model — secret URL + auto-open firewall

`@playwright/mcp`'s HTTP endpoint has **no built-in authentication**, so this
setup protects it with an **unguessable secret in the URL path** instead of
juggling firewall IPs:

- The MCP server binds to **`127.0.0.1` only** — it is never directly exposed.
- A **Caddy reverse proxy** sits in front and forwards **only** `/<secret>/*`
  to the local MCP (prefix stripped → backend sees `/mcp`). Every other path
  returns `404`, so the public port is useless without the secret.
- The firewall is **auto-opened to `0.0.0.0/0`**, so your phone's IP can change
  freely and you **never touch the firewall again** — the secret URL is the guard.

**The full connector URL (with the secret) IS your credential. Keep it private.**
It's saved at `~/pw-mcp-secret.txt` on the VM. Anyone who has the URL can drive
your browser — treat it like a password. To rotate it, re-run `setup.sh` (a new
secret is generated) and update the connector URL in the app.

## What `setup.sh` does

1. Installs Node 20 (via NodeSource) if missing.
2. Installs `@playwright/mcp` (pinned to `0.0.78`, matching `.mcp.json`) and
   headless Chromium with system deps.
3. Generates a 40-char secret at `~/pw-mcp-secret.txt`.
4. Registers a **systemd service** (`pw-mcp`) running MCP on `127.0.0.1:8930`.
5. Installs **Caddy** and configures it to proxy `:8931/<secret>/*` → the local
   MCP; everything else `404`.
6. **Auto-opens the GCP firewall** for the public port (`gcloud`, `0.0.0.0/0`).
7. Prints the **connector URL** to paste into the Claude app.

## Run

On the VM (as a normal **sudo-capable** user, *not* root):

```bash
bash setup.sh
```

Override defaults with env vars if needed:

```bash
PORT=443 INTERNAL_PORT=8930 PW_MCP_VERSION=0.0.78 bash setup.sh
```

When it finishes it prints:

```
http://<VM-EXTERNAL-IP>:8931/<secret>/mcp
```

## Connect from the Claude app

1. Open **Settings → Connectors** (desktop or mobile).
2. Add a custom connector with the printed URL (secret path included):
   `http://<VM-EXTERNAL-IP>:8931/<secret>/mcp`
3. The Playwright browser tools become available in your Claude sessions — now
   driving the cloud VM's Chromium. Try: *"open example.com and screenshot it."*

## Firewall

`setup.sh` opens it automatically when `gcloud` is present. If not (or it lacks
permission), open it once by hand — no IP restriction is needed because the
secret URL is the guard:

```bash
gcloud compute firewall-rules create pw-mcp-8931 \
  --allow=tcp:8931 --source-ranges=0.0.0.0/0 \
  --description="Playwright MCP (Trisshul) — secret-URL protected"
```

## Operate the services

```bash
sudo systemctl status pw-mcp caddy      # are they running?
sudo journalctl -u pw-mcp -f            # MCP logs
sudo journalctl -u caddy -f             # proxy logs
sudo systemctl restart pw-mcp caddy     # restart both
```

To tear down completely:

```bash
sudo systemctl disable --now pw-mcp caddy
sudo rm /etc/systemd/system/pw-mcp.service
sudo rm /etc/caddy/Caddyfile
sudo systemctl daemon-reload
gcloud compute firewall-rules delete pw-mcp-8931   # if you created it
```

## Notes

- HTTP mode uses the streamable-HTTP MCP transport; with the proxy the client
  endpoint is `/<secret>/mcp`.
- Navigation to public sites depends on the **VM's** egress, not your phone's —
  the browser runs on the VM.
- Keep `PW_MCP_VERSION` aligned with `.mcp.json` so local and cloud browsers
  behave the same.
- **Untested on a live VM from this repo** — the script provisions cloud
  infrastructure, so run it on your target host and use the operate/log commands
  above to confirm both services are green.
