#!/usr/bin/env bash
# Claude Code PreToolUse (Bash) guard: §4.5 destruktif islemleri ARAC SEVIYESINDE bloklar.
# PreToolUse, --dangerously-skip-permissions altinda bile calisir; exit 2 = blok (stderr Claude'a doner).
# stdin JSON: {"tool_name":"Bash","tool_input":{"command":"..."}}
set -uo pipefail
INPUT="$(cat)"

# Komutu güvenle çıkar (jq > python3 > ham metin fallback)
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
else
  CMD="$INPUT"
fi
[ -z "$CMD" ] && exit 0

block(){
  echo "GUARD (§$2): '$1' ARAÇ SEVİYESİNDE durduruldu." >&2
  echo "Bu destrüktif işlem yalnız kullanıcı AÇIKÇA isterse yapılır. Onaylıysa komutu terminalde elle çalıştır." >&2
  exit 2
}

echo "$CMD" | grep -qE 'git +reset +.*--hard'              && block "git reset --hard" "4.5"
echo "$CMD" | grep -qE 'git +push +.*(--force([^-]|$)|-f([^a-z]|$)|\+[A-Za-z])' && block "git push --force" "4.5"
echo "$CMD" | grep -qE 'git +clean +-[A-Za-z]*f'           && block "git clean -f" "4.5"
echo "$CMD" | grep -qE -- '--no-verify'                    && block "hook atlama (--no-verify)" "4.5"
echo "$CMD" | grep -qE 'git +rebase'                       && block "git rebase" "4.5"
echo "$CMD" | grep -qE 'git +(filter-branch|filter-repo)'  && block "git filter-branch" "4.5"
echo "$CMD" | grep -qE 'git +commit +.*--amend'            && block "git commit --amend" "4.5"
echo "$CMD" | grep -qE 'rm +-[A-Za-z]*r[A-Za-z]* +.*(/|\*|~)' && block "yıkıcı rm -rf" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])(mkfs|dd +if=)'       && block "disk düzeyi yıkıcı komut" "4.5"

exit 0
