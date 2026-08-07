#!/usr/bin/env bash
# Install-time skill/agent security scanner — zero-dep bash + regex. Scans a directory or file (meant for a
# project's EXISTING third-party .claude skills/agents that adopt.sh will coexist with) for supply-chain red flags
# and scores each file:  score = 100 − CRIT×20 − HIGH×10 − MED×3 − LOW×1  (floored at 0).
#   SAFE  ≥ 90 AND no CRIT/HIGH   ·   REVIEW  70–89, or any HIGH   ·   DANGER  < 70, or any CRIT
#
# ADVISORY + HEURISTIC. It substring-matches, so a *security-education* skill (a red-team guide, an exfil example)
# can legitimately score low — REVIEW the flagged file, don't trust the number blindly. Its job is to SURFACE
# curl|bash, prompt-injection directives, credential/exfil patterns, not to prove intent.
#
# Exit: 0 if every scanned file is SAFE, 1 if any is REVIEW/DANGER (so a caller like adopt.sh can gate on it).
# Usage:  bash scan-skill.sh [path]   (default: .claude)
set -uo pipefail
TARGET="${1:-.claude}"

# --- pattern groups (ERE) ------------------------------------------------------------------------------------
# CRIT: download-and-exec, known exfil/collaborator hosts, rm -rf of home/root.
CRIT='(curl|wget|fetch)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|python[0-9.]*|node|perl|ruby)|(bash|sh)[[:space:]]+<\(|(webhook\.site|requestbin|pipedream\.net|ngrok\.io|burpcollaborator|oastify|interactsh|dnslog\.|\.oast\.)|rm[[:space:]]+-[A-Za-z]*r[A-Za-z]*[[:space:]]+(~|/|\$HOME)([[:space:]]|$|/)'
# HIGH: prompt-injection directives; a credential file READ/exfil (a reader verb + the path — a bare `~/.ssh/id_rsa`
# config value is NOT flagged); base64-decode piped to a shell.
HIGH='ignore[[:space:]]+(all[[:space:]]+)?(the[[:space:]]+)?(previous|prior|above)[[:space:]]+(instruction|prompt)|disregard[[:space:]]+(the[[:space:]]+|all[[:space:]]+)?(previous|above|prior)|ignore[[:space:]]+your[[:space:]]+(system[[:space:]]+)?(prompt|instruction)|(cat|less|more|tail|head|base64|xxd|od|strings|curl|wget|scp|cp|rsync)[^|]*(~/\.ssh|id_rsa|/etc/(passwd|shadow)|\.aws/credentials|\.netrc|\.git-credentials)|(~/\.ssh|id_rsa|/etc/(passwd|shadow)|\.aws/credentials|\.netrc|\.git-credentials)[^|]{0,80}(curl|wget|scp|nc |netcat|base64|exfiltrat)|base64[[:space:]]+-[A-Za-z]*d[^|]*\|'
# MED: named cloud/CI secret env vars, process.env secret access, chmod 777, code eval/exec.
MED='(GITHUB_TOKEN|AWS_SECRET|AWS_ACCESS_KEY|NPM_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|SLACK_TOKEN)|process\.env\.[A-Za-z_]*(TOKEN|SECRET|KEY|PASSWORD)|chmod[[:space:]]+(-R[[:space:]]+)?0?777|[^a-zA-Z](eval|exec)[[:space:]]*\('
# LOW: an outbound URL fetch or a raw socket — common in benign deploy/example prose, hence low weight.
LOW='(^|[^a-zA-Z])(curl|wget)[[:space:]]+[^|]*https?://|/dev/tcp/|[^a-zA-Z]nc[[:space:]]+-[A-Za-z]*e'

FAIL=0; N=0
# The score ranks; the SEVERITY decides. A single HIGH costs 10 points and lands on exactly 90 — the SAFE line —
# so one credential-exfil line or one prompt-injection directive used to pass as safe on arithmetic alone. That
# is the wrong way round: the score exists to order a review queue, not to let a high-severity hit through it.
# So severity floors the verdict — any CRIT is DANGER, any HIGH is never SAFE — and the number still ranks what
# is left. (Measured: the kit's own 59 payload files carry no CRIT or HIGH at all, lowest score 99.)
verdict(){   # $1 = score, $2 = crit count, $3 = high count
  if [ "${2:-0}" -gt 0 ]; then echo DANGER; return; fi
  if [ "${3:-0}" -gt 0 ]; then [ "$1" -ge 70 ] && echo REVIEW || echo DANGER; return; fi
  if [ "$1" -ge 90 ]; then echo SAFE; elif [ "$1" -ge 70 ]; then echo REVIEW; else echo DANGER; fi; }

# One grep PER SEVERITY over ALL files, not four greps per file.
#
# Measured on a user's Windows machine: scanning 64 files took 8m07s — user 12.6s, sys 2m46s. The regex work is
# not the cost; process creation is. Git Bash has no real fork, so every spawn is a CreateProcess plus MSYS
# emulation plus an antivirus scan of the binary, and 64 files × 4 greps = 256 of them. adopt.sh calls this on
# every refresh, which is where most of a "the update is hung" report actually went.
#
# grep accepts many files at once and `-cH` prints `path:count` for each, including zeros — so the same regex
# engine, the same `-i` semantics and the same per-file line counts come back in 4 processes instead of 256.
# Deliberately NOT rewritten in awk: these patterns carry intervals and alternations whose behaviour would have
# to be re-proved against a different engine, and the win here is process count, not matching speed.
counts_of(){   # $1 = pattern, $2 = output file. `path:count` per input file, in the order given.
  grep -cHiE "$1" -- "${FILES[@]}" > "$2" 2>/dev/null
  return 0     # grep exits 1 when nothing matched anywhere; that is a normal result, not an error
}

# Sets the named array AND the global RC_N. Deliberately not "$(read_counts …)": command substitution runs in a
# SUBSHELL, so the array assignments would be discarded and every file would score a spotless 100. That is exactly
# what the first version did — and the output diff against the old implementation is what caught it.
read_counts(){ # $1 = grep -cH output file, $2 = array name
  local line i=0
  while IFS= read -r line; do
    # split from the RIGHT: a path may contain ':' (a Windows drive letter), a count never does
    eval "$2[$i]=\"\${line##*:}\""
    i=$((i+1))
  done < "$1"
  RC_N=$i
}

emit(){        # prints one line per file, in FILES order, from the four count arrays
  local f c h m l score v i=0
  while [ "$i" -lt "${#FILES[@]}" ]; do
    f="${FILES[$i]}"
    c="${CNT_C[$i]:-0}"; h="${CNT_H[$i]:-0}"; m="${CNT_M[$i]:-0}"; l="${CNT_L[$i]:-0}"
    i=$((i+1))
    score=$((100 - c*20 - h*10 - m*3 - l*1)); [ "$score" -lt 0 ] && score=0
    v="$(verdict "$score" "$c" "$h")"
    N=$((N+1))
    case "$v" in
      SAFE)   printf '  ✅ %-3s %s\n' "$score" "$f" ;;
      REVIEW) printf '  ⚠️  %-3s %s  (crit:%s high:%s med:%s low:%s) — REVIEW\n' "$score" "$f" "$c" "$h" "$m" "$l"; FAIL=1 ;;
      DANGER) printf '  ❌ %-3s %s  (crit:%s high:%s med:%s low:%s) — DANGER\n' "$score" "$f" "$c" "$h" "$m" "$l"; FAIL=1 ;;
    esac
  done
}

# A single file keeps the old path: grep prints a bare count with one argument, so the batch parser would have to
# special-case it anyway, and one file means one process either way.
scan_file(){
  local f="$1"
  local c h m l
  # grep -c prints the count (0 on no match) and exits 1 on no match; that non-zero exit is fine here (no set -e),
  # and a `|| echo 0` would DOUBLE the printed 0 and break the arithmetic — so don't add one.
  c=$(grep -icE "$CRIT" "$f" 2>/dev/null); h=$(grep -icE "$HIGH" "$f" 2>/dev/null)
  m=$(grep -icE "$MED"  "$f" 2>/dev/null); l=$(grep -icE "$LOW"  "$f" 2>/dev/null)
  c=${c:-0}; h=${h:-0}; m=${m:-0}; l=${l:-0}
  local score=$((100 - c*20 - h*10 - m*3 - l*1)); [ "$score" -lt 0 ] && score=0
  local v; v="$(verdict "$score" "$c" "$h")"
  N=$((N+1))
  case "$v" in
    SAFE)   printf '  ✅ %-3s %s\n' "$score" "$f" ;;
    REVIEW) printf '  ⚠️  %-3s %s  (crit:%s high:%s med:%s low:%s) — REVIEW\n' "$score" "$f" "$c" "$h" "$m" "$l"; FAIL=1 ;;
    DANGER) printf '  ❌ %-3s %s  (crit:%s high:%s med:%s low:%s) — DANGER\n' "$score" "$f" "$c" "$h" "$m" "$l"; FAIL=1 ;;
  esac
}

echo "== skill/agent security scan: $TARGET =="
if [ -f "$TARGET" ]; then
  scan_file "$TARGET"
elif [ -d "$TARGET" ]; then
  # Skill/agent definition files only (markdown). Skip the kit's own -csk agents (trusted, not third-party).
  FILES=()
  while IFS= read -r f; do
    case "$f" in *-csk.md) continue ;; esac
    FILES+=("$f")
  done < <(find "$TARGET" \( -name 'SKILL.md' -o -name '*.md' \) -path '*/skills/*' -o -path '*/agents/*' -name '*.md' 2>/dev/null | sort -u)
  if [ "${#FILES[@]}" -le 1 ]; then
    [ "${#FILES[@]}" -eq 1 ] && scan_file "${FILES[0]}"
  else
    ST="$(mktemp -d)"
    counts_of "$CRIT" "$ST/c"; counts_of "$HIGH" "$ST/h"
    counts_of "$MED"  "$ST/m"; counts_of "$LOW"  "$ST/l"
    read_counts "$ST/c" CNT_C; NC=$RC_N;  read_counts "$ST/h" CNT_H; NH=$RC_N
    read_counts "$ST/m" CNT_M; NM=$RC_N;  read_counts "$ST/l" CNT_L; NL=$RC_N
    rm -rf "$ST"
    # If grep skipped a file (unreadable, vanished mid-run) the rows no longer line up with FILES, and a silently
    # misaligned count would score the wrong file. Fall back to the per-file path rather than report a guess.
    if [ "$NC" = "${#FILES[@]}" ] && [ "$NH" = "$NC" ] && [ "$NM" = "$NC" ] && [ "$NL" = "$NC" ]; then
      emit
    else
      for f in "${FILES[@]}"; do scan_file "$f"; done
    fi
  fi
else
  echo "  (nothing to scan at '$TARGET')"; exit 0
fi

echo "---"
if [ "$N" -eq 0 ]; then echo "scan: nothing scanned"; exit 0; fi
if [ "$FAIL" -eq 0 ]; then echo "SCAN: all $N file(s) SAFE ✅"; exit 0
else echo "SCAN: review the flagged file(s) above ⚠️  (heuristic — security-education skills can score low by design)"; exit 1; fi
