#!/usr/bin/env bash
# Install-time skill/agent security scanner — zero-dep bash + regex. Scans a directory or file (meant for a
# project's EXISTING third-party .claude skills/agents that adopt.sh will coexist with) for supply-chain red flags
# and scores each file:  score = 100 − CRIT×20 − HIGH×10 − MED×3 − LOW×1  (floored at 0).
#   SAFE  ≥ 90   ·   REVIEW  70–89   ·   DANGER  < 70
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
HIGH='ignore[[:space:]]+(all[[:space:]]+)?(the[[:space:]]+)?(previous|prior|above)[[:space:]]+(instruction|prompt)|disregard[[:space:]]+(the[[:space:]]+|all[[:space:]]+)?(previous|above|prior)|ignore[[:space:]]+your[[:space:]]+(system[[:space:]]+)?(prompt|instruction)|(cat|less|more|tail|head|base64|xxd|od|strings|curl|wget|scp|cp|rsync)[^|]*(~/\.ssh|id_rsa|/etc/(passwd|shadow)|\.aws/credentials|\.netrc|\.git-credentials)|base64[[:space:]]+-[A-Za-z]*d[^|]*\|'
# MED: named cloud/CI secret env vars, process.env secret access, chmod 777, code eval/exec.
MED='(GITHUB_TOKEN|AWS_SECRET|AWS_ACCESS_KEY|NPM_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|SLACK_TOKEN)|process\.env\.[A-Za-z_]*(TOKEN|SECRET|KEY|PASSWORD)|chmod[[:space:]]+(-R[[:space:]]+)?0?777|[^a-zA-Z](eval|exec)[[:space:]]*\('
# LOW: an outbound URL fetch or a raw socket — common in benign deploy/example prose, hence low weight.
LOW='(^|[^a-zA-Z])(curl|wget)[[:space:]]+[^|]*https?://|/dev/tcp/|[^a-zA-Z]nc[[:space:]]+-[A-Za-z]*e'

FAIL=0; N=0
verdict(){ if [ "$1" -ge 90 ]; then echo SAFE; elif [ "$1" -ge 70 ]; then echo REVIEW; else echo DANGER; fi; }

scan_file(){
  local f="$1"
  local c h m l
  # grep -c prints the count (0 on no match) and exits 1 on no match; that non-zero exit is fine here (no set -e),
  # and a `|| echo 0` would DOUBLE the printed 0 and break the arithmetic — so don't add one.
  c=$(grep -icE "$CRIT" "$f" 2>/dev/null); h=$(grep -icE "$HIGH" "$f" 2>/dev/null)
  m=$(grep -icE "$MED"  "$f" 2>/dev/null); l=$(grep -icE "$LOW"  "$f" 2>/dev/null)
  c=${c:-0}; h=${h:-0}; m=${m:-0}; l=${l:-0}
  local score=$((100 - c*20 - h*10 - m*3 - l*1)); [ "$score" -lt 0 ] && score=0
  local v; v="$(verdict "$score")"
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
  while IFS= read -r f; do
    case "$f" in *-csk.md) continue ;; esac
    scan_file "$f"
  done < <(find "$TARGET" \( -name 'SKILL.md' -o -name '*.md' \) -path '*/skills/*' -o -path '*/agents/*' -name '*.md' 2>/dev/null | sort -u)
else
  echo "  (nothing to scan at '$TARGET')"; exit 0
fi

echo "---"
if [ "$N" -eq 0 ]; then echo "scan: nothing scanned"; exit 0; fi
if [ "$FAIL" -eq 0 ]; then echo "SCAN: all $N file(s) SAFE ✅"; exit 0
else echo "SCAN: review the flagged file(s) above ⚠️  (heuristic — security-education skills can score low by design)"; exit 1; fi
