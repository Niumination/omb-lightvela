#!/bin/sh
# gen-opencode-config.sh — tulis opencode.json dari model yang benar-benar
# ada di 9router Anda.
#
# KENAPA INI PERLU (teruji, bukan dugaan):
#   opencode TIDAK menemukan model otomatis dari provider openai-compatible.
#   Diuji dengan server tiruan di 127.0.0.1:20128:
#     tanpa blok "models"  -> `opencode models` = 0 model 9router
#     dengan blok "models" -> `opencode models` = 4 model 9router
#   Jadi setiap model harus dideklarasikan satu per satu.
#
#   Dan inferensi end-to-end terbukti jalan: opencode -> 127.0.0.1:20128/v1
#   -> model "9router/kr/glm-5" -> jawaban diterima, satu request.
#
# PAKAI:
#   docker compose exec omb sh /opt/omb/gen-opencode-config.sh
#
# Skrip ini MENIMPA daftar model di provider "9router" saja. Provider lain
# (termasuk yang di-inject OMB sendiri) dipertahankan — sama seperti perilaku
# merge OMB di opencode-go.ts:499.
#
# Sesudah menjalankan ini, restart omb supaya katalog model dibaca ulang:
#   docker compose restart omb

set -eu

ROUTER_URL="${ROUTER_URL:-http://127.0.0.1:20128/v1}"
KEY="${NINEROUTER_API_KEY:-}"
CONFIG="${HOME:-/data}/.config/opencode/opencode.json"

if [ -z "$KEY" ]; then
  echo "ERROR: NINEROUTER_API_KEY kosong." >&2
  echo "Ambil dari dashboard 9router, taruh di .env, lalu:" >&2
  echo "  docker compose up -d omb" >&2
  exit 1
fi

echo "Menanya 9router di $ROUTER_URL/models ..."
LIST=$(curl -fsS --max-time 20 -H "Authorization: Bearer $KEY" "$ROUTER_URL/models") || {
  echo "ERROR: tidak bisa mengambil daftar model dari 9router." >&2
  echo "Periksa: docker compose ps   dan   docker compose logs --tail=50 9router" >&2
  exit 1
}

mkdir -p "$(dirname "$CONFIG")"

ROUTER_URL="$ROUTER_URL" CONFIG="$CONFIG" LIST="$LIST" node <<'NODE'
const fs = require("node:fs");
const path = process.env.CONFIG;

let raw = [];
try { raw = JSON.parse(process.env.LIST).data ?? []; }
catch (e) { console.error("Respons /v1/models bukan JSON yang dikenali:", e.message); process.exit(1); }

const ids = raw.map((m) => m && m.id).filter((x) => typeof x === "string" && x.length > 0);
if (ids.length === 0) {
  console.error("9router melaporkan 0 model. Anda belum menyambungkan provider apa pun");
  console.error("di dashboard. Sambungkan minimal satu (mis. OpenCode Free / Kiro), lalu ulangi.");
  process.exit(1);
}

// Baca config lama supaya provider lain (termasuk inject OMB) tidak hilang.
let cfg = { $schema: "https://opencode.ai/config.json" };
if (fs.existsSync(path)) {
  try { cfg = JSON.parse(fs.readFileSync(path, "utf8")); }
  catch (e) { console.error("opencode.json lama tidak valid, dimulai dari kosong:", e.message); }
}

const providers = (cfg.provider && typeof cfg.provider === "object" && !Array.isArray(cfg.provider))
  ? { ...cfg.provider } : {};
const prev = (providers["9router"] && typeof providers["9router"] === "object")
  ? { ...providers["9router"] } : {};

const models = {};
for (const id of ids.sort()) models[id] = { name: id };

providers["9router"] = {
  ...prev,
  npm: prev.npm || "@ai-sdk/openai-compatible",
  name: prev.name || "9Router",
  options: { ...(prev.options || {}), baseURL: process.env.ROUTER_URL, apiKey: "{env:NINEROUTER_API_KEY}" },
  models,
};
cfg.provider = providers;

const backup = path + ".bak";
if (fs.existsSync(path)) fs.copyFileSync(path, backup);
fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");

console.log(`OK — ${ids.length} model dideklarasikan di provider "9router".`);
if (fs.existsSync(backup)) console.log("     config lama dicadangkan ke " + backup);
console.log("");
console.log("10 model pertama (ID yang dipakai di OMB diberi awalan '9router/'):");
for (const id of ids.sort().slice(0, 10)) console.log("  9router/" + id);
if (ids.length > 10) console.log(`  ... dan ${ids.length - 10} lainnya`);
console.log("");
console.log("Langkah terakhir:  docker compose restart omb");
NODE
