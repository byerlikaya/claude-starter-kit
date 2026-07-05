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

# --- §4.4 commit/push onay kapisi (auto/bypass izin modunda DA tutar) ---
# Neden hook: permissions.ask bypass modda ATLANIR; PreToolUse "deny" ise HER modda tutar. Hook mod-kordur
# (permission_mode gormez), o yuzden git commit/push VARSAYILAN kapali; yalniz kullanici oturum baslamadan
# CLAUDE_GIT_OK=1 set ederse acilir. Model bunu hook ortamina yazamaz (hook ayri surecte; Bash-tool env'i
# turler-arasi kalici degil). Amac degismez: commit MESAJINI once kullaniciya sun, ACIK onay al.
is_git_write() {
  printf '%s' "$1" | grep -qiE '(^|[;&|(]|[[:space:]])git[[:space:]]+([^;&|[:space:]]+[[:space:]]+)*(commit|push)([[:space:]]|$|;|&|\|)'
}
if is_git_write "$CMD"; then
  if printf '%s' "$CMD" | grep -q 'CLAUDE_GIT_OK'; then
    echo "GUARD (§4.4): onay anahtarini (CLAUDE_GIT_OK) komut icinde set etme girisimi reddedildi." >&2
    echo "Anahtar yalniz kullanici tarafindan, oturum baslamadan once set edilir." >&2
    exit 2
  fi
  case "${CLAUDE_GIT_OK:-}" in
    1|yes|true|on|YES|TRUE|ON) : ;;   # kullanici bu oturumda ACIKCA izin verdi -> gecir
    *)
      echo "GUARD (§4.4): 'git commit/push' ARAC SEVIYESINDE onaya bagli (auto/bypass modda da)." >&2
      echo "Once commit MESAJINI kullaniciya sun ve ACIK onay al. Onaylandiginda:" >&2
      echo "  (a) kullanici komutu kendi terminalinde calistirir, VEYA" >&2
      echo "  (b) oturumu 'CLAUDE_GIT_OK=1' ile baslatip Claude'a birakir (normal modda permissions.ask yine sorar)." >&2
      exit 2 ;;
  esac
fi

exit 0
