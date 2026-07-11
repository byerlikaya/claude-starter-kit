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
( cd "$P" && printf 'yes\n' | bash adopt.sh >/dev/null 2>&1 )
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
( cd "$G" && printf 'yes\n' | bash adopt.sh >/dev/null 2>&1 )
grep -q '^stack=generic' "$G/.claude/kit.conf"          || { echo "FAIL: Node project not recorded as generic"; exit 1; }
[ ! -d "$G/.claude/skills/devarch-module" ]             || { echo "FAIL: devarch-module not pruned on a generic adopt"; exit 1; }
echo "[adopt-generic] stack=generic · devarch-module pruned"

# A REFRESH whose recorded stack is a stale 'generic' but the project is clearly DevArch -> corrected to dotnet.
R="$WORK/adopt-refresh"; rm -rf "$R"; mkdir -p "$R"
cp adopt.sh "$R/"; cp -R claude-starter "$R/"; cp VERSION "$R/"; printf '{"name":"x"}' > "$R/package.json"
( cd "$R" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
( cd "$R" && printf 'yes\n' | bash adopt.sh >/dev/null 2>&1 && git add -A && git commit -qm adopt1 )
grep -q '^stack=generic' "$R/.claude/kit.conf"          || { echo "FAIL: first adopt of a Node project should record generic"; exit 1; }
mkdir -p "$R/backend/Business/Handlers"; : > "$R/backend/DevArchitecture.sln"
( cd "$R" && git add -A && git commit -qm 'add devarch structure' )
( cd "$R" && printf 'yes\n' | bash adopt.sh >/dev/null 2>&1 )
grep -q '^stack=dotnet' "$R/.claude/kit.conf"           || { echo "FAIL: refresh did not correct a stale generic stack to dotnet"; exit 1; }
[ -d "$R/.claude/skills/devarch-module" ]               || { echo "FAIL: devarch-module not restored after the stack correction"; exit 1; }
echo "[adopt-refresh] stale generic corrected -> dotnet · devarch-module restored"

echo "e2e: all installer rehearsals passed"
