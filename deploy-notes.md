# Deploy notes — 29 Okt 2026

Perubahan dari kondisi live server (VM-6-34-ubuntu):

1. **Caddyfile** — pure reverse proxy ke `127.0.0.1:8799` (host network).
   OMB v0.1.130 menangani `/hooks/*` sendiri, route terpisah ke 8800 dihapus.
2. **opencode.json** — baseURL 9router `omb-9router:20128` → `127.0.0.1:20128`
   (host network; Docker DNS name tidak resolve). apiKey tetap env-var.
3. **Container live**: `omb-test-v2` (image ghcr.io/milind-soni/openmausbot:latest
   v0.1.130, network host, OMB_PORT 8799) + `omb-caddy-v2` (host network, bind
   mount Caddyfile+assets :ro) + `omb-9router` (127.0.0.1:20129->20128).
   Compose file live ada di ~/niumination/OpenMausBot/deploy/docker-compose.yml.
