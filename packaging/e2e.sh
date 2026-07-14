#!/usr/bin/env bash
# End-to-end rehearsal for the installers. Shared by ci.yml (every push) AND release.yml (before it publishes),
# so a release can never ship while the e2e is red — the gap that once let a green release sit on top of a red CI.
# Run from anywhere; it resolves the repo root itself. Uses $RUNNER_TEMP in CI, a mktemp dir locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"

# ---- start.sh: 6 combinations (profile × backend stack) ----
combo() {
  local lbl="$1" inp="$2"; shift 2
  local P="$WORK/proj-$lbl"; rm -rf "$P"; mkdir -p "$P"
  cp start.sh "$P/"; cp -R claude-starter "$P/"
  ( cd "$P" && printf "$inp" | bash start.sh "$@" >/dev/null )
  ( cd "$P" && bash .claude/eval/smoke-test.sh >/dev/null )
  echo "[$lbl] agents=$(ls "$P"/.claude/agents/*.md | wc -l | tr -d ' ') skills=$(ls -d "$P"/.claude/skills/*/ | wc -l | tr -d ' ') smoke=OK"
}
combo frontend          'yes\n'      --frontend
combo mobile            'yes\n'      --mobile
combo backend-dotnet    'yes\nno\n'  --backend --dotnet
combo backend-generic   'yes\n'      --backend --generic
combo fullstack-dotnet  'yes\nno\n'  --fullstack --dotnet
combo fullstack-generic 'yes\n'      --fullstack --generic

# ---- adopt.sh: stack detection (.sln under ./backend) + agent-overlap takeover ----
# A brownfield DevArch project: solution under ./backend (NOT root), Business/Handlers layout, and a
# pre-existing backend-expert.md that collides with the kit's backend-expert-csk.
P="$WORK/adopt-dotnet"; rm -rf "$P"; mkdir -p "$P/backend/Business/Handlers" "$P/.claude/agents"
cp adopt.sh "$P/"; cp -R claude-starter "$P/"; cp VERSION "$P/"
: > "$P/backend/DevArchitecture.sln"
printf -- '---\nname: backend-expert\ndescription: legacy\n---\n' > "$P/.claude/agents/backend-expert.md"
( cd "$P" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
( cd "$P" && bash adopt.sh --yes >/dev/null 2>&1 )
grep -q '^stack=dotnet' "$P/.claude/kit.conf"           || { echo "FAIL: .sln under ./backend not detected as dotnet"; exit 1; }
[ -d "$P/.claude/skills/devarch-module" ]               || { echo "FAIL: devarch-module missing on a dotnet adopt"; exit 1; }
[ ! -f "$P/.claude/agents/backend-expert.md" ]          || { echo "FAIL: overlapping project agent was not taken over"; exit 1; }
[ -f "$P/.claude/superseded/agents/backend-expert.md" ] || { echo "FAIL: taken-over agent's original was not backed up"; exit 1; }
[ -f "$P/.claude/skills/backend-expert-local/SKILL.md" ]|| { echo "FAIL: taken-over agent's domain was not imported to a project skill"; exit 1; }
( cd "$P" && bash .claude/eval/smoke-test.sh >/dev/null )|| { echo "FAIL: the adopted project's own smoke-test did not pass"; exit 1; }
echo "[adopt-dotnet] stack=dotnet · devarch-module kept · overlap imported to skill + backed up · smoke OK"

# A generic (Node) project: no .sln -> generic, devarch-module pruned.
G="$WORK/adopt-generic"; rm -rf "$G"; mkdir -p "$G"
cp adopt.sh "$G/"; cp -R claude-starter "$G/"; cp VERSION "$G/"; printf '{"name":"x"}' > "$G/package.json"
( cd "$G" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
( cd "$G" && bash adopt.sh --yes >/dev/null 2>&1 )
grep -q '^stack=generic' "$G/.claude/kit.conf"          || { echo "FAIL: Node project not recorded as generic"; exit 1; }
[ ! -d "$G/.claude/skills/devarch-module" ]             || { echo "FAIL: devarch-module not pruned on a generic adopt"; exit 1; }
echo "[adopt-generic] stack=generic · devarch-module pruned"

# A REFRESH whose recorded stack is a stale 'generic' but the project is clearly DevArch -> corrected to dotnet.
R="$WORK/adopt-refresh"; rm -rf "$R"; mkdir -p "$R"
cp adopt.sh "$R/"; cp -R claude-starter "$R/"; cp VERSION "$R/"; printf '{"name":"x"}' > "$R/package.json"
( cd "$R" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
( cd "$R" && bash adopt.sh --yes >/dev/null 2>&1 && git add -A && git commit -qm adopt1 )
grep -q '^stack=generic' "$R/.claude/kit.conf"          || { echo "FAIL: first adopt of a Node project should record generic"; exit 1; }
mkdir -p "$R/backend/Business/Handlers"; : > "$R/backend/DevArchitecture.sln"
( cd "$R" && git add -A && git commit -qm 'add devarch structure' )
( cd "$R" && bash adopt.sh --yes >/dev/null 2>&1 )
grep -q '^stack=dotnet' "$R/.claude/kit.conf"           || { echo "FAIL: refresh did not correct a stale generic stack to dotnet"; exit 1; }
[ -d "$R/.claude/skills/devarch-module" ]               || { echo "FAIL: devarch-module not restored after the stack correction"; exit 1; }
echo "[adopt-refresh] stale generic corrected -> dotnet · devarch-module restored"

# Non-interactive SELF-HEAL — the /update-csk path. An UPDATE of an existing install must fix a stale settings.json
# off a TTY with NO flag and NO manual edit (this is what /update-csk drives), and the settings refresh must work
# even with NO jq and NO python3 (typical Windows Git-Bash). A FIRST adopt (brownfield) still needs --yes. Every run
# uses a closed stdin so the test can never hang.
mk_stale_install(){                       # $1 = dir : a healthy 1.4.x install whose settings.json is STALE
  local d="$1"; rm -rf "$d"; mkdir -p "$d/.claude"
  cp adopt.sh "$d/"; cp -R claude-starter "$d/"; cp VERSION "$d/"
  cp -R "$d/claude-starter/." "$d/.claude/" 2>/dev/null; cp VERSION "$d/.claude/VERSION"
  printf 'profile=fullstack\nstack=generic\ninstaller=start.sh\n' > "$d/.claude/kit.conf"
  printf '%s\n' '{ "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type":"command","command":"bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/context-usage.sh\" 2>/dev/null || true","timeout":10 } ] } ] } }' > "$d/.claude/settings.json"
  printf '# project rules\n@.claude/DISCIPLINE.md\n' > "$d/CLAUDE.md"
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
}
# (A) update · non-interactive · NO --yes -> APPLIES (self-heal): stale hook refreshed, SessionStart wired, CLAUDE.md kept
U="$WORK/selfheal"; mk_stale_install "$U"
( cd "$U" && bash adopt.sh --here </dev/null >/dev/null 2>&1 )
grep -q 'SessionStart' "$U/.claude/settings.json"       || { echo "FAIL: non-interactive update did not self-heal (SessionStart missing)"; exit 1; }
grep -q '"timeout": 30' "$U/.claude/settings.json"      || { echo "FAIL: non-interactive update did not refresh the stale timeout"; exit 1; }
head -1 "$U/CLAUDE.md" | grep -q 'project rules'        || { echo "FAIL: update clobbered the project's own CLAUDE.md"; exit 1; }
# (B) SAME, but with NO jq and NO python3 on PATH (the real Windows Git-Bash case) -> kit-only settings safely
# REPLACED + backup kept. The strip needs a symlink farm; Git-Bash on Windows can't make one, so there we skip this
# sub-test (with a note) and rely on (A) + the portable-bash fallback proven on the POSIX runners.
# Probe ONCE whether this filesystem makes real symlinks. Git-Bash on Windows copies instead — a copied .exe is
# DLL-fragile and can't run, so a mirror-farm PATH there is both broken and slow (thousands of copies). Only build
# the jq-less strip where symlinks are real; elsewhere skip this leg (the no-jq code is proven on the POSIX runners).
SYMPROBE="$WORK/.symprobe"; rm -f "$SYMPROBE"; ln -s "$(command -v bash 2>/dev/null)" "$SYMPROBE" 2>/dev/null
if [ -L "$SYMPROBE" ]; then
  N="$WORK/selfheal-nojq"; mk_stale_install "$N"
  NODEPS="$WORK/nodeps-bin"; rm -rf "$NODEPS"; mkdir -p "$NODEPS"    # mirror every tool on PATH, then drop jq + python*
  oldIFS="$IFS"; IFS=:
  for d in $PATH; do [ -d "$d" ] || continue
    for f in "$d"/*; do b="$(basename "$f" 2>/dev/null)"; [ -n "$b" ] && [ -x "$f" ] && [ ! -e "$NODEPS/$b" ] && ln -s "$f" "$NODEPS/$b" 2>/dev/null; done
  done; IFS="$oldIFS"
  rm -f "$NODEPS"/jq "$NODEPS"/jq.* "$NODEPS"/python "$NODEPS"/python3 "$NODEPS"/python.* "$NODEPS"/python3.* 2>/dev/null
  if ! PATH="$NODEPS" bash -c 'command -v jq >/dev/null 2>&1' && ! PATH="$NODEPS" bash -c 'command -v python3 >/dev/null 2>&1'; then
    ( cd "$N" && PATH="$NODEPS" bash adopt.sh --here </dev/null >/dev/null 2>&1 )
    grep -q 'SessionStart' "$N/.claude/settings.json"     || { echo "FAIL: no-jq/python update did not self-heal the settings"; exit 1; }
    grep -q '"timeout": 30' "$N/.claude/settings.json"    || { echo "FAIL: no-jq/python update did not refresh the timeout"; exit 1; }
    ls "$N"/.claude/settings.json.bak-* >/dev/null 2>&1   || { echo "FAIL: no-jq/python replace did not keep a backup"; exit 1; }
    head -1 "$N/CLAUDE.md" | grep -q 'project rules'      || { echo "FAIL: no-jq/python update clobbered CLAUDE.md"; exit 1; }
    NOJQ_NOTE="with + WITHOUT jq/python"
  else NOJQ_NOTE="with jq/python (couldn't build a jq-less PATH here)"; fi
else
  NOJQ_NOTE="with jq/python (no-jq PATH-strip needs POSIX symlinks — that leg runs on Linux/macOS)"
fi
rm -f "$SYMPROBE"
# (C) FIRST adopt (no kit present) · non-interactive · NO --yes -> declines (a brownfield change still needs consent)
F="$WORK/firstadopt"; rm -rf "$F"; mkdir -p "$F"
cp adopt.sh "$F/"; cp -R claude-starter "$F/"; cp VERSION "$F/"; printf '{"name":"x"}' > "$F/package.json"
( cd "$F" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
( cd "$F" && bash adopt.sh --here </dev/null >/dev/null 2>&1 )
[ ! -f "$F/.claude/DISCIPLINE.md" ]                     || { echo "FAIL: first adopt must NOT apply non-interactively without --yes"; exit 1; }
echo "[adopt-selfheal] update self-heals off a TTY ($NOJQ_NOTE) · backup kept · CLAUDE.md preserved · first adopt still needs --yes"

echo "e2e: all installer rehearsals passed"
