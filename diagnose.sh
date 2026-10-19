#!/bin/sh
# diagnose.sh — diagnostik READ-ONLY untuk OMB + 9router di LightVela.
#
# Skrip ini tidak menulis, tidak mengubah config, tidak me-restart apa pun.
#
#   docker compose exec omb sh /opt/omb/diagnose.sh
#
# Kirim SELURUH output-nya ke Hermes. Jangan menafsirkan sendiri.
# (Bagian H benar-benar menembak endpoint inferensi dan memakai ~1 request.)

set -u

h() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok() { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
no() { printf '  \033[31m[GAGAL]\033[0m %s\n' "$1"; }
i() { printf '  [..] %s\n' "$1"; }

OC="${OPENCODE_BIN:-/usr/local/bin/opencode}"
CFGDIR="${HOME:-/data}/.config/opencode"
CFG="$CFGDIR/opencode.json"
ROUTER="http://127.0.0.1:20128"

# ---------------------------------------------------------------- A. BINARI
h "A. Binari opencode"
if [ -x "$OC" ]; then
  ok "$OC ada, versi: $("$OC" --version 2>&1 | head -1)"
else
  no "$OC tidak ada atau tidak bisa dijalankan"
fi
i "jumlah binari opencode: $(ls -1 /usr/local/bin/opencode* 2>/dev/null | wc -l | tr -d ' ')"
i "PATH opencode yang dipakai: $(command -v opencode 2>/dev/null || echo '(tidak di PATH)')"
i "HOME=$HOME  XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-<kosong>}"
i "direktori config opencode: $CFGDIR"

# ------------------------------------------------------- B. opencode.json
h "B. opencode.json"
if [ -f "$CFG" ]; then
  ok "$CFG ada"
  i "ukuran: $(wc -c <"$CFG" | tr -d ' ') byte"
  i "provider yang dideklarasikan:"
  node -e '
    const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const p=c.provider||{};
    for(const k of Object.keys(p)) console.log("     "+k+"  ("+Object.keys(p[k].models||{}).length+" model)");
    if(!Object.keys(p).length) console.log("     (tidak ada)");
  ' "$CFG" 2>/dev/null || i "     (gagal dibaca sebagai JSON)"
  # Uji tulis — mount :ro akan gagal di sini, dan itu penyebab error EROFS.
  if touch "$CFG" 2>/dev/null; then ok "config bisa DITULIS (mount benar)"; else
    no "config TIDAK bisa ditulis -> mount :ro. OMB akan error EROFS saat inject model."; fi
else
  no "$CFG tidak ada. OMB akan membuatnya sendiri saat start."
fi

# ------------------------------------------------- C. KUNCI DI LINGKUNGAN
h "C. Kunci API di lingkungan omb"
for v in OPENROUTER_API_KEY NINEROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY GROQ_API_KEY KIMI_API_KEY MINIMAX_API_KEY MOONSHOT_API_KEY CLINE_API_KEY; do
  val=$(printenv "$v" 2>/dev/null || true)
  if [ -n "$val" ]; then ok "$v di-set (panjang ${#val})"; else i "$v kosong"; fi
done
i "catatan: OMB meneruskan HANYA 9 kunci ke opencode (config.ts:982). OPENROUTER_API_KEY"
i "       dan NINEROUTER_API_KEY TIDAK termasuk, tapi opencode tetap melihat keduanya"
i "       karena omb spawn 'opencode acp' dan mewariskan seluruh env (procs.ts:183)."

# ----------------------------------------------------- D. KATALOG MODEL
h "D. Katalog model opencode"
if MODELS=$("$OC" models 2>/dev/null); then
  i "total model: $(printf '%s\n' "$MODELS" | grep -c . | tr -d ' ')"
  for p in openrouter 9router opencode anthropic openai google; do
    n=$(printf '%s\n' "$MODELS" | grep -c "^$p/" || true)
    if [ "$n" -gt 0 ]; then ok "provider '$p': $n model"; fi
  done
  if [ "$(printf '%s\n' "$MODELS" | grep -c '^9router/' || true)" -eq 0 ]; then
    no "0 model '9router/'"
    i "   penyebab paling umum: blok \"models\" di provider 9router kosong."
    i "   opencode TIDAK auto-discover model openai-compatible (teruji)."
    i "   perbaiki: docker compose exec omb sh /opt/omb/gen-opencode-config.sh"
  fi
  if [ "$(printf '%s\n' "$MODELS" | grep -c '^openrouter/' || true)" -eq 0 ]; then
    i "0 model 'openrouter/' -> OPENROUTER_API_KEY kosong (wajar kalau Anda pakai 9router saja)"
  fi
  i "contoh model 9router:"
  printf '%s\n' "$MODELS" | grep '^9router/' | head -8 | sed 's/^/     /'
  i "contoh model OpenRouter :free:"
  printf '%s\n' "$MODELS" | grep '^openrouter/' | grep ':free$' | head -5 | sed 's/^/     /'
else
  no "'$OC models' gagal"
  "$OC" models 2>&1 | head -10 | sed 's/^/     /'
fi

# ------------------------------------------------------------- E. 9ROUTER
h "E. 9router"
if curl -fsS --max-time 5 "$ROUTER/api/health" >/dev/null 2>&1; then
  ok "9router hidup di $ROUTER"
  i "health: $(curl -fsS --max-time 5 "$ROUTER/api/health" 2>/dev/null | head -c 200)"
else
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$ROUTER/api/health" 2>/dev/null || echo 000)
  no "9router tidak menjawab di $ROUTER (kode HTTP: $code)"
  i "   periksa dari host:  docker compose ps 9router ; docker compose logs --tail=50 9router"
fi

KEY="${NINEROUTER_API_KEY:-}"
if [ -n "$KEY" ]; then
  if R=$(curl -fsS --max-time 15 -H "Authorization: Bearer $KEY" "$ROUTER/v1/models" 2>/dev/null); then
    n=$(printf '%s' "$R" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s).data||[]).length)}catch(e){console.log("bukan-JSON")}})' 2>/dev/null)
    ok "9router /v1/models menjawab: $n model"
    i "prefix provider yang tersambung:"
    printf '%s' "$R" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        try{const p=new Set((JSON.parse(s).data||[]).map(m=>String(m.id).split("/")[0]));
        console.log("     "+(p.size?[...p].sort().map(x=>x+"/").join(" ")+"  <- tiap prefix = satu provider aktif":"(kosong)"))}
        catch(e){console.log("     (gagal diurai)")}})' 2>/dev/null
    if [ "$n" = "0" ]; then
      no "9router punya 0 model -> belum ada provider tersambung di dashboard"
    fi
  else
    no "9router menolak /v1/models dengan kunci yang ada di env"
    i "   -> NINEROUTER_API_KEY salah/basi. Ambil ulang dari dashboard 9router."
  fi
else
  no "NINEROUTER_API_KEY kosong -> 9router tidak bisa dipakai"
  i "   isi di .env, lalu: docker compose up -d omb"
fi

# ------------------------------------------- F. KESELARASAN CONFIG vs 9ROUTER
h "F. Apakah model yang dideklarasikan cocok dengan 9router?"
if [ -n "$KEY" ] && [ -f "$CFG" ]; then
  R=$(curl -fsS --max-time 15 -H "Authorization: Bearer $KEY" "$ROUTER/v1/models" 2>/dev/null || echo '{}')
  CFG="$CFG" R="$R" node -e '
    const fs=require("fs");
    let live=[],decl=[];
    try{live=(JSON.parse(process.env.R).data||[]).map(m=>m.id)}catch(e){}
    try{const p=JSON.parse(fs.readFileSync(process.env.CFG,"utf8")).provider||{};
        decl=Object.keys((p["9router"]||{}).models||{})}catch(e){}
    const L=new Set(live);
    const mati=decl.filter(d=>!L.has(d));
    console.log("     dideklarasikan di opencode.json : "+decl.length);
    console.log("     benar-benar ada di 9router      : "+live.length);
    if(mati.length){
      console.log("     \x1b[33mTIDAK ADA di 9router (akan error saat dipakai):\x1b[0m");
      mati.slice(0,12).forEach(m=>console.log("       "+m));
      if(mati.length>12)console.log("       ...dan "+(mati.length-12)+" lainnya");
      console.log("     perbaiki: docker compose exec omb sh /opt/omb/gen-opencode-config.sh");
    } else if(decl.length){
      console.log("     \x1b[32msemua model yang dideklarasikan valid\x1b[0m");
    }
  ' 2>/dev/null || i "     (gagal membandingkan)"
else
  i "     dilewati (butuh NINEROUTER_API_KEY dan opencode.json)"
fi

# ----------------------------------------------------- G. INFERENSI GRATIS
h "G. Inferensi lewat 9router (memakai ~1 request)"
ALLMODELS=$("$OC" models 2>/dev/null || true)
TEST_MODEL="${TEST_MODEL:-}"
if [ -z "$TEST_MODEL" ]; then
  TEST_MODEL=$(printf '%s\n' "$ALLMODELS" | grep '^9router/' | grep -i 'free' | head -1)
fi
if [ -z "$TEST_MODEL" ]; then
  TEST_MODEL=$(printf '%s\n' "$ALLMODELS" | grep '^9router/' | head -1)
fi
if [ -n "$TEST_MODEL" ]; then
  i "mencoba: $TEST_MODEL"
  OUT=$("$OC" run -m "$TEST_MODEL" "Balas persis: OKE" 2>&1)
  RC=$?
  printf '%s\n' "$OUT" | tail -8 | sed 's/^/     /'
  if [ $RC -eq 0 ]; then ok "inferensi 9router BERHASIL (exit 0)"
  else no "inferensi 9router GAGAL (exit $RC)"; fi
else
  no "tidak ada model 9router untuk diuji"
fi

# ------------------------------------- H. INFERENSI GRATIS (OPENROUTER)
h "H. Inferensi lewat OpenRouter :free (pembanding)"
RM="openrouter/nvidia/nemotron-3.5-lightning:free"
if printf '%s\n' "$ALLMODELS" | grep -qx "$RM"; then
  OUT=$("$OC" run -m "$RM" "Balas persis: OKE" 2>&1); RC=$?
  printf '%s\n' "$OUT" | tail -5 | sed 's/^/     /'
  if [ $RC -eq 0 ]; then ok "OpenRouter gratis BERHASIL -> ini jalur cadangan yang terbukti"
  else no "OpenRouter gratis GAGAL (exit $RC) -> kemungkinan limit harian habis"; fi
else
  i "$RM tidak ada di katalog -> OPENROUTER_API_KEY kosong"
fi

# ------------------------------------------- I. FREE TIER BAWAAN OPENCODE
h "I. Free tier bawaan opencode (pembanding)"
i "model opencode/* di katalog: $(printf '%s\n' "$ALLMODELS" | grep -c '^opencode/')"
i "CATATAN PENTING: model ini MUNCUL di daftar tapi inferensinya di-blok 403."
i "  Teruji langsung: POST https://opencode.ai/zen/v1/chat/completions -> 403 FreeTierError"
i "  ('Your plan does not include access to opencode inference')."
i "  Jangan pakai jalur ini. Jangan coba mengakalinya lewat proksi header."

# ------------------------------------------------ J. SISA KREDENSIAL LAMA
h "J. Sisa kredensial dari image lama"
FOUND=0
for p in "$HOME/.config/google-chrome" "$HOME/.config/chromium" \
         "$HOME/.cache/ms-playwright" "$HOME/.cache/puppeteer" \
         /tmp/omb-search5.sh /tmp/omb-search6.sh /tmp/omb-search7.sh; do
  if [ -e "$p" ]; then no "ditemukan: $p"; FOUND=$((FOUND+1)); fi
done
[ "$FOUND" -eq 0 ] && ok "tidak ada profil browser atau skrip /tmp yang tersisa"

# ------------------------------------------------------- K. DISK & LOOP
h "K. Disk, proses, dan tanda-tanda loop retry"
i "ruang /data: $(df -h /data 2>/dev/null | tail -1 | awk '{print $3" terpakai dari "$2" ("$5")"}')"
i "jumlah proses: $(ps -e 2>/dev/null | grep -c . | tr -d ' ')"
i "chrome/chromium aktif: $(ps -e 2>/dev/null | grep -Ec 'chrome|chromium' | tr -d ' ')"
i "load rata-rata: $(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}')"
CORES=$(nproc 2>/dev/null || echo 1)
L1=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
if [ -n "$L1" ]; then
  HI=$(awk -v l="$L1" -v c="$CORES" 'BEGIN{print (l>c*0.9)?1:0}')
  if [ "$HI" = "1" ]; then
    no "load $L1 mendekati/melebihi $CORES core"
    i "   KEMUNGKINAN LOOP RETRY. Teruji: kalau upstream membalas respons yang"
    i "   bukan SSE streaming, opencode menembak ulang TANPA HENTI (ratusan request/detik)."
    i "   periksa dari host:  docker stats --no-stream"
  else
    ok "load $L1 untuk $CORES core — wajar"
  fi
fi
i "kalau dari host Anda bisa: docker stats --no-stream  (CPU omb/9router tinggi terus = loop)"

printf '\n\033[1mSelesai. Kirim SELURUH output ini ke Hermes.\033[0m\n'
