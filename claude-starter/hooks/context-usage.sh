#!/usr/bin/env bash
# Oturum context dolulugunu GERCEK olcer (tahmin DEGIL): transcript JSONL'deki son ana-context
# turunun API usage'ini okur -> input + cache_read + cache_creation = context penceresindeki token.
# Bu, /context'in gosterdigi sayidir; asistan /context'i calistiramadigi icin dogrudan buradan okur.
#
# Kullanim:
#   bash context-usage.sh [transcript.jsonl]            # arg verilmezse pwd'den otomatik bulur
#   echo '{"transcript_path":"..."}' | bash context-usage.sh   # hook stdin JSON'unu da kabul eder
# Pencere boyutu: CONTEXT_WINDOW env (varsayilan 1000000).
set -uo pipefail
WINDOW="${CONTEXT_WINDOW:-1000000}"
TR="${1:-}"

# 1) hook stdin'inden transcript_path (varsa)
if [ -z "$TR" ] && [ ! -t 0 ]; then
  IN="$(cat 2>/dev/null || true)"
  [ -n "$IN" ] && TR="$(printf '%s' "$IN" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
# 2) hala yoksa: pwd'den proje transcript dizinini bul (istemci: / ve . -> -)
if [ -z "$TR" ]; then
  for esc in "$(pwd | sed 's#[/.]#-#g')" "$(pwd | sed 's#/#-#g')"; do
    cand="$(ls -t "$HOME/.claude/projects/$esc"/*.jsonl 2>/dev/null | head -1)"
    [ -n "$cand" ] && { TR="$cand"; break; }
  done
fi
[ -n "$TR" ] && [ -f "$TR" ] || { echo "context-usage: transcript bulunamadi (arg ver ya da hook stdin kullan)"; exit 1; }

# Son ana-context turunun (sidechain degil, cache_read'i olan) usage toplami.
if command -v jq >/dev/null 2>&1; then
  TOTAL="$(jq -r 'select((.isSidechain // false) == false)
    | select(.message.usage.cache_read_input_tokens != null)
    | (.message.usage.input_tokens
       + (.message.usage.cache_read_input_tokens // 0)
       + (.message.usage.cache_creation_input_tokens // 0))' "$TR" 2>/dev/null | tail -1)"
else
  # jq yoksa yaklasik: son cache_read (context'in buyuk kismi).
  TOTAL="$(grep -o '"cache_read_input_tokens":[0-9]*' "$TR" | tail -1 | grep -o '[0-9]*')"
fi
[ -n "${TOTAL:-}" ] || { echo "context-usage: usage okunamadi"; exit 1; }

PCT="$(awk -v t="$TOTAL" -v w="$WINDOW" 'BEGIN{printf "%.1f", (t/w)*100}')"
LEVEL="$(awk -v p="$PCT" 'BEGIN{ if(p+0<50) print "devam"; else if(p+0<75) print "orta (ilk faz sinirinda handoff)"; else print "handoff+clear" }')"
echo "🔋 Oturum: %$PCT ($TOTAL/$WINDOW token) → $LEVEL"
