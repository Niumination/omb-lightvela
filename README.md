# OMB LightVela — OpenMausBot deployment

Stack produksi **OpenMausBot (OMB)** yang berjalan di `https://maus.abstract.biz.id`.

## Arsitektur

```
Internet ──► Cloudflare Tunnel ──► Caddy (network_mode: service:omb)
                                        │
                                        ▼
                              Container OMB (omb-lightvela:2026-10-18)
                              port 8799 (app) + 8800 (webhook)
                                        │
                              ┌─────────┴─────────┐
                              ▼                   ▼
                    omb-9router (20128)     Engine AI (opencode,
                    container berdiri       claude-code, codex, grok)
                    sendiri, alias
                    `omb-9router` di
                    network openmausbot_default
```

- **OMB** = `openmausbot-omb-1`, image `omb-lightvela:2026-10-18`, dibangun
  dari [Dockerfile](Dockerfile) di atas base `ghcr.io/milind-soni/openmausbot:latest`.
- **9router** = `omb-9router`, image `decolua/9router:0.5.104`, volume
  `omb_9router_data`. Tidak ikut compose supaya bisa di-restart tanpa
  menyentuh OMB (Caddy memakai `network_mode: service:omb`).
- **Caddy** = reverse proxy + TLS termination (Cloudflare Tunnel di depan).

## Provider model

| Provider | Jalur | Catatan |
|---|---|---|
| 9router (agnes, nous) | `opencode.json` → `http://omb-9router:20128/v1` | default: `9router/agnes/agnes-2.5-flash` |
| OpenRouter | config OMB (`openrouter.key`) | |
| Huancheng | config OMB (`openaiCompat`, `api.hcnsec.cn/v1`) | |
| opencode free (`oc/*`) | via 9router | 403 dari IP datacenter (gate opencode.ai) |

## Isi repo

```
compose.yaml          Compose utama (OMB + Caddy)
compose.override.yaml Override: NINEROUTER_API_KEY + mount opencode.json
Dockerfile            Image OMB (base openmausbot + engines)
Caddyfile             Config Caddy
config/config.json    Config OMB (secrets di-REDACTED)
config/opencode.json  Katalog model 9router untuk engine opencode
config/bots.json      Definisi bot
config/run-9router.sh Jalankan 9router (container berdiri sendiri)
```

## Menjalankan

```bash
# 1. Network + secret
docker network create openmausbot_default 2>/dev/null || true
export NINEROUTER_API_KEY=<key dari 9router>

# 2. Build & start OMB + Caddy
docker compose -f compose.yaml -f compose.override.yaml up -d

# 3. 9router (sekali, atau saat update)
./config/run-9router.sh
```

## Catatan operasional penting

- **Recreate OMB harus selalu `docker compose -f compose.yaml -f compose.override.yaml up -d`**
  (tanpa target service) — kalau hanya recreate `omb`, Caddy kehilangan
  network namespace dan `maus.abstract.biz.id` jadi 502.
- `opencode.json` adalah **bind mount yang ditulis OMB sendiri** (merge).
  Edit dari host bikin inode baru → container masih membaca file lama.
  Untuk update pakai base64 + `docker exec -u root`.
- 9router refresh token nous otomatis; kalau `nous/*` 401 cek
  `providerConnections` di `omb_9router_data`.

## Lisensi

Lihat LICENSE proyek hulu [OpenMausBot](https://github.com/milind-soni/OpenMausBot).
