# OMB LightVela — OpenMausBot stack produksi (maus.abstract.biz.id)

Repo ini berisi **seluruh setup & konfigurasi** stack OMB aktif yang jalan di
`https://maus.abstract.biz.id` (server LightVela). Image produksi:
[`zaryu/omb-lightvela`](https://hub.docker.com/r/zaryu/omb-lightvela)
(tag `2026-10-18` / `latest`, public).

## Arsitektur

```
Cloudflare Tunnel (maus.abstract.biz.id)
  └─ caddy (openmausbot-caddy-1)      network_mode: service:omb — TLS termination
       └─ omb (openmausbot-omb-1)     image zaryu/omb-lightvela:2026-10-18, port 8799
            ├─ volume openmausbot_data:/data (config.json, bots.json, sesi, opencode auth)
            ├─ bind mount opencode.json → /data/.config/opencode/opencode.json (RW)
            └─ → 9router (omb-9router)  container berdiri sendiri, network openmausbot_default
                 ├─ image decolua/9router:0.5.104 (upstream public)
                 ├─ volume omb_9router_data:/app/data (providers, keys, combos)
                 ├─ dashboard: 127.0.0.1:20129/dashboard
                 └─ providers: agnes (E2E ✓), nous (OAuth auto-refresh ✓), oc/* (403 IP-gate),
                    katalog 29 model — detail: config/9ROUTER-STATE.md
```

Provider lain di config OMB: **huancheng** via `openaiCompatible` langsung
(`https://api.hcnsec.cn/v1` — bukan lewat 9router), **openrouter**.

> **Secrets**: nilai aktual (API keys, token) tidak ada di repo ini —
> semuanya ada di repo private **[Niumination/omb-lightvela-secrets](https://github.com/Niumination/omb-lightvela-secrets)**
> (config.json utuh, .env server, backup volume 9router).

## Isi repo

```
compose.yaml          stack omb + caddy (build image dari Dockerfile)
compose.override.yaml tambahan: env NINEROUTER_API_KEY + bind mount opencode.json
Dockerfile            base ghcr.io/milind-soni/openmausbot + opencode + grok CLI
Caddyfile             reverse proxy + TLS internal (tunnel di depan)
.env.example          variabel yang perlu diisi (salin → .env)
config/config.json    config OMB (secrets = [REDACTED] — isi live: providerKeys,
                      openrouter, composio, huancheng, opencodeGo)
config/opencode.json  katalog 20 model 9router (agnes/nous/oc/mmf/combo)
config/bots.json      definisi bot
config/run-9router.sh jalankan omb-9router (container berdiri sendiri)
config/9ROUTER-STATE.md  state aktual 9router: providers, keys, combos, katalog
```

## Menjalankan dari nol

```bash
# 1. OMB + Caddy
cp .env.example .env          # isi NINEROUTER_API_KEY dst.
docker compose -f compose.yaml -f compose.override.yaml build
docker compose -f compose.yaml -f compose.override.yaml up -d

# 2. 9router (container terpisah — TIDAK jadi service compose)
bash config/run-9router.sh
# lalu seed providers/API keys via dashboard 127.0.0.1:20129/dashboard
# (atau restore backup volume omb_9router_data)

# 3. Config OMB: isi providerKeys/openrouter/huancheng di config.json
#    (nilai aktual tersimpan di volume openmausbot_data → /data/.openmausbot/config.json)

# 4. Pairing WhatsApp: dashboard OMB > pairing code
```

## Catatan operasional penting

- **Recreate OMB wajib pakai kedua file compose** (`-f compose.yaml -f
  compose.override.yaml`) tanpa menarget service tertentu — Caddy memakai
  `network_mode: service:omb`, recreate parsial bikin Caddy 502.
- **opencode.json = bind mount**: mengedit file host lewat tool biasa membuat
  inode baru sehingga container tetap melihat file lama. Update in-place
  (mis. tulis via `docker cp` ke /tmp lalu copy internal), atau recreate OMB.
- **nous**: 9router refresh otomatis via refresh_token (portal.nousresearch.com,
  client_id `hermes-cli`). Refresh token one-time-use; kalau rusak → device flow ulang.
- **oc/\***: selalu 403 dari IP datacenter (FreeTierError, gate opencode.ai) —
  bukan masalah config; butuh egress IP residential.
- **9router dashboard**: password bcrypt di DB (`settings.password`); default
  via `INITIAL_PASSWORD`. Reset manual = tulis bcrypt hash langsung ke DB.
- Docker 29 + containerd snapshotter: image lama bisa "index tanpa layer"
  (push gagal *no platform*) → build ulang dari Dockerfile.
