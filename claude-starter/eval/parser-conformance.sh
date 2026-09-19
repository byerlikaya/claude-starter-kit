#!/usr/bin/env bash
# PARSER CONFORMANCE — the gate's payload reader must agree with a real JSON parser.
#
# WHY THIS FILE EXISTS. guard-bash.sh read its payload through a ladder: jq, then python3, then a pure-bash
# slice. Three parsers meant three behaviours, and every parser incident this kit has had came from the tiers
# DIVERGING rather than from any one of them being weak:
#   * tier 3 was once `CMD="$INPUT"`, so every `git push` was hard-blocked as a force-push on any session id
#     containing `-f8`. CI never saw it, because CI has jq.
#   * Windows ships a python3 Store stub that satisfies `command -v` and cannot run, so stock desktops took
#     tier 2 and FAILED OPEN.
#   * a Windows-native jq writes stdout in TEXT mode, so tier 1 received `\` + CR + CR + LF where tier 3
#     received JSON's two-character escapes, and an ordinary commit was refused on one platform only.
# Each was found by a single assertion going red long after the change that caused it.
#
# TWO MODES, AND THE FILE CHOOSES BETWEEN THEM BY LOOKING AT THE HOOK.
#   LADDER PRESENT — the payload can still be read two ways, so the property is "both tiers reach the same
#     VERDICT". Exit codes are compared, not bytes: the tiers legitimately hand the rules different bytes and a
#     byte comparison would report those as defects and bury the one that is not.
#   LADDER ABSENT — there is only one reader in production, so a tier comparison would be the slice against
#     itself. The property becomes "the slice DECODES what a real parser decodes", measured against a reference
#     that never goes through the hook at all, plus "the gate still reaches the verdict each row declares".
# The DECODE check runs in BOTH modes on purpose. It costs nothing while the ladder is there and it means the
# normalisations below are already pinned by the time the ladder goes, rather than being written the same day
# they become the only thing standing.
#
# THE MODE DETECTOR IS ITSELF CALIBRATED, IN BOTH DIRECTIONS. It is the one place where this whole file can go
# quiet: a detector that wrongly says "ladder absent" against a ladder-ful hook stops exercising tier selection
# and says nothing about it. So two fixtures are built and the detector must answer each correctly before any
# mode runs.
#
# THE DECODE RULES ARE TAKEN FROM THE HOOK'S CASE ARMS, NOT FROM A MEASUREMENT. Pinning whatever the slice
# happens to do today would make the pin agree with any future change. _json_unescape maps:
#     \n -> LF   \t -> TAB   \r -> DROPPED   \b and \f -> one space
#     \uXXXX matching 00[2-7][0-9a-fA-F] (printable ASCII) -> that character
#     any other \uXXXX -> a single `?`          \<anything else> -> that character literally
# A row whose expected decode is `=` must match the reference EXACTLY; a row that exercises one of those
# normalisations carries the literal it must produce, so each normalisation is a stated fact and not an excuse.
#
# FIXTURES ARE BYTE-CHECKED BEFORE THEY ARE TRUSTED. A corpus of escapes is the easiest thing in this repo to
# measure vacuously: write `\\u002e` and the payload carries an escaped BACKSLASH followed by the letters
# u002e — inert text every reader agrees about while proving nothing; write it through a shell that expands
# escapes and the payload carries a real `.` and no parser ever sees an escape. Both shapes happened while this
# corpus was being built, on two different machines. So every escape row declares the escape it needs, the
# payload's bytes are searched for it, and a row whose fixture came out inert is reported UNMEASURED, never as
# a pass. Every backslash in a fixture is produced at RUN TIME by printf rather than written literally here,
# because a literal one has to survive every layer between an author and this file and in this repo it has not.
#
# Exit 0 = everything agreed. Exit 1 = a divergence, a broken fixture, or a calibration that did not answer.
# Exit 3 = nothing could be compared on this machine (no hook, or no reference parser). Never a pass.

set -u
LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/guard-bash.sh"
[ -f "$HOOK" ] || HOOK="$HERE/../../claude-starter/hooks/guard-bash.sh"
if [ ! -f "$HOOK" ]; then
  # Not a divergence and not a broken fixture — there was nothing to measure at all, which is what rc 3 means
  # everywhere else in this file. Exiting 1 here would report "the readers disagree" for a file that was merely
  # copied somewhere else, and a caller that maps 1 to "gate failed" would chase a bug that does not exist.
  echo "parser-conformance: guard-bash.sh bulunamadı ($HOOK) — HİÇBİR ŞEY ÖLÇÜLMEDİ, bu bir geçiş değildir"
  exit 3
fi

PASS=0; FAILED=0; UNMEASURED=0; KNOWN_OPEN=0
ok(){   PASS=$((PASS+1));   printf '  \033[32mOK\033[0m   %s\n' "$1"; }
bad(){  FAILED=$((FAILED+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
unm(){  UNMEASURED=$((UNMEASURED+1)); printf '  \033[33m????\033[0m %s\n' "$1"; }
note(){ printf '  ·    %s\n' "$1"; }

W="$(mktemp -d)"
trap 'cd /; rm -rf "$W"' EXIT INT TERM
P="$W/payload.json"
BS="$(printf '\\')"          # one real backslash, never written literally into this file

# ---------------------------------------------------------------------------------------------------------
# THE MODE DETECTOR, and its calibration in both directions.
# ---------------------------------------------------------------------------------------------------------
has_ladder(){ grep -q 'command -v jq' "$1"; }

mkdir -p "$W/det"
printf '%s\n' '#!/usr/bin/env bash' 'CMD=""' \
  'if command -v jq >/dev/null 2>&1 && CMD="$(jq -r .x)"; then :; fi' > "$W/det/with.sh"
printf '%s\n' '#!/usr/bin/env bash' 'CMD=""' 'CMD="$(_json_slice "$INPUT" command)"' > "$W/det/without.sh"

echo "== mod seçici, iki yönde de kalibre ediliyor =="
DETOK=1
if has_ladder "$W/det/with.sh"; then ok "merdivenli bir kapıda seçici 'merdiven VAR' diyor"
else bad "seçici merdivenli kapıyı kaçırdı — kip seçimi güvenilmez"; DETOK=0; fi
if has_ladder "$W/det/without.sh"; then bad "seçici merdivensiz kapıda 'VAR' dedi — sessizleşmenin tersi, yine de yanlış"; DETOK=0
else ok "merdivensiz bir kapıda seçici 'merdiven YOK' diyor"; fi
[ "$DETOK" = 1 ] || { echo; echo "SEÇİCİ KALİBRASYONU BAŞARISIZ — hangi kipin koşacağı bilinemez, hiçbir şey raporlanmıyor"; exit 1; }

LADDER=0; has_ladder "$HOOK" && LADDER=1
note "kapıda okuma merdiveni: $( [ "$LADDER" = 1 ] && echo 'VAR — iki katman karşılaştırılacak' || echo 'YOK — tek okuyucu, referansa karşı çözüm karşılaştırılacak' )"
echo

# ---------------------------------------------------------------------------------------------------------
# A REFERENCE PARSER. Real jq is preferred; otherwise a shim named `jq` is placed on PATH so the hook can still
# take its tier-1 branch while the ladder exists. The shim writes in binary: the Windows text-mode flavour is a
# separate, already-fixed defect and not what this file measures. perl comes before python3 because Git Bash
# ships perl with JSON::PP in core, while the python3 on PATH there is a Store stub that cannot run.
# ---------------------------------------------------------------------------------------------------------
REFKIND=""
if   command -v jq      >/dev/null 2>&1 && printf '{"a":"b"}' | jq -r '.a' 2>/dev/null | grep -qx b; then REFKIND=jq
elif command -v perl    >/dev/null 2>&1 && printf '{"a":"b"}' | perl -MJSON::PP -e 'local $/; print decode_json(<STDIN>)->{a}' 2>/dev/null | grep -qx b; then REFKIND=perl
elif command -v python3 >/dev/null 2>&1 && printf '{"a":"b"}' | python3 -c 'import sys,json;sys.stdout.write(json.load(sys.stdin)["a"])' 2>/dev/null | grep -qx b; then REFKIND=python3
elif command -v node    >/dev/null 2>&1 && printf '{"a":"b"}' | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).a))' 2>/dev/null | grep -qx b; then REFKIND=node
fi
if [ -z "$REFKIND" ]; then
  echo "  bu makinede JSON çözebilen ikinci bir araç yok (jq, perl, python3, node)."
  echo "  HİÇBİR ŞEY KARŞILAŞTIRILMADI. Bu bir geçiş değildir."
  exit 3
fi
note "referans çözücü: $REFKIND"

ref_decode(){ # the reference's own answer for .tool_input.command, straight from the payload
  case "$REFKIND" in
    jq)      jq -r '.tool_input.command // empty' < "$P" 2>/dev/null ;;
    perl)    perl -MJSON::PP -e 'local $/; my $j=decode_json(<STDIN>); binmode(STDOUT); print(($j->{tool_input}{command} // ""));' < "$P" 2>/dev/null ;;
    python3) python3 -c 'import sys,json;sys.stdout.write(json.load(sys.stdin).get("tool_input",{}).get("command",""))' < "$P" 2>/dev/null ;;
    node)    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let o;try{o=JSON.parse(s)}catch(e){process.exit(0)}process.stdout.write(((o.tool_input||{}).command)||"")})' < "$P" 2>/dev/null ;;
  esac; }

SHIM="$W/shim"; mkdir -p "$SHIM"; T1PATH=""
if [ "$REFKIND" != jq ]; then
  case "$REFKIND" in
    perl)    RUN='perl -MJSON::PP -e '\''local $/; my $j=decode_json(<STDIN>); binmode(STDOUT); my $k=$ENV{K}; print(($k eq "cmd" ? ($j->{tool_input}{command} // "") : ($j->{permission_mode} // "")), "\n");'\''' ;;
    python3) RUN='python3 -c '\''import sys,os,json;d=json.load(sys.stdin);k=os.environ["K"];sys.stdout.write((d.get("tool_input",{}).get("command","") if k=="cmd" else d.get("permission_mode",""))+"\n")'\''' ;;
    node)    RUN='node -e '\''let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let o;try{o=JSON.parse(s)}catch(e){process.exit(5)}const k=process.env.K;process.stdout.write((k==="cmd"?((o.tool_input||{}).command||""):(o.permission_mode||""))+"\n")})'\''' ;;
  esac
  { echo '#!/usr/bin/env bash'
    echo 'case "$2" in'
    echo "  '.tool_input.command // empty') K=cmd ;;"
    echo "  '.permission_mode // empty')    K=pm  ;;"
    echo '  *) exit 3 ;;'
    echo 'esac'
    echo "export K; $RUN"; } > "$SHIM/jq"
  chmod +x "$SHIM/jq"; T1PATH="$SHIM"
fi

# ---------------------------------------------------------------------------------------------------------
# THE SLICE, EXTRACTED. This is what production reads with once the ladder is gone, so it is compared against
# the reference directly rather than through the hook — a comparison routed through the hook would be the
# slice against itself the moment the ladder disappears.
# ---------------------------------------------------------------------------------------------------------
{ echo '#!/usr/bin/env bash'; echo 'INPUT="$(cat)"'
  awk '/^_json_slice\(\)/{f=1} f{print} f&&/^}$/{exit}' "$HOOK"
  awk '/^_json_unescape\(\)/{f=1} f{print} f&&/^}$/{exit}' "$HOOK"
  echo '_json_unescape "$(_json_slice "$INPUT" command)"'; } > "$W/dec.sh"
cp "$W/dec.sh" "$W/dec.good.sh"
if ! bash -n "$W/dec.sh" 2>/dev/null; then
  echo "  _json_slice / _json_unescape kapıdan çıkarılamadı — çözüm karşılaştırması yapılamaz"; exit 3; fi
slice_decode(){ bash "$W/dec.sh" < "$P" 2>/dev/null; }

# ---------------------------------------------------------------------------------------------------------
# A REPO FOR THE GATE TO JUDGE. §4.6 reads a review record, so without one every commit blocks for a reason
# that has nothing to do with parsing and the corpus would compare two identical refusals.
# ---------------------------------------------------------------------------------------------------------
R="$W/repo"; mkdir -p "$R"
( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name t \
  && echo one > a.txt && git add a.txt && git commit -qm init && echo two >> a.txt && git add a.txt \
  && mkdir -p .claude ) >/dev/null 2>&1
( cd "$R" && printf '{"diff_oid":"%s","head":"%s","ts":"t"}\n' \
    "$(git diff --cached | git hash-object --stdin)" "$(git rev-parse --verify --quiet HEAD)" \
    > .claude/review-pass.json )

t3(){ ( cd "$R" && bash "$HOOK" < "$P" >/dev/null 2>&1; printf '%s' "$?" ); }
t1(){ if [ -n "$T1PATH" ]; then ( cd "$R" && PATH="$T1PATH:$PATH" bash "$HOOK" < "$P" >/dev/null 2>&1; printf '%s' "$?" )
      else ( cd "$R" && bash "$HOOK" < "$P" >/dev/null 2>&1; printf '%s' "$?" ); fi; }

mk(){ printf '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"x"}' "$1" > "$P"; }
mkraw(){ printf '%s' "$1" > "$P"; }
hexof(){ printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
bytes(){ od -An -tx1 "$P" | tr -d ' \n'; }

# ---------------------------------------------------------------------------------------------------------
# CALIBRATION. Nothing below is reported unless every question here answers.
# ---------------------------------------------------------------------------------------------------------
echo
echo "-- kalibrasyon --"
CAL=1
mk 'rm -rf /'; a="$(t3)"
if [ "$a" = 2 ]; then ok "yıkıcı bir komut bloklanıyor (kapı gerçekten koşuyor)"; else bad "kalibrasyon: 'rm -rf /' rc=$a"; CAL=0; fi
mk 'ls -la';   a="$(t3)"
if [ "$a" = 0 ]; then ok "zararsız bir komut geçiyor (kapı aşırı bloklamıyor)"; else bad "kalibrasyon: 'ls -la' rc=$a"; CAL=0; fi

if [ "$LADDER" = 1 ]; then
  # the tier-1 branch must really be taken, or the second column is the first column twice
  if [ -n "$T1PATH" ]; then
    cp "$SHIM/jq" "$W/jq.real"
    { echo '#!/usr/bin/env bash'
      echo "case \"\$2\" in '.tool_input.command // empty') printf '%s\\n' 'rm -rf /' ;; '.permission_mode // empty') printf '%s\\n' default ;; *) exit 3 ;; esac"
    } > "$SHIM/jq"; chmod +x "$SHIM/jq"
    mk 'ls -la'; c="$(t1)"
    cp "$W/jq.real" "$SHIM/jq"; chmod +x "$SHIM/jq"
    if [ "$c" = 2 ]; then ok "tier 1 dalı gerçekten koşuluyor (stub başka komut döndürünce rc 0->2)"
    else bad "kalibrasyon: tier 1 dalına girilmiyor — ikinci sütun birincinin kopyası (rc=$c)"; CAL=0; fi
  else
    mk 'ls -la'
    if jq -r '.tool_input.command // empty' < "$P" 2>/dev/null | grep -qx 'ls -la'; then ok "tier 1 dalı gerçek jq ile koşuluyor"
    else bad "kalibrasyon: gerçek jq beklendiği gibi cevap vermiyor"; CAL=0; fi
  fi
fi

# the decode comparison must be able to SEE a difference, and must be able to FAIL
mk "echo a${BS}ud83d${BS}ude00b"
d_s="$(slice_decode)"; d_r="$(ref_decode)"
if [ "$d_s" != "$d_r" ]; then ok "bilinen çözüm farkı görünüyor (vekil çift: dilim '$d_s' · referans '$d_r')"
else bad "kalibrasyon: bilinen fark görünmüyor — çözüm karşılaştırması boş olabilir"; CAL=0; fi

# MUTATION MUST-FAIL: break the extracted slice and require the comparison to notice
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' "printf '%s' 'MUTASYON'" > "$W/dec.sh"
mk 'ls -la'; d_s="$(slice_decode)"; d_r="$(ref_decode)"
cp "$W/dec.good.sh" "$W/dec.sh"
if [ "$d_s" != "$d_r" ]; then ok "bozulmuş bir dilim çözüm karşılaştırmasında YAKALANIYOR (mutasyon testi)"
else bad "kalibrasyon: dilim kasten bozuldu ve karşılaştırma fark etmedi — kontrol ölü"; CAL=0; fi
mk 'ls -la'
if [ "$(slice_decode)" = "ls -la" ]; then ok "mutasyondan sonra gerçek dilim geri geldi"
else bad "kalibrasyon: mutasyon geri alınamadı, kalan satırlar bozuk dilimle ölçülürdü"; CAL=0; fi

if [ "$CAL" != 1 ]; then
  echo; echo "KALİBRASYON BAŞARISIZ — korpus raporlanmıyor, çünkü sonucu okunamaz."; exit 1; fi

# ---------------------------------------------------------------------------------------------------------
# THE CORPUS. Every row declares the verdict it expects, so a divergence is reported with its DIRECTION: a
# reader answering 0 where 2 was expected is a BLIND GATE; 2 where 0 was expected is an OVER-BLOCK, which
# teaches the user to reach for --no-verify and disarms all of §4.
#   $3 `need`  : the escape the fixture must really carry (`-` none, `hex:…` a whole byte sequence)
#   $5 `dec`   : `=` the slice must decode exactly what the reference decodes
#                anything else: the literal the documented normalisation must produce
# ---------------------------------------------------------------------------------------------------------
echo
echo "-- korpus --"

check_decode(){ # $1 label  $2 expectation
  local s r; s="$(slice_decode)"
  if [ "$2" = "=" ]; then
    r="$(ref_decode)"
    if [ "$s" = "$r" ]; then ok "$1 · çözüm referansla aynı"
    else bad "$1 · ÇÖZÜM AYRIŞIYOR: dilim [$s] · referans [$r]"; fi
  else
    if [ "$s" = "$2" ]; then ok "$1 · çözüm belgelenen normalleştirmeyi veriyor [$2]"
    else bad "$1 · NORMALLEŞTİRME BOZULDU: beklenen [$2] · ölçülen [$s]"; fi
  fi; }

run_row(){ # $1 label  $2 expected rc  $3 need  $4 command  $5 decode expectation
  local label="$1" exp="$2" need="$3" cmd="$4" dec="$5" a b h nh dh
  mk "$cmd"
  if [ "$need" != "-" ]; then
    h="$(bytes)"
    case "$need" in
      hex:*) nh="${need#hex:}"; dh="" ;;
      *)     nh="5c$(hexof "$need")"; dh="5c5c$(hexof "$need")" ;;
    esac
    if [ -n "$dh" ]; then case "$h" in *"$dh"*) unm "$label — fixture ATIL: kaçış çift yazılmış ($dh)"; return ;; esac; fi
    case "$h" in *"$nh"*) ;; *) unm "$label — fixture ATIL: payload'da $nh baytları yok"; return ;; esac
  fi
  check_decode "$label" "$dec"
  a="$(t3)"
  if [ "$LADDER" = 1 ]; then
    b="$(t1)"
    if [ "$a" != "$b" ]; then
      if [ "$a" = "$exp" ]; then bad "$label · AYRIŞIYOR: tier1 rc=$b, beklenen $exp $( [ "$exp" = 2 ] && echo '(tier1 KÖR)' || echo '(tier1 AŞIRI BLOKLUYOR)' )"
      else bad "$label · AYRIŞIYOR: tier3 rc=$a, beklenen $exp $( [ "$exp" = 2 ] && echo '(tier3 KÖR)' || echo '(tier3 AŞIRI BLOKLUYOR)' )"; fi
      return
    fi
  fi
  if [ "$a" = "$exp" ]; then ok "$label · hüküm rc=$a"
  else bad "$label · HÜKÜM YANLIŞ: rc=$a, beklenen $exp $( [ "$exp" = 2 ] && echo '(KÖR KAPI)' || echo '(AŞIRI BLOK)' )"; fi; }

U="${BS}u"     # the two characters a JSON unicode escape starts with, built at run time
run_row 'düz commit'                    2 -  'git commit -m c'                    '='
run_row 'pathspec commit'               2 -  'git commit -m c -- a.txt'           '='
run_row 'devam + LF'                    2 hex:5c5c5c6e  "git commit ${BS}${BS}${BS}n  -m c"   '='
run_row 'devam + CRLF'                  2 hex:5c5c5c72  "git commit ${BS}${BS}${BS}r${BS}n  -m c"  "git commit ${BS}"$'\n'"  -m c"
run_row 'CRLF ayraç'                    2 r  "git commit -m c${BS}r${BS}necho done"  "git commit -m c"$'\n'"echo done"
run_row 'yalnız CR'                     2 r  "git commit -m c${BS}recho done"        'git commit -m cecho done'
run_row 'sekme ayraçlı'                 2 t  "git commit${BS}t-m${BS}tc"             "git commit"$'\t'"-m"$'\t'"c"
run_row 'kaçışlı tırnak'                2 '"' "git commit -m ${BS}\"a b${BS}\""      'git commit -m "a b"'
run_row 'rm -rf kök'                    2 -  'rm -rf /'                           '='
run_row 'force push'                    2 -  'git push --force'                   '='
run_row 'git add -f'                    2 -  'git add -f secrets.env'             '='
run_row 'PowerShell özyinelemeli sil'   2 -  "Remove-Item -Recurse -Force C:${BS}${BS}x"  "Remove-Item -Recurse -Force C:${BS}x"
run_row 'gate betiği (düz)'             2 -  'echo x > .claude/hooks/guard-bash.sh'  '='
run_row 'gate betiği (\u kaçışlı)'      2 u  "echo x > ${U}002eclaude/hooks/guard-bash.sh"  'echo x > .claude/hooks/guard-bash.sh'
run_row 'gate yolunu okuma (\u)'        0 u  "cat ${U}002eclaude/hooks/guard-bash.sh"      'cat .claude/hooks/guard-bash.sh'
run_row 'latin kaçışları -> ?'          0 u  "echo ${U}00e7${U}011f${U}0131"        'echo ???'
run_row 'vekil çift -> ??'              0 u  "echo a${U}d83d${U}de00b"              'echo a??b'
run_row 'NUL kaçışı -> ?'               0 u  "echo a${U}0000b"                      'echo a?b'
run_row 'backspace -> boşluk'           0 b  "echo a${BS}bb"                        'echo a b'
run_row 'formfeed -> boşluk'            0 f  "echo a${BS}fc"                        'echo a c'
run_row 'kaçışlı bölü'                  0 /  "cat a${BS}/b${BS}/c.txt"              'cat a/b/c.txt'
run_row 'zararsız komut'                0 -  'echo not-a-command'                 '='
run_row 'boş komut'                     0 -  ''                                   '='

# ---------------------------------------------------------------------------------------------------------
# ADVERSARIAL SHAPES — whole objects rather than commands, because the question is which VALUE each reader
# takes for a key, not what the command says. RFC 8259 leaves duplicate names undefined, so neither "first
# wins" nor "last wins" is wrong on its own; what matters is that the gate does not judge one value while
# showing the user another.
# ---------------------------------------------------------------------------------------------------------
echo
echo "-- düşmanca biçimler --"
adv(){ # $1 label  $2 expected rc  $3 raw payload  [$4 known-open:<t3>/<t1>]
  local label="$1" exp="$2" a b known="${4:-}"
  mkraw "$3"; a="$(t3)"
  if [ "$LADDER" = 1 ]; then b="$(t1)"; else b="$a"; fi
  if [ -n "$known" ] && [ "${CSK_CONFORMANCE_KNOWN_OPEN:-0}" = 1 ]; then
    # A known-open row is a divergence this file FOUND that nothing has fixed yet. It is pinned to the exact
    # shape observed so it cannot rot: if the shape moves, or if the row starts passing, this FAILS and says so.
    local want="${known#known-open:}"
    if [ "$a" = "$b" ] && [ "$a" = "$exp" ]; then bad "$label — ARTIK GEÇİYOR: bulgu düzeltilmiş, known-open işareti kaldırılmalı"; return; fi
    if [ "$a/$b" = "$want" ]; then KNOWN_OPEN=$((KNOWN_OPEN+1))
      printf '  \033[33mAÇIK\033[0m %s — bilinen ayrışma, kayıtlı: %s (beklenen %s)\n' "$label" "$a/$b" "$exp"; return; fi
    bad "$label — bilinen ayrışma DEĞİŞTİ: kayıt $want, ölçülen $a/$b"; return
  fi
  if [ "$LADDER" = 1 ] && [ "$a" != "$b" ]; then
    bad "$label — AYRIŞIYOR: tier3 rc=$a · tier1 rc=$b (beklenen $exp)"; return; fi
  if [ "$a" = "$exp" ]; then ok "$label (rc=$a)"
  else bad "$label — rc=$a, beklenen $exp $( [ "$exp" = 2 ] && echo '(KÖR KAPI)' || echo '(AŞIRI BLOK)' )"; fi; }

adv 'command anahtarı iki kez'                 2 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"ls -la","command":"rm -rf /"},"tool_use_id":"x"}'
adv 'gövdede sahte command anahtarı'           2 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"description":"\"command\":\"ls\"","command":"rm -rf /"},"tool_use_id":"x"}'
adv 'gerçek anahtardan önce iç içe nesne'      2 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"meta":{"command":"ls -la"},"command":"rm -rf /"},"tool_use_id":"x"}'
adv 'kapanıştan önce kaçışlı tırnak'           2 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf / --no-preserve-root \"x\""},"tool_use_id":"x"}'
adv 'kapanıştan önce kaçışlı ters bölü'        0 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"echo C:\\\\"},"tool_use_id":"x"}'
adv 'anahtar sırası: tool_input önce'          2 \
  '{"tool_input":{"command":"rm -rf /"},"tool_name":"Bash","cwd":"/tmp","permission_mode":"default","tool_use_id":"x"}'

# tool_input carries NO command at all and the only `"command":` in the payload sits in a sibling object. A
# reader that answers `.tool_input.command` returns empty and, if it also records "I parsed it", the gate's
# "gated tool with no readable command" refusal never runs. Measured as a live fail-open on every jq machine.
adv 'komut yalnız kardeş nesnede'              2 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"foo":1},"meta":{"command":"rm -rf /"},"tool_use_id":"x"}'
# the must-pass twin, so "it now blocks everything" is excluded rather than assumed
adv 'sade payload hâlâ geçiyor (ikiz)'         0 \
  '{"cwd":"/tmp","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_use_id":"x"}'

# permission_mode twice: §4.4 fails CLOSED under bypassPermissions, so a nested earlier key that shadows the
# real one moves the gate from refuse to ask — and under bypass the harness answers ask with allow.
adv 'permission_mode iki kez (gölgeli bypass)' 2 \
  '{"cwd":"/tmp","meta":{"permission_mode":"default"},"permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_use_id":"x"}'
adv 'dürüst bypass (ikiz)'                     2 \
  '{"cwd":"/tmp","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_use_id":"x"}'
adv 'permission_mode yok (ikiz, meşru)'        2 \
  '{"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_use_id":"x"}'

# The key NAME written as a unicode escape. A reader that decodes key names finds `command` and judges
# `rm -rf /`; one that searches for the literal bytes finds nothing and the gate has no command to judge. The
# safe answer is the refusal either way, so 2 is expected and a reader answering 0 is BLIND, not lenient.
# The backslash is built at run time and the payload's BYTES are checked before the row is allowed to count:
# written literally, `c` has arrived here as `\\u0063` — an escaped backslash, inert text every reader
# agrees about — and the row would have reported a pass while measuring nothing.
ESCKEY="{\"cwd\":\"/tmp\",\"permission_mode\":\"default\",\"tool_name\":\"Bash\",\"tool_input\":{\"${BS}u0063ommand\":\"rm -rf /\"},\"tool_use_id\":\"x\"}"
case "$(printf '%s' "$ESCKEY" | od -An -tx1 | tr -d ' \n')" in
  *5c5c7530303633*) bad 'anahtar adı \u kaçışlı — fixture ATIL: çift ters bölü' ;;
  *5c7530303633*)   adv 'anahtar adı \u kaçışlı' 2 "$ESCKEY" ;;
  *)                bad 'anahtar adı \u kaçışlı — fixture kurulamadı' ;;
esac

echo
printf 'PARSER-CONFORMANCE: %s geçti · %s başarısız · %s ölçülemedi · %s bilinen-açık  (kip: %s · referans: %s)\n' \
  "$PASS" "$FAILED" "$UNMEASURED" "$KNOWN_OPEN" \
  "$( [ "$LADDER" = 1 ] && echo 'merdivenli' || echo 'tek okuyucu' )" "$REFKIND"
if [ "$KNOWN_OPEN" -gt 0 ]; then
  echo "$KNOWN_OPEN bilinen ayrışma AÇIK ve bu koşuda başarısızlık sayılmadı (CSK_CONFORMANCE_KNOWN_OPEN=1)."
fi
if [ "$FAILED" -gt 0 ]; then echo "Okuyucu referanstan ayrıştı ya da bir hüküm yanlış. Bu kapatılmalı."; exit 1; fi
if [ "$UNMEASURED" -gt 0 ]; then echo "Bazı satırlar ölçülemedi — bu bir geçiş değildir, fixture'ları düzeltin."; exit 1; fi
echo "Kapının okuyucusu her vakada referansla aynı sonuca vardı."
exit 0
