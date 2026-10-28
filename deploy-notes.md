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

## Pemeliharaan disk — 29 Okt 2026

Disk sempat 90% (42G/50G). Penyebab: backup-repo GPG 6.2G, state-snapshots
2.4G (17 snapshot lama), containerd dangling image 1.9G, pnpm store 2.3G,
npm/uv cache ~0.9G.

Tindakan:
- Deployment OMB dimatikan sementara (omb-test-v2 + omb-caddy-v2 stopped).
  `omb-9router` tetap jalan.
- state-snapshots: hanya 3 terbaru disimpan (2.4G → 377M)
- containerd: dangling image openmausbot lama dihapus (5.5G → 3.6G)
- pnpm store prune (2.3G → 16M), npm/uv/node-gyp cache dibersihkan
- Docker image :latest lama dihapus (akan pull ulang saat upgrade)
- backup-repo: `git gc` biasa (bukan aggressive) di background

Hasil: 90% → 72% (14G free).
Upgrade image OMB ke build terbaru DITAHAN sampai backup /data terverifikasi.
