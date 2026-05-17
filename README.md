# Shore Tech Cloud — Enterprise In-House Sync Stack

Zero-licensing-cost file sync and web file management for Ubuntu hosts and Android (Syncthing) devices.

| Component | Role |
|-----------|------|
| [Syncthing](https://syncthing.net/) | Continuous device-to-device sync |
| [File Browser](https://filebrowser.org/) | Web UI for files under `data/` |
| [Nginx Proxy Manager](https://nginxproxymanager.com/) | HTTPS reverse proxy and Let's Encrypt |
| [DuckDNS](https://www.duckdns.org/) | Dynamic DNS for home/office public IP |

## Requirements

- Ubuntu Desktop or Server with Docker Engine and Docker Compose v2
- Router port forwarding (see below)
- DuckDNS subdomain and token
- Android devices with the Syncthing app (Play Store or F-Droid)

## Deploy to `~/sync-server`

```bash
git clone https://github.com/OLJE901753/shore-tech-cloud.git ~/sync-server
cd ~/sync-server
cp .env.example .env
# Edit .env: DUCKDNS_SUBDOMAIN, DUCKDNS_TOKEN, TZ, PUID/PGID if not 1000
./init.sh
docker compose up -d
```

Updates (preserve `data/` and `config/`):

```bash
cd ~/sync-server
git pull
docker compose pull
docker compose up -d
```

## Directory layout

```
~/sync-server/
├── docker-compose.yml
├── .env                 # secrets (not in git)
├── init.sh
├── config/              # per-service state (gitignored)
│   ├── syncthing/
│   ├── filebrowser/
│   ├── npm/
│   └── duckdns/
└── data/                # shared sync root (gitignored)
```

Place synced folders inside `data/`. Syncthing sees them at `/data`; File Browser serves them at `/srv` (same files).

## Services and ports

| Service | Host ports | Internal access |
|---------|------------|-----------------|
| Nginx Proxy Manager | 80, 443, 81 (admin) | `http://<host>:81` |
| Syncthing | 8384 (GUI), 22000/tcp+udp, 21027/udp | `http://<host>:8384` |
| File Browser | none (internal only) | `filebrowser:80` on `sync_net` |
| DuckDNS | none | logs only |

### Router port forwarding (Option A — real HTTPS)

Forward these ports from your router to the Ubuntu host LAN IP (e.g. `10.66.125.187`):

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (Let's Encrypt + redirects) |
| 443 | TCP | HTTPS |
| 22000 | TCP | Syncthing sync (Android fleet) |
| 21027 | UDP | Syncthing local discovery |

Do **not** expose Syncthing GUI (8384) to the public internet unless you protect it (VPN or NPM with access controls).

**Option A automated flow** (after router forwards 80 and 443):

```bash
cd ~/sync-server
./scripts/enable-acme-nginx.sh    # once: ACME path on your proxy host
./scripts/option-a-ssl.sh         # waits for port 80, runs certbot, prints next steps
```

Or in NPM: Proxy Host → SSL → Request certificate (same requirement: port 80 reachable).

## Nginx Proxy Manager setup

1. Open `http://<host-ip>:81`.
2. Log in (first boot: `admin@example.com` / `changeme` — **change immediately**).
3. **Hosts → Proxy Hosts → Add Proxy Host**
   - Domain: `<your-subdomain>.duckdns.org` (e.g. `shoretech.duckdns.org`)
   - Scheme: `http`
   - Forward hostname / IP: `filebrowser` (Docker service name — not `localhost`)
   - Forward port: `80`
4. **Details** tab — forward scheme must be **http** (not https) to `filebrowser:80`.
5. **SSL** tab (only after `./scripts/check-external-access.sh` shows OK for HTTP):
   - SSL Certificate: **Request a new SSL Certificate**
   - Force SSL, HTTP/2, and **I Agree to the Let's Encrypt Terms** enabled
   - Save; wait for certificate status **Valid**

If NPM shows **Internal Error**, run `./scripts/check-external-access.sh`. Port **80** must reach this PC from the internet for the default NPM certificate request.

**Without port forwarding:** try `./scripts/issue-ssl-duckdns-dns.sh`, then add the cert in NPM as **Custom**. DuckDNS DNS validation is often unreliable (CAA/TXT limits).

**LAN-only HTTPS (browser warning):** `./scripts/create-selfsigned-ssl.sh` → NPM → Custom certificate.

**Fix external access (run this first):**

```bash
./scripts/fix-external-access.sh           # stack + UFW + UPnP + verify + tunnel fallback
```

Or step by step:

```bash
sudo ./scripts/configure-host-firewall.sh    # UFW rules + local port check
sudo apt install -y miniupnpc && ./scripts/configure-router-upnp.sh   # auto router ports (if supported)
./scripts/router-port-forward-guide.sh     # manual router table
./scripts/verify-external-ports.sh         # internet-side port check
```

**No router port forwarding (interim only):**

```bash
./scripts/tunnel-fallback.sh start
./scripts/show-access-urls.sh   # …trycloudflare.com/login URL
```

When `verify-external-ports.sh` passes, stop the interim tunnel: `./scripts/tunnel-fallback.sh stop`

6. *(Optional)* Proxy `sync.<your-subdomain>.duckdns.org` → `syncthing:8384` for remote GUI access.

## DuckDNS

Set in `.env`:

- `DUCKDNS_SUBDOMAIN` — name only (e.g. `myhome` for `myhome.duckdns.org`)
- `DUCKDNS_TOKEN` — from the DuckDNS control panel

The `duckdns` container updates your IP every few minutes so Let's Encrypt and remote clients resolve correctly.

**After changing `.env`**, recreate DuckDNS so the container picks up new values:

```bash
docker compose up -d --force-recreate duckdns
docker compose logs duckdns --tail 5   # expect "successful", not "KO"
```

## Android (Google Pixel / fleet)

1. Install **Syncthing** from Play Store or F-Droid.
2. Run `./scripts/show-access-urls.sh` on the host and copy the **Device ID** (or open `http://<host-ip>:8384` → **Settings → Show ID**).
3. On Android: **Devices → +** → scan QR or paste the Ubuntu device ID.
4. On Ubuntu: accept the incoming device when prompted.
5. Share the **Shared** folder (`~/sync-server/data/shared`) to the Android device in the Syncthing UI on both sides.

For sync over the internet, ensure router forwards **22000/tcp** and **21027/udp**, and use your DuckDNS hostname or public IP in Syncthing if needed.

## File Browser first login

Set `FILEBROWSER_ADMIN_PASSWORD` in `.env` and run `./init.sh` again, **or** create a user manually (stop the container first to avoid database lock timeouts):

```bash
cd ~/sync-server
docker compose stop filebrowser
docker run --rm -u 1000:1000 \
  -v "$(pwd)/config/filebrowser:/config" \
  --entrypoint /bin/filebrowser \
  filebrowser/filebrowser:latest \
  users add admin 'YOUR_SECURE_PASSWORD' \
  -d /config/filebrowser.db --perm.admin
docker compose start filebrowser
```

Open `https://<your-subdomain>.duckdns.org` after NPM SSL is enabled (HTTP works on port 80 before SSL).

## Verification checklist

```bash
cd ~/sync-server
docker compose ps                    # all services running
curl -sf http://127.0.0.1:8384       # Syncthing GUI responds
curl -sf -o /dev/null http://127.0.0.1:81   # NPM admin UI
docker compose logs duckdns --tail 20        # no invalid token errors
echo "sync-test" > data/.verify && ls data/.verify
```

Confirm `data/.verify` appears in Syncthing and File Browser (via NPM).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Permission errors in `data/` | Re-run `./init.sh` or `chown -R $PUID:$PGID config data` |
| Let's Encrypt fails | Check DuckDNS A record, ports 80/443 forwarded, wait for DNS propagation |
| DuckDNS token errors | Verify `DUCKDNS_TOKEN` and `DUCKDNS_SUBDOMAIN` in `.env` |
| DuckDNS logs show `KO` | Run `docker compose up -d --force-recreate duckdns` after editing `.env` |
| File Browser 404 | Create an admin user (see above); empty DB has no login UI |
| File Browser 502 in NPM | Forward scheme must be **http** (not https); forward host `filebrowser`, port `80` |
| NPM "Internal Error" on SSL | Fix 502 first; forward port **80** on router; wait 1h if Let's Encrypt rate-limited |
| Let's Encrypt timeout | Router must forward **80** and **443** to this host; ISP may block port 80 |

## License

Infrastructure images are upstream open-source projects; this repository contains only deployment configuration.
