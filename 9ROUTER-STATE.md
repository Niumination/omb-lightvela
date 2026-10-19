# State 9router Docker (omb-9router)

Container: `omb-9router`, image `decolua/9router:0.5.104` (upstream public).
Volume: `omb_9router_data` → `/app/data` (DB SQLite berisi semua state).
Jalankan ulang: `./run-9router.sh`.

## State aktual (per 19 Okt 2026)

### Settings
- `headroomEnabled: false` — HEADROOM mati (log spam)
- `cavemanEnabled: true`, `ponytailEnabled: true`
- `providerOverrides: {}`, `comboStrategies: {}`
- Password dashboard: hash bcrypt di `settings.password` (volume). Nilai aktual TIDAK didokumentasikan di repo ini (pernah bocor di sini — sudah diganti).

### Provider connections
- `agnes` — aktif (E2E ✓)
- `nous` — OAuth via portal.nousresearch.com, client_id `hermes-cli`,
  access token JWT 1 jam + refresh_token; 9router refresh otomatis
  (refresh_token grant terverifikasi). E2E ✓

### API Keys
- `Default Key` — dipakai OMB via `NINEROUTER_API_KEY` (di config.json OMB,
  nilai aktual tersimpan di volume OMB `config.json` — REDACTED di repo ini)
- `hermes-test`, `cloud-test`, `cloud-agent`

### Combos
- `nous-combo-1`, `oc-agnes`

### Katalog model (kv)
- `nous/*` 9 model, `agnes/*` 4, `oc/*` 10, `mmf/mimo-auto`
- Total via /v1/models: 29

## Catatan

- `oc/*` = provider noAuth hardcoded, fetch live dari `opencode.ai/inference/v1`.
  Dari IP datacenter selalu 403 FreeTierError (gate IP opencode.ai) —
  bukan masalah config. TIDAK di-bypass (anti-abuse maintainer eksplisit); gunakan agnes/nous.
- nous token expired tidak masalah: 9router refresh sendiri via refresh_token.
- Kalau volume hilang: dashboard password = `INITIAL_PASSWORD` env
  (lihat run-9router.sh), lalu seed ulang providers/keys/combos manual
  atau restore backup volume.
