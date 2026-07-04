#!/usr/bin/env bash
# Stop hook — oturum >%75 dolulukta handoff onerisini GARANTI yuzeye cikarir; modelin
# "hatirlamasina" birakmaz (token yonetimi = temenni degil, esikte kapi).
# Olcumu context-usage.sh yapar. Bu hook YALNIZ handoff+clear esiginde ve LOOP-GUARD ile
# bir kez modeli durmadan once devam ettirir. Otomatik /clear YOK — onay kullanicinin (§4.4).
# Olcum basarisizsa fail-open (exit 0): asla yanlislikla bloklamaz.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IN="$(cat 2>/dev/null || true)"

# Loop guard: bu Stop zaten bir Stop-hook devamiysa tekrar bloklama (sonsuz dongu engeli).
case "$IN" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# Gercek context% — context-usage.sh stdin JSON'undaki transcript_path'i okur (ilk satir = ozet).
LINE="$(printf '%s' "$IN" | bash "$HERE/context-usage.sh" 2>/dev/null | head -1 || true)"

case "$LINE" in
  *"handoff+clear"*)
    # exit 2: stderr modele doner; model durmadan once handoff onerisini kullaniciya sunar.
    echo "OTURUM >%75 ($LINE). Yanitini kapatmadan: oturum-sagligi satirini + handoff/clear onerisini kullaniciya ACIKCA sun. Istenirse handoff skill'i ile docs/SESSION_STATE.md'ye devir yaz. Otomatik /clear YOK (onay kullanicinin)." >&2
    exit 2 ;;
  *) exit 0 ;;
esac
