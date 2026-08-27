#!/usr/bin/env bash
# End-to-end rehearsal for the installers. Shared by ci.yml (every push) AND release.yml (before it publishes),
# so a release can never ship while the e2e is red — the gap that once let a green release sit on top of a red CI.
# Run from anywhere; it resolves the repo root itself. Uses $RUNNER_TEMP in CI, a mktemp dir locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"

# ---- start.sh: 2 combinations (backend pattern) ----
# 2.0 removed the profile split, and with it four of the six combinations: they differed only in which
# components were deleted after an identical install. The backend pattern is the one axis that still changes
# what lands on disk (devarch-module + the backend agent variant), so it is the one axis still rehearsed.
# The legacy-flag case is here rather than in the smoke-test because only an end-to-end run proves an old
# command line still installs — the thing that would break a CI step someone wrote a year ago.
combo() {
  local lbl="$1" inp="$2" exp_ag="$3" exp_sk="$4"; shift 4
  local P="$WORK/proj-$lbl"; rm -rf "$P"; mkdir -p "$P"
  cp start.sh "$P/"; cp -R claude-starter "$P/"
  ( cd "$P" && printf "$inp" | bash start.sh "$@" >/dev/null )
  # scope=install: the gate UNIT cases drive hook binaries the installer copies UNCHANGED, so running all of
  # them in every combination re-checks identical bytes. Install scope keeps the install-dependent assertions
  # plus a canary that proves the installed hook actually executes; the exhaustive cases run once, in CI's
  # standalone full-scope smoke-test step.
  ( cd "$P" && CSK_SMOKE_SCOPE=install bash .claude/eval/smoke-test.sh >/dev/null )
  # The install manifest is what separates kit-owned from project-owned downstream (doctor readiness, trust gate).
  [ -s "$P/.claude/kit-manifest.txt" ] || { echo "FAIL [$lbl]: .claude/kit-manifest.txt missing or empty"; exit 1; }
  grep -q '^skills/handoff$' "$P/.claude/kit-manifest.txt" || { echo "FAIL [$lbl]: manifest does not list the shipped skills"; exit 1; }
  # Component count is an ASSERTION now, not a printed number: the whole point of 2.0 is that the set no longer
  # varies, and a silent drop would otherwise read as a normal install.
  local ag sk; ag=$(ls "$P"/.claude/agents/*.md | wc -l | tr -d ' '); sk=$(ls -d "$P"/.claude/skills/*/ | wc -l | tr -d ' ')
  [ "$ag" = "$exp_ag" ] || { echo "FAIL [$lbl]: expected $exp_ag agents, got $ag"; exit 1; }
  [ "$sk" = "$exp_sk" ] || { echo "FAIL [$lbl]: expected $exp_sk skills, got $sk"; exit 1; }
  grep -q '^profile=' "$P/.claude/kit.conf" && { echo "FAIL [$lbl]: kit.conf still records a profile"; exit 1; }
  echo "[$lbl] agents=$ag skills=$sk smoke=OK manifest=$(wc -l < "$P/.claude/kit-manifest.txt" | tr -d ' ')"
}
# The expected counts come from the PAYLOAD, not from a number typed here. Written by hand they drift with the
# first component added — the network diagram's subtitle did exactly that, announcing 11 agents and 36 skills
# over a picture it had drawn with 12 and 38 — and the failure reads like a broken install rather than a stale
# constant. `--generic` prunes exactly one skill (devarch-module), so that arm is the payload count minus one;
# the assertion that matters is still "the set does not vary silently", and it survives intact.
KIT_AG=$(ls "$ROOT"/claude-starter/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
KIT_SK=$(ls -d "$ROOT"/claude-starter/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
[ "${KIT_AG:-0}" -gt 0 ] && [ "${KIT_SK:-0}" -gt 0 ] || { echo "FAIL: cannot count the payload at $ROOT/claude-starter"; exit 1; }
echo "payload: $KIT_AG agents, $KIT_SK skills (expectations derived, not typed)"
combo dotnet        'yes\nno\n'  "$KIT_AG" "$KIT_SK"          --dotnet
combo generic       'yes\n'      "$KIT_AG" "$((KIT_SK - 1))"  --generic
# An old command line must still install, and must install the FULL set — the flag is accepted, not obeyed.
combo legacy-flags  'yes\n'      "$KIT_AG" "$((KIT_SK - 1))"  --frontend --generic
grep -q 'no effect' "$WORK/proj-legacy-flags/.claude/kit.conf" && { echo "FAIL: notice leaked into kit.conf"; exit 1; }
[ -f "$WORK/proj-legacy-flags/.claude/agents/backend-expert-csk.md" ] || { echo "FAIL: --frontend still pruned the backend agent"; exit 1; }
echo "[legacy-flags] --frontend accepted and ignored; full set installed"

# Every adopt assertion below used to depend on a run sent to /dev/null, then print one line and exit. A red CI
# therefore arrived with no evidence at all: the recorded stack, what the detector saw, and whether adopt even
# finished were all unknowable from the log, so a real defect and a flake looked identical. `run_adopt` keeps the
# output and the exit code; `evidence` prints the state the assertion actually ran against. Nothing is retried —
# a flake that is hidden is worse than one that is loud, and this is here to make the next failure readable.
ADOPT_OUT=""; ADOPT_RC=0
run_adopt() {   # $1 = project dir, rest = adopt.sh args
  local d="$1"; shift
  ADOPT_RC=0
  ADOPT_OUT="$( cd "$d" && bash adopt.sh "$@" 2>&1 )" || ADOPT_RC=$?
  return 0
}
evidence() {    # $1 = label, $2 = project dir
  echo "---- evidence · $1 (adopt exit=$ADOPT_RC) ----"
  echo "  kit.conf:";        sed 's/^/    /' "$2/.claude/kit.conf" 2>/dev/null || echo "    (absent)"
  echo "  components:       agents=$(ls "$2"/.claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ') skills=$(ls -d "$2"/.claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
  echo "  devarch-module:   $([ -d "$2/.claude/skills/devarch-module" ] && echo present || echo absent)"
  # The two signals the stack detector reads, evaluated here the same way adopt.sh evaluates them.
  echo "  .sln/.csproj:     $( (cd "$2" && find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) 2>/dev/null | head -3 | tr '\n' ' ') )"
  echo "  Business/Handlers: $( (cd "$2" && find . -maxdepth 4 -type d -path '*/Business/Handlers' 2>/dev/null | head -1) )"
  echo "  branch:           $(git -C "$2" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "  adopt output (tail):"; printf '%s\n' "$ADOPT_OUT" | tail -45 | sed 's/^/    /'
  echo "---- end evidence ----"
}
die() {         # $1 = message, $2 = label, $3 = project dir
  echo "FAIL: $1"; evidence "$2" "$3"; exit 1
}

# ---- adopt.sh: stack detection (.sln under ./backend) + agent-overlap takeover ----
# A brownfield DevArch project: solution under ./backend (NOT root), Business/Handlers layout, and a
# pre-existing backend-expert.md that collides with the kit's backend-expert-csk.
P="$WORK/adopt-dotnet"; rm -rf "$P"; mkdir -p "$P/backend/Business/Handlers" "$P/.claude/agents"
cp adopt.sh "$P/"; cp -R claude-starter "$P/"; cp VERSION "$P/"
: > "$P/backend/DevArchitecture.sln"
printf -- '---\nname: backend-expert\ndescription: legacy\n---\n' > "$P/.claude/agents/backend-expert.md"
( cd "$P" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
run_adopt "$P" --yes
grep -q '^stack=dotnet' "$P/.claude/kit.conf"           || die ".sln under ./backend not detected as dotnet" adopt-dotnet "$P"
[ -d "$P/.claude/skills/devarch-module" ]               || die "devarch-module missing on a dotnet adopt" adopt-dotnet "$P"
[ ! -f "$P/.claude/agents/backend-expert.md" ]          || die "overlapping project agent was not taken over" adopt-dotnet "$P"
[ -f "$P/.claude/superseded/agents/backend-expert.md" ] || die "taken-over agent's original was not backed up" adopt-dotnet "$P"
[ -f "$P/.claude/skills/backend-expert-local/SKILL.md" ]|| die "taken-over agent's domain was not imported to a project skill" adopt-dotnet "$P"
# The manifest lists what the KIT ships, so the skill this adopt imported from the project must NOT appear in it
# — that is exactly the distinction the readiness check and the trust gate are built on.
grep -q '^skills/devarch-module$' "$P/.claude/kit-manifest.txt"     || { echo "FAIL: manifest missing a kit skill"; exit 1; }
grep -q '^skills/backend-expert-local$' "$P/.claude/kit-manifest.txt" && { echo "FAIL: manifest claims a project-imported skill as kit-owned"; exit 1; }
# Captured, not piped: `grep -q` closes the pipe on its first match, doctor takes a SIGPIPE, and `pipefail`
# would then report a passing assertion as a failure.
DT0=$SECONDS
DOUT="$( cd "$P" && bash .claude/eval/doctor.sh 2>&1 || true )"
DEL=$((SECONDS - DT0))
case "$DOUT" in *"project-specific skill(s)"*) ;; *) echo "FAIL: doctor readiness did not detect the project's own skill"; exit 1 ;; esac
# COST GATE, and it belongs here rather than in the smoke-test because this job also runs on windows-latest —
# the only place in CI where a process spawn costs what it costs a real user of Git Bash (62-135 ms against
# ~1.7ms on the POSIX runners). Doctor's agent-reference check used to run a `grep|cut|tr|sed` for every
# (agent x scanned doc) pair, ~250 spawns; on Windows that stopped dead mid-run and a user reported doctor
# itself as hung. Correctness assertions cannot see this — doctor printed the right answers, eventually.
# The bound is deliberately loose: a healthy run is ~2-4s on a Windows runner, a spawn-per-pair regression is
# 10s+, so 20s separates them with room for a slow shared runner and no room for the bug coming back.
#
# Be clear about what this does NOT do: on the POSIX runners both the fixed and the broken version finish in
# well under a second (measured: 0s either way on an M-series Mac), so this assertion cannot fire there. It is a
# Windows gate that happens to also run elsewhere, not a portable one — a wall-clock bound low enough to catch
# the regression on macOS would sit below a healthy Windows run and fail the job for being slow. The portable
# half of the protection is the route-hint gate in smoke-test.sh §7y, where the old code took 34s on macOS too.
[ "$DEL" -le 20 ] || { echo "FAIL: doctor.sh took ${DEL}s (>20s) — a per-pair fork loop is back; on Git Bash this reads as a hang"; exit 1; }
( cd "$P" && CSK_SMOKE_SCOPE=install bash .claude/eval/smoke-test.sh >/dev/null )|| { echo "FAIL: the adopted project's own smoke-test did not pass"; exit 1; }
# doctor's elapsed time is printed on SUCCESS too, not only in the failure message. The bound above is loose by
# design, so a silent pass hides the trend that matters: 2s creeping to 8s is the regression arriving, and it
# reads as "fine" until the day it trips. The number in the log is what makes that visible in hindsight.
echo "[adopt-dotnet] stack=dotnet · devarch-module kept · overlap imported to skill + backed up · smoke OK · doctor ${DEL}s"

# A generic (Node) project: no .sln -> generic, devarch-module pruned.
G="$WORK/adopt-generic"; rm -rf "$G"; mkdir -p "$G"
cp adopt.sh "$G/"; cp -R claude-starter "$G/"; cp VERSION "$G/"; printf '{"name":"x"}' > "$G/package.json"
( cd "$G" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
run_adopt "$G" --yes
grep -q '^stack=generic' "$G/.claude/kit.conf"          || die "Node project not recorded as generic" adopt-generic "$G"
[ ! -d "$G/.claude/skills/devarch-module" ]             || die "devarch-module not pruned on a generic adopt" adopt-generic "$G"
echo "[adopt-generic] stack=generic · devarch-module pruned"

# A REFRESH whose recorded stack is a stale 'generic' on a clearly-DevArch project. The correction is OFFERED,
# never applied behind the user's back — so this asserts BOTH halves, and the first half is the one that was
# missing. The old test ran `--yes` (no tty) and required stack=dotnet, i.e. it demanded that a recorded choice
# be overruled where nobody could be asked. It passed for five releases while a user who installed --generic on
# a .NET project that is NOT DevArchitecture got devarch-module and the .NET agent pushed onto them.
R="$WORK/adopt-refresh"; rm -rf "$R"; mkdir -p "$R"
cp adopt.sh "$R/"; cp -R claude-starter "$R/"; cp VERSION "$R/"; printf '{"name":"x"}' > "$R/package.json"
( cd "$R" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
run_adopt "$R" --yes
( cd "$R" && git add -A && git commit -qm adopt1 ) >/dev/null 2>&1
grep -q '^stack=generic' "$R/.claude/kit.conf"          || die "first adopt of a Node project should record generic" adopt-refresh/1st "$R"
mkdir -p "$R/backend/Business/Handlers"; : > "$R/backend/DevArchitecture.sln"
( cd "$R" && git add -A && git commit -qm 'add devarch structure' )
# (a) nobody to ask -> the recorded choice STANDS, and the mismatch is reported rather than acted on.
run_adopt "$R" --yes
grep -q '^stack=generic' "$R/.claude/kit.conf"          || die "a non-interactive refresh silently overruled the recorded stack" adopt-refresh/keep "$R"
[ ! -d "$R/.claude/skills/devarch-module" ]             || die "devarch-module installed without anyone approving the stack change" adopt-refresh/keep "$R"
grep -qi 'stack-agnostic' "$R/.claude/agents/backend-expert-csk.md" || die "backend agent flipped to .NET without approval" adopt-refresh/keep "$R"
# (b) asked for deliberately -> corrected, and devarch-module comes back with it.
CSK_CORRECT_STACK=1 run_adopt "$R" --yes
grep -q '^stack=dotnet' "$R/.claude/kit.conf"           || die "CSK_CORRECT_STACK=1 did not correct a stale generic stack" adopt-refresh/fix "$R"
[ -d "$R/.claude/skills/devarch-module" ]               || die "devarch-module not restored after the stack correction" adopt-refresh/fix "$R"
echo "[adopt-refresh] recorded generic KEPT without a person · CSK_CORRECT_STACK=1 corrects it -> dotnet"

# ---- adopt.sh: pre-2.0 profile MIGRATION ----
# A project installed by 1.x with `--backend` is missing the frontend agent and four UI skills. 2.0 completes
# it. Built by hand rather than by running the old start.sh, because the old installer no longer exists — the
# fixture IS the contract: kit.conf carrying profile=, and the exact set that profile pruned.
M="$WORK/adopt-migrate"; rm -rf "$M"; mkdir -p "$M/.claude/agents" "$M/.claude/skills"
cp adopt.sh "$M/"; cp -R claude-starter "$M/"; cp VERSION "$M/"
cp claude-starter/agents/*.md "$M/.claude/agents/"; rm -f "$M/.claude/agents/frontend-expert-csk.md"
cp -R claude-starter/skills/. "$M/.claude/skills/"
for s in frontend frontend-rn-expo frontend-design a11y; do rm -rf "$M/.claude/skills/$s"; done
printf 'profile=backend\nstack=dotnet\ninstaller=start.sh\n' > "$M/.claude/kit.conf"
printf '1.10.1' > "$M/.claude/VERSION"
( cd "$M" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
MOUT="$( cd "$M" && bash adopt.sh --yes 2>&1 || true )"
case "$MOUT" in *"profile pruning was removed"*) ;; *) echo "FAIL: migration was silent — the user is never told the shape changed"; exit 1 ;; esac
[ -f "$M/.claude/agents/frontend-expert-csk.md" ] || { echo "FAIL: migration did not restore the pruned agent"; exit 1; }
for s in frontend frontend-rn-expo frontend-design a11y; do
  [ -d "$M/.claude/skills/$s" ] || { echo "FAIL: migration did not restore skills/$s"; exit 1; }
done
grep -q '^profile=' "$M/.claude/kit.conf" && { echo "FAIL: migration left the profile= key behind — the notice would repeat forever"; exit 1; }
grep -q '^stack=dotnet' "$M/.claude/kit.conf" || { echo "FAIL: migration lost the recorded backend pattern"; exit 1; }
# Second run must be QUIET: the notice is retired by removing the key, not by a flag.
MOUT2="$( cd "$M" && bash adopt.sh --yes 2>&1 || true )"
case "$MOUT2" in *"profile pruning was removed"*) echo "FAIL: migration notice repeats on every refresh"; exit 1 ;; esac
echo "[adopt-migrate] pre-2.0 backend install completed (+1 agent, +4 skills) · pattern kept · notice retired"

# ---- Channel parity: start.sh and the plugin edition must ship the SAME components ----
# The two channels drifting is not hypothetical — it is what shipped a sleeping agent and broke the route-hint
# cases on pruned profiles. With the split gone they are identical by construction, so assert it.
if [ -d plugin/agents ] && [ -d plugin/skills ]; then
  PA_="$WORK/proj-dotnet/.claude"
  diff <(ls "$PA_"/agents/*.md | xargs -n1 basename | sort) <(ls plugin/agents/*.md | xargs -n1 basename | sort) >/dev/null \
    || { echo "FAIL: installed agents differ from the plugin edition"; exit 1; }
  diff <(ls -d "$PA_"/skills/*/ | xargs -n1 basename | sort) <(ls -d plugin/skills/*/ | xargs -n1 basename | sort) >/dev/null \
    || { echo "FAIL: installed skills differ from the plugin edition"; exit 1; }
  echo "[channel-parity] a --dotnet install and the plugin edition ship the same agents and skills"
fi

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
# The refreshed value is read from the kit, not pinned to a literal. A hard-coded number turns every future
# timeout retune into a red e2e that blames the merge — which is exactly what happened when the hook timeouts
# moved to 60: the merge was correct and the assertion was stale. The fixture above deliberately carries 10, and
# the guard below keeps the test honest by refusing to run if the kit ever ships that same value.
# Layout-independent: find the line naming the script, then take the FIRST "timeout" after it. A fixed `grep -A1`
# was tied to the shell-form shape and went blank the moment hooks moved to exec form, where the path sits inside
# an `args` array and the timeout is several lines further down. The guard below caught that rather than letting
# the assertions quietly pass on an empty value — which is the whole reason it is there.
KIT_TO="$(awk '/context-usage\.sh/{f=1} f && /"timeout"/{gsub(/[^0-9]/,""); print; exit}' claude-starter/settings.json)"
[ -n "$KIT_TO" ] && [ "$KIT_TO" != 10 ] || { echo "FAIL: could not read the kit's UserPromptSubmit timeout (got '${KIT_TO:-}') — the stale-vs-refreshed assertions below would prove nothing"; exit 1; }
# (A) update · non-interactive · NO --yes -> APPLIES (self-heal): stale hook refreshed, SessionStart wired, CLAUDE.md kept
U="$WORK/selfheal"; mk_stale_install "$U"
( cd "$U" && bash adopt.sh --here </dev/null >/dev/null 2>&1 )
grep -q 'SessionStart' "$U/.claude/settings.json"       || { echo "FAIL: non-interactive update did not self-heal (SessionStart missing)"; exit 1; }
grep -q "\"timeout\": $KIT_TO" "$U/.claude/settings.json"      || { echo "FAIL: non-interactive update did not refresh the stale timeout"; exit 1; }
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
    grep -q "\"timeout\": $KIT_TO" "$N/.claude/settings.json"    || { echo "FAIL: no-jq/python update did not refresh the timeout"; exit 1; }
    ls "$N"/.claude/settings.json.bak-* >/dev/null 2>&1   || { echo "FAIL: no-jq/python replace did not keep a backup"; exit 1; }
    head -1 "$N/CLAUDE.md" | grep -q 'project rules'      || { echo "FAIL: no-jq/python update clobbered CLAUDE.md"; exit 1; }
    NOJQ_NOTE="with + WITHOUT jq/python"
    # (D) Python exposed ONLY as `py` (the Windows Python Launcher) — no jq, no python3/python. The merge must run
    #     via py and heal, NOT fall through to the .kit reference (the exact case a Git-Bash Windows user hit).
    REALPY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
    if [ -n "$REALPY" ]; then
      P="$WORK/selfheal-py"; mk_stale_install "$P"
      printf '#!/bin/sh\nexec "%s" "$@"\n' "$REALPY" > "$NODEPS/py"; chmod +x "$NODEPS/py"
      ( cd "$P" && PATH="$NODEPS" bash adopt.sh --here </dev/null >/dev/null 2>&1 )
      grep -q 'SessionStart' "$P/.claude/settings.json"   || { echo "FAIL: py-launcher update did not self-heal (SessionStart)"; exit 1; }
      grep -q "\"timeout\": $KIT_TO" "$P/.claude/settings.json"  || { echo "FAIL: py-launcher update did not refresh the timeout"; exit 1; }
      [ ! -e "$P/.claude/settings.json.kit" ]             || { echo "FAIL: py present but the merge fell back to .kit"; exit 1; }
      rm -f "$NODEPS/py"
    fi
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

# (D) TTY + --yes must NOT hang — the /update-csk regression. adopt.sh once tested `-t 0` BEFORE --yes, so an
# --yes run that inherited a TTY (Claude Code drives commands under a pty on Windows) blocked on a prompt. Every
# test above misses it by construction — they close stdin, so `-t 0` is false. Here we allocate a REAL pty and
# assert the refresh completes under --yes. Needs a pty-capable `script`; skipped where none exists (Git-Bash).
T="$WORK/pty-yes"; rm -rf "$T"; mkdir -p "$T"
cp start.sh adopt.sh VERSION "$T/"; cp -R claude-starter "$T/"
# empty baseline commit BEFORE install (no hooksPath yet), then install; the refresh below STAGES only (like
# /update-csk) so no pre-commit trace hook runs — the point here is the prompt behaviour, not a commit.
( cd "$T" && git init -q && git config user.email t@t.t && git config user.name t && git commit -q --allow-empty -m base \
    && printf 'yes\nno\n' | bash start.sh --dotnet >/dev/null 2>&1 )
cp adopt.sh "$T/adopt.sh"; cp -R claude-starter "$T/claude-starter"   # a refresh reads the payload beside adopt.sh
if script --version >/dev/null 2>&1; then PTY_FLAVOR=linux            # util-linux: script -q -e -c CMD FILE
elif command -v script >/dev/null 2>&1;  then PTY_FLAVOR=bsd          # BSD/macOS: script -q FILE CMD…
else PTY_FLAVOR=none; fi
if [ "$PTY_FLAVOR" = none ]; then
  echo "[adopt-pty-yes] SKIPPED (no pty-capable 'script' here — e.g. stock Windows Git-Bash)"
else
  ( cd "$T"
    if [ "$PTY_FLAVOR" = linux ]; then script -q -e -c "bash adopt.sh --here --yes" /dev/null >pty.log 2>&1
    else script -q /dev/null bash adopt.sh --here --yes >pty.log 2>&1; fi ) &
  PP=$!; G=0
  while kill -0 $PP 2>/dev/null; do G=$((G+1)); [ "$G" -ge 60 ] && { kill -9 $PP 2>/dev/null; break; }; sleep 1; done
  wait $PP 2>/dev/null || true
  [ "$G" -ge 60 ] && { echo "FAIL: 'adopt --here --yes' HUNG under a TTY (--yes must never block on input)"; exit 1; }
  echo "[adopt-pty-yes] update --here --yes completes under a real TTY (no hang)"
fi

echo "e2e: all installer rehearsals passed"
