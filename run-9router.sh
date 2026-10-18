#!/bin/bash
# Jalankan 9router untuk stack OMB (container berdiri sendiri di network OMB).
# Alasan tidak jadi service compose: 9router harus bisa di-restart tanpa
# menyentuh OMB, dan Caddy memakai network_mode: service:omb (namespace sama).
set -e

docker run -d --name omb-9router \
  --network openmausbot_default \
  --network-alias omb-9router \
  --restart unless-stopped \
  -p 127.0.0.1:20129:20128 \
  -v omb_9router_data:/app/data \
  -e PORT=20128 \
  -e HOSTNAME=0.0.0.0 \
  -e NODE_ENV=production \
  -e NEXT_TELEMETRY_DISABLED=1 \
  -e REQUIRE_API_KEY=true \
  -e DATA_DIR=/app/data \
  -e "INITIAL_PASSWORD=__GANTI_DI_SINI__" \
  decolua/9router:0.5.104

echo "omb-9router jalan. Dashboard: http://127.0.0.1:20129/dashboard"
echo "Ganti password: Settings > Change Password (default: INITIAL_PASSWORD di atas)."
