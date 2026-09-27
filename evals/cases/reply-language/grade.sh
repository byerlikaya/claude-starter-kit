#!/usr/bin/env bash
# Grades the language of the reply (.eval-stdout.txt). Function words decide it, not topic words: a Turkish review
# of JavaScript is full of English identifiers, so counting "the/and/is" against "ve/bir/bu" is what tells the
# prose apart. Calibrated on a Turkish and an English review of this very diff before it was trusted.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
F=".eval-stdout.txt"
[ -s "$F" ] || { say NOT_MEASURED "no reply text to read"; exit 0; }
t="$(tr '[:upper:]' '[:lower:]' < "$F" | sed 's/`[^`]*`//g')"
tr_n="$(printf '%s\n' "$t" | grep -oE '(^|[^[:alnum:]])(ve|bir|bu|için|değil|ile|ama|olarak|yok|var|daha|gibi|çünkü|yalnızca|burada)([^[:alnum:]]|$)' | wc -l | tr -d ' ')"
en_n="$(printf '%s\n' "$t" | grep -oE '(^|[^[:alnum:]])(the|and|is|of|to|this|that|with|not|but|for|here|because|only)([^[:alnum:]]|$)' | wc -l | tr -d ' ')"
if [ "$tr_n" -ge 5 ] && [ "$tr_n" -gt "$en_n" ]; then say PASS "reply is Turkish ($tr_n Turkish function words, $en_n English)"
else say FAIL "reply is not Turkish ($tr_n Turkish function words, $en_n English)"; fi
