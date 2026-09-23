#!/usr/bin/env bash
# End-to-end rehearsal for the installers. Shared by ci.yml (every push) AND release.yml (before it publishes),
# so a release can never ship while the e2e is red — the gap that once let a green release sit on top of a red CI.
# Run from anywhere; it resolves the repo root itself. Uses $RUNNER_TEMP in CI, a mktemp dir locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"

# WHY A LOG AND NOT /dev/null, for every installer and smoke call below.
#
# They all used to discard their output. Under `set -e` a failing one killed the run with nothing on screen
# but an exit status, so the reason was unknowable. That is exactly what happened on a Windows leg of
# e9d90a0: the generic combo failed, the output was gone, and it could only be filed as "not reproduced" —
# which is NOT the same as "not observed". Four passes out of five made a runner flake the likely reading,
# but nothing could have distinguished a flake from a real defect, and nothing would have next time either.
#
# A green run prints exactly what it printed before: the log is read ONLY when the step fails, and then only
# its tail, so CI output stays quiet until it has something to say. "Produced no output at all" is reported
# as its own case, because an empty log and a missing log answer different questions.
_STEP=0
_slog(){ _STEP=$((_STEP+1)); printf '%s/e2e-step-%02d.log' "$WORK" "$_STEP"; }
_evidence(){   # $1 = label, $2 = log path, $3 = the step's exit status
  echo "FAIL [$1]: the step exited $3. Last 20 lines of its own output:" >&2
  if [ -s "$2" ]; then tail -n 20 "$2" | sed 's/^/    | /' >&2
  else echo "    | (the step produced no output at all)" >&2; fi
  exit 1
}

# ---- start.sh: 2 combinations (backend pattern) ----
# 2.0 removed the profile split, and with it four of the six combinations: they differed only in which
# components were deleted after an identical install. The backend pattern is the one axis that still changes
# what lands on disk (cqrs-aop-module + the backend agent variant), so it is the one axis still rehearsed.
# The legacy-flag case is here rather than in the smoke-test because only an end-to-end run proves an old
# command line still installs — the thing that would break a CI step someone wrote a year ago.
combo() {
  local lbl="$1" inp="$2" exp_ag="$3" exp_sk="$4"; shift 4
  local P="$WORK/proj-$lbl"; rm -rf "$P"; mkdir -p "$P"
  cp start.sh "$P/"; cp -R claude-starter "$P/"
  _L="$(_slog)"; ( cd "$P" && printf "$inp" | bash start.sh "$@" ) >"$_L" 2>&1 || _evidence "start.sh in $P" "$_L" $?
  # scope=install: the gate UNIT cases drive hook binaries the installer copies UNCHANGED, so running all of
  # them in every combination re-checks identical bytes. Install scope keeps the install-dependent assertions
  # plus a canary that proves the installed hook actually executes; the exhaustive cases run once, in CI's
  # standalone full-scope smoke-test step.
  _L="$(_slog)"; ( cd "$P" && CSK_SMOKE_SCOPE=install bash .claude/eval/smoke-test.sh ) >"$_L" 2>&1 || _evidence "smoke-test.sh in $P" "$_L" $?
  # The install manifest is what separates kit-owned from project-owned downstream (doctor readiness, trust gate).
  [ -s "$P/.claude/kit-manifest.txt" ] || { echo "FAIL [$lbl]: .claude/kit-manifest.txt missing or empty"; exit 1; }
  grep -q '^skills/handoff$' "$P/.claude/kit-manifest.txt" || { echo "FAIL [$lbl]: manifest does not list the shipped skills"; exit 1; }
  # Component count is an ASSERTION now, not a printed number: the whole point of 2.0 is that the set no longer
  # varies, and a silent drop would otherwise read as a normal install.
  local ag sk; ag=$(ls "$P"/.claude/agents/*.md | wc -l | tr -d ' '); sk=$(ls -d "$P"/.claude/skills/*/ | wc -l | tr -d ' ')
  [ "$ag" = "$exp_ag" ] || { echo "FAIL [$lbl]: expected $exp_ag agents, got $ag"; exit 1; }
  [ "$sk" = "$exp_sk" ] || { echo "FAIL [$lbl]: expected $exp_sk skills, got $sk"; exit 1; }
  grep -q '^profile=' "$P/.claude/kit.conf" && { echo "FAIL [$lbl]: kit.conf still records a profile"; exit 1; }
  # The panel. `/studio-csk` resolves exactly this path and nothing else, so its absence is the ENOENT
  # this whole change exists to stop — asserted rather than assumed, in every install combination.
  [ -f "$P/.claude/studio/server/index.js" ] || { echo "FAIL [$lbl]: .claude/studio/server/index.js missing — /studio-csk would ENOENT"; exit 1; }
  # Silently load-bearing: every server file is ESM. Without this manifest node reads them as CommonJS
  # and the panel installs cleanly, then dies on its first import — a failure only the user meets.
  grep -q '"type": *"module"' "$P/.claude/studio/package.json" || { echo "FAIL [$lbl]: studio/package.json missing or not \"type\":\"module\" — the ESM server would not load"; exit 1; }
  [ ! -d "$P/.claude/studio/test" ] || { echo "FAIL [$lbl]: studio/test shipped into the project — its pins read the REPO and would be red here"; exit 1; }
  # The runtime finder. /studio-csk runs exactly this path when node is missing, and without it a
  # machine with no node is back to the dead end the whole feature exists to remove — silently,
  # because everything else about the install would still look right.
  [ -f "$P/.claude/studio/ensure-node.sh" ] || { echo "FAIL [$lbl]: .claude/studio/ensure-node.sh missing — a machine without node gets no way to get one"; exit 1; }
  echo "[$lbl] agents=$ag skills=$sk smoke=OK manifest=$(wc -l < "$P/.claude/kit-manifest.txt" | tr -d ' ') studio=installed"
}
# The expected counts come from the PAYLOAD, not from a number typed here. Written by hand they drift with the
# first component added — the network diagram's subtitle did exactly that, announcing 11 agents and 36 skills
# over a picture it had drawn with 12 and 38 — and the failure reads like a broken install rather than a stale
# constant. `--generic` prunes exactly one skill (cqrs-aop-module), so that arm is the payload count minus one;
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

# §4.2 arming. The blocklist ships the vendor name COMMENTED, beside a note telling the reader to add their own
# -- right for a name only the user knows, wrong for this one, because on the DevArchitecture path the kit is
# what brought the vendor onto the machine. So the installer uncomments it there and only there, and both halves
# are asserted: an armed pattern on --dotnet, and a still-commented one on --generic, where a DevArchitecture
# pattern would block an ordinary commit that merely discusses the pattern. The third assertion is the one that
# matters -- an uncommented line proves the edit ran, not that anything is enforced -- so the REAL commit-msg
# hook is driven with a message carrying the name, and with one that does not.
BL_DN="$WORK/proj-dotnet/.claude/hooks/trace-blocklist.txt"
BL_GEN="$WORK/proj-generic/.claude/hooks/trace-blocklist.txt"
grep -qx 'DevArchitecture'   "$BL_DN"  || { echo "FAIL: --dotnet left the §4.2 vendor pattern commented out"; exit 1; }
grep -qx '# DevArchitecture' "$BL_GEN" || { echo "FAIL: --generic armed a vendor pattern for a stack it did not install"; exit 1; }
# In a throwaway repo rather than in proj-dotnet itself, for two reasons: the hook needs a git repository (its
# board step says so and exits non-zero without one, which is correct -- a commit-msg hook only ever runs inside
# one), and proj-dotnet is read by later assertions that should not inherit a .git this check created.
TR="$WORK/trace42"; rm -rf "$TR"; mkdir -p "$TR"
cp -R "$WORK/proj-dotnet/.claude" "$TR/" && ( cd "$TR" && git init -q . ) \
  || { echo "FAIL: could not stage the §4.2 hook check"; exit 1; }
CMT="$TR/msg.txt"
printf 'feat(api): ported the handler from DevArchitecture\n' > "$CMT"
( cd "$TR" && bash .claude/hooks/commit-msg "$CMT" ) >/dev/null 2>&1 \
  && { echo "FAIL: the armed vendor pattern did not block a commit message carrying the name"; exit 1; }
# The must-PASS twin, and it earned its place: the first version of this check ran outside a repo, where the
# hook fails for its own reasons, so the blocking assertion above was green against a hook that refused
# EVERYTHING. A gate tested only on what it must reject is indistinguishable from a gate that rejects all.
printf 'feat(api): add the unpaid invoices endpoint\n' > "$CMT"
( cd "$TR" && bash .claude/hooks/commit-msg "$CMT" ) >/dev/null 2>&1 \
  || { echo "FAIL: the armed vendor pattern blocked an ordinary commit message"; exit 1; }
rm -rf "$TR"
echo "[trace-4.2] --dotnet arms the vendor name and the hook enforces it; --generic leaves it commented"

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
  echo "  cqrs-aop-module:   $([ -d "$2/.claude/skills/cqrs-aop-module" ] && echo present || echo absent)"
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
[ -d "$P/.claude/skills/cqrs-aop-module" ]               || die "cqrs-aop-module missing on a dotnet adopt" adopt-dotnet "$P"
[ ! -f "$P/.claude/agents/backend-expert.md" ]          || die "overlapping project agent was not taken over" adopt-dotnet "$P"
[ -f "$P/.claude/superseded/agents/backend-expert.md" ] || die "taken-over agent's original was not backed up" adopt-dotnet "$P"
[ -f "$P/.claude/skills/backend-expert-local/SKILL.md" ]|| die "taken-over agent's domain was not imported to a project skill" adopt-dotnet "$P"
# The manifest lists what the KIT ships, so the skill this adopt imported from the project must NOT appear in it
# — that is exactly the distinction the readiness check and the trust gate are built on.
grep -q '^skills/cqrs-aop-module$' "$P/.claude/kit-manifest.txt"     || { echo "FAIL: manifest missing a kit skill"; exit 1; }
grep -q '^skills/backend-expert-local$' "$P/.claude/kit-manifest.txt" && { echo "FAIL: manifest claims a project-imported skill as kit-owned"; exit 1; }
# Captured, not piped: `grep -q` closes the pipe on its first match, doctor takes a SIGPIPE, and `pipefail`
# would then report a passing assertion as a failure.
DT0=$SECONDS
DOUT="$( cd "$P" && bash .claude/eval/doctor.sh 2>&1 || true )"
DEL=$((SECONDS - DT0))
case "$DOUT" in *"project-specific skill(s)"*) ;; *) echo "FAIL: doctor readiness did not detect the project's own skill"; exit 1 ;; esac
# The §4.6 liveness probe, asserted on a REAL install rather than left as an unasserted side effect. It was
# already running here — doctor runs in full — but nothing read its verdict, and this call is wrapped in
# `|| true`, so a probe reporting "bad" would have passed through every platform silently. The probe itself is
# calibrated against a neutered hook in smoke-test; what this adds is that it reaches the same verdict on a
# tree start.sh actually produced, on every OS this job runs on.
case "$DOUT" in *"enforces the §4.6 review gate"*) ;;
  *) echo "FAIL: doctor did not confirm the §4.6 review gate on a real install — the probe or the hook is missing"; exit 1 ;; esac
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
_L="$(_slog)"; ( cd "$P" && CSK_SMOKE_SCOPE=install bash .claude/eval/smoke-test.sh ) >"$_L" 2>&1 || { tail -n 20 "$_L" | sed 's/^/    | /' >&2; echo "FAIL: the adopted project's own smoke-test did not pass"; exit 1; }
# doctor's elapsed time is printed on SUCCESS too, not only in the failure message. The bound above is loose by
# design, so a silent pass hides the trend that matters: 2s creeping to 8s is the regression arriving, and it
# reads as "fine" until the day it trips. The number in the log is what makes that visible in hindsight.
echo "[adopt-dotnet] stack=dotnet · cqrs-aop-module kept · overlap imported to skill + backed up · smoke OK · doctor ${DEL}s"

# A generic (Node) project: no .sln -> generic, cqrs-aop-module pruned.
G="$WORK/adopt-generic"; rm -rf "$G"; mkdir -p "$G"
cp adopt.sh "$G/"; cp -R claude-starter "$G/"; cp VERSION "$G/"; printf '{"name":"x"}' > "$G/package.json"
( cd "$G" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
run_adopt "$G" --yes
grep -q '^stack=generic' "$G/.claude/kit.conf"          || die "Node project not recorded as generic" adopt-generic "$G"
[ ! -d "$G/.claude/skills/cqrs-aop-module" ]             || die "cqrs-aop-module not pruned on a generic adopt" adopt-generic "$G"
echo "[adopt-generic] stack=generic · cqrs-aop-module pruned"

# A REFRESH whose recorded stack is a stale 'generic' on a clearly-DevArch project. The correction is OFFERED,
# never applied behind the user's back — so this asserts BOTH halves, and the first half is the one that was
# missing. The old test ran `--yes` (no tty) and required stack=dotnet, i.e. it demanded that a recorded choice
# be overruled where nobody could be asked. It passed for five releases while a user who installed --generic on
# a .NET project that is NOT DevArchitecture got cqrs-aop-module and the .NET agent pushed onto them.
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
[ ! -d "$R/.claude/skills/cqrs-aop-module" ]             || die "cqrs-aop-module installed without anyone approving the stack change" adopt-refresh/keep "$R"
grep -qi 'stack-agnostic' "$R/.claude/agents/backend-expert-csk.md" || die "backend agent flipped to .NET without approval" adopt-refresh/keep "$R"
# (b) asked for deliberately -> corrected, and cqrs-aop-module comes back with it.
CSK_CORRECT_STACK=1 run_adopt "$R" --yes
grep -q '^stack=dotnet' "$R/.claude/kit.conf"           || die "CSK_CORRECT_STACK=1 did not correct a stale generic stack" adopt-refresh/fix "$R"
[ -d "$R/.claude/skills/cqrs-aop-module" ]               || die "cqrs-aop-module not restored after the stack correction" adopt-refresh/fix "$R"
echo "[adopt-refresh] recorded generic KEPT without a person · CSK_CORRECT_STACK=1 corrects it -> dotnet"

# ---- adopt.sh: the devarch-module -> cqrs-aop-module RENAME, on an install that predates kit.conf ----
# The skill was renamed, and three things could have gone wrong on the upgrade path; this case holds all three.
# (1) kit_infer_shape reads the STACK from the skill's directory name when kit.conf is absent, so a check for the
#     new name alone classifies every old .NET install as generic — and the generic path PRUNES the pattern skill.
# (2) kit-manifest.txt arrived in v1.8.0 and the skill shipped from v1.0.0, so the stale-files sweep is blind to
#     an install not updated since before 1.8.0.
# (3) that sweep only REPORTS, so without a migration two pattern skills would compete for every prompt.
# The fixture is shaped to isolate (1): no .sln, no kit.conf, no manifest — the OLD directory is the only signal.
U="$WORK/adopt-rename"; rm -rf "$U"; mkdir -p "$U"
cp adopt.sh "$U/"; cp -R claude-starter "$U/"; cp VERSION "$U/"
: > "$U/App.sln"
( cd "$U" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
run_adopt "$U" --yes
[ -d "$U/.claude/skills/cqrs-aop-module" ]  || die "the first adopt did not install the .NET pattern skill" adopt-rename/setup "$U"
# Down to the shape of a pre-1.8.0 .NET install that has never been updated since:
mv "$U/.claude/skills/cqrs-aop-module" "$U/.claude/skills/devarch-module"
rm -f "$U/.claude/kit.conf" "$U/.claude/kit-manifest.txt" "$U/App.sln"
( cd "$U" && git add -A && git commit -qm 'shape of a pre-1.8.0 dotnet install' ) >/dev/null 2>&1
run_adopt "$U" --yes
grep -q '^stack=dotnet' "$U/.claude/kit.conf" || die "an install carrying only the OLD skill name was inferred generic (it would be pruned)" adopt-rename "$U"
[ -d "$U/.claude/skills/cqrs-aop-module" ]    || die "the .NET pattern skill is gone after the rename migration" adopt-rename "$U"
[ ! -d "$U/.claude/skills/devarch-module" ]   || die "the old skill was left beside the new one — two pattern skills compete" adopt-rename "$U"
echo "[adopt-rename] pre-kit.conf install carrying the OLD name -> inferred dotnet, migrated, no duplicate"

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
mk_stale_install(){                       # $1 = dir, [$2 = settings.json] : a healthy 1.4.x install whose settings.json is STALE
  local d="$1"; rm -rf "$d"; mkdir -p "$d/.claude"
  cp adopt.sh "$d/"; cp -R claude-starter "$d/"; cp VERSION "$d/"
  cp -R "$d/claude-starter/." "$d/.claude/" 2>/dev/null; cp VERSION "$d/.claude/VERSION"
  printf 'profile=fullstack\nstack=generic\ninstaller=start.sh\n' > "$d/.claude/kit.conf"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2"; else printf '%s\n' '{ "permissions": { "ask": [ "Bash(git add:*)", "Bash(git commit:*)", "Bash(git push:*)", "Bash(git checkout -b:*)", "Bash(terraform apply:*)" ] }, "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type":"command","command":"bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/context-usage.sh\" 2>/dev/null || true","timeout":10 } ] } ] } }'; fi > "$d/settings.stale"
  cp "$d/settings.stale" "$d/.claude/settings.json"
  printf '# project rules\n@.claude/DISCIPLINE.md\n' > "$d/CLAUDE.md"
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
}
# The four §4.4 ask rules were RETIRED from the kit (a matching ask rule outranks a hook's "allow", so it killed
# CLAUDE_GIT_OK). Concat+dedup never removes, so an update must drop them explicitly; the fixture carries all four
# plus one rule of the project's own, which must survive every arm that merges. Prints what it found, not a verdict
# word, so a failure names the rule that stayed.
retired_gone(){                           # $1 = settings.json
  local r left=""; for r in 'Bash(git add:*)' 'Bash(git commit:*)' 'Bash(git push:*)' 'Bash(git checkout -b:*)'; do
    grep -qF "\"$r\"" "$1" && left="$left $r"; done
  [ -z "$left" ] || { echo "FAIL: an update kept retired §4.4 ask rule(s):$left — CLAUDE_GIT_OK stays dead in that project"; exit 1; }
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
UOUT="$( cd "$U" && bash adopt.sh --here </dev/null 2>&1 )"; cp "$U/.claude/settings.json" "$U/settings.first"
grep -q 'SessionStart' "$U/.claude/settings.json"       || { echo "FAIL: non-interactive update did not self-heal (SessionStart missing)"; exit 1; }
grep -q "\"timeout\": $KIT_TO" "$U/.claude/settings.json"      || { echo "FAIL: non-interactive update did not refresh the stale timeout"; exit 1; }
head -1 "$U/CLAUDE.md" | grep -q 'project rules'        || { echo "FAIL: update clobbered the project's own CLAUDE.md"; exit 1; }
retired_gone "$U/.claude/settings.json"
grep -q '"Bash(terraform apply:\*)"' "$U/.claude/settings.json" || { echo "FAIL: retiring the kit's ask rules also dropped the project's own"; exit 1; }
grep -q '"Bash(ssh:\*)"' "$U/.claude/settings.json"             || { echo "FAIL: retiring the §4.4 rules also dropped the kit's deploy ask rules"; exit 1; }
# The removal is a change to a file the project may track, and a string match cannot tell the kit's copy from the
# project's own — so it must be SAID, by name, and the merge line must not claim every permission was preserved.
case "$UOUT" in *"ask rule(s) REMOVED (git add, git commit, git push, git checkout -b)"*) ;;
  *) echo "FAIL: the retired ask rules were removed SILENTLY — output: $(printf '%s' "$UOUT" | grep 'settings.json' | tr '\n' ' ')"; exit 1 ;; esac
case "$UOUT" in *"custom hooks/permissions PRESERVED"*) echo "FAIL: the merge line claims every permission was preserved while rules were removed"; exit 1 ;; esac
grep -q 'retired §4.4 ask rule(s) REMOVED: git add, git commit, git push, git checkout -b' "$U/docs/HANDOVER.md" 2>/dev/null \
  || { echo "FAIL: HANDOVER.md does not record the removed rules (it would read 'permissions PRESERVED')"; exit 1; }
# Twin: a second update has nothing left to retire, so it must announce nothing and keep the plain claim.
UOUT2="$( cd "$U" && bash adopt.sh --here </dev/null 2>&1 )"
case "$UOUT2" in *"REMOVED ("*) echo "FAIL: an update with no retired rule present still announced a removal"; exit 1 ;; esac
case "$UOUT2" in *"custom hooks/permissions PRESERVED"*) ;; *) echo "FAIL: the plain PRESERVED line is gone even when nothing was removed"; exit 1 ;; esac
# (B) The merge is ONE awk path, so a machine without jq/python3 must produce the SAME file. Stubs named jq,
# python3, python and py sit FIRST on PATH and exit 49 like the Microsoft Store redirector: were the merge still
# to reach for either tool it would get a failing one. No symlink farm, so this leg runs on Windows Git-Bash too.
N="$WORK/selfheal-nojq"; mk_stale_install "$N"
STUBS="$WORK/store-stubs"; rm -rf "$STUBS"; mkdir -p "$STUBS"
for _t in jq python3 python py; do printf '#!/bin/sh\necho "Python was not found" >&2\nexit 49\n' > "$STUBS/$_t"; chmod +x "$STUBS/$_t"; done
_L="$(_slog)"; ( cd "$N" && PATH="$STUBS:$PATH" bash adopt.sh --here </dev/null ) >"$_L" 2>&1 || _evidence "adopt.sh in $N" "$_L" $?
cmp -s "$U/settings.first" "$N/.claude/settings.json" \
  || { echo "FAIL: with jq/python3 failing, the settings merge produced a different file:"; diff "$U/settings.first" "$N/.claude/settings.json" | head -20; exit 1; }
# (E) A project that grew its own settings: a foreign hook in a kit event, a foreign event, a stale copy of a kit
# hook, extra rules in all three permission arrays, and keys the kit does not ship. Each must land where the old
# jq merge put it — asserted by name here, and against that jq program itself where jq exists.
R="$WORK/selfheal-rich"; mk_stale_install "$R" '{
  "model": "opus", "env": { "A": "1", "B": "say \"hi\" \\ ç" }, "skillListingBudgetFraction": 0.5,
  "permissions": { "allow": [ "Bash", "WebFetch(domain:example.com)" ], "ask": [ "Bash(git push:*)", "Bash(terraform apply:*)" ],
    "deny": [ "Read(.env)", "Read(secrets/**)" ], "defaultMode": "acceptEdits" },
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "my-own-check.sh", "timeout": 5 } ] },
                    { "matcher": "Bash|PowerShell", "hooks": [ { "type": "command", "command": "bash", "args": [ "old/.claude/hooks/guard-bash.sh" ] } ] } ],
    "Notification": [ { "hooks": [ { "type": "command", "command": "notify-send hi" } ] } ]
  }
}'

_L="$(_slog)"; ( cd "$R" && PATH="$STUBS:$PATH" bash adopt.sh --here </dev/null ) >"$_L" 2>&1 || _evidence "adopt.sh in $R" "$_L" $?
for _k in '"my-own-check.sh"' '"notify-send hi"' '"model": "opus"' '"defaultMode": "acceptEdits"' '"Read(secrets/**)"' \
          '"WebFetch(domain:example.com)"' '"Bash(terraform apply:*)"' '"B": "say \"hi\" \\ ç"' '"skillListingBudgetFraction": 0.5' 'SessionStart'; do
  grep -qF "$_k" "$R/.claude/settings.json" || { echo "FAIL: the merge lost the project's $_k"; exit 1; }; done
! grep -qF 'old/.claude/hooks/guard-bash.sh' "$R/.claude/settings.json" || { echo "FAIL: a stale kit hook survived the refresh"; exit 1; }
! grep -qF '"Bash(git push:*)"' "$R/.claude/settings.json"              || { echo "FAIL: a retired ask rule survived the merge"; exit 1; }
[ "$(grep -cF '"Read(.env)"' "$R/.claude/settings.json")" = 1 ]           || { echo "FAIL: a rule both sides carry was not deduplicated"; exit 1; }
# Parity with the program the awk merge replaced. It lives here only, as the oracle; the product never runs it.
# Compared after `jq -S .`, so key order is out and array order stays in. Needs a jq that RUNS (not a stub).
JQ_ORACLE='
def ddedup: reduce .[] as $x ([]; if any(.[]; .==$x) then . else .+[$x] end);
def dm(a;b): reduce (b|keys_unsorted[]) as $k (a;
  if (.[$k]|type)=="object" and (b[$k]|type)=="object" then .[$k]=dm(.[$k];b[$k])
  elif (.[$k]|type)=="array" and (b[$k]|type)=="array" then .[$k]=((.[$k]+b[$k])|ddedup)
  else .[$k]=b[$k] end);
def is_kit: ((.hooks // []) | map((((.command // "") + " " + ((.args // []) | join(" "))) | contains(".claude/hooks/"))) | any);
def merge_hooks(kh;ph):
  (((kh|keys_unsorted)+(ph|keys_unsorted))|unique) as $e
  | reduce $e[] as $k ({}; .[$k]=((kh[$k] // [])+((ph[$k] // [])|map(select(is_kit|not)))));
def retired: ["Bash(git add:*)","Bash(git commit:*)","Bash(git push:*)","Bash(git checkout -b:*)"];
def drop_retired: if (.permissions.ask|type)=="array" then .permissions.ask -= retired else . end;
(dm($k[0]; $p[0]) | drop_retired) | .hooks=merge_hooks(($k[0].hooks // {}); ($p[0].hooks // {}))'
if printf '{}' | jq -e . >/dev/null 2>&1; then
  for _c in "$U/settings.stale:$U/settings.first" "$R/settings.stale:$R/.claude/settings.json"; do
    _in="${_c%%:*}"; _out="${_c#*:}"
    _want="$(jq -n --slurpfile p "$_in" --slurpfile k claude-starter/settings.json "$JQ_ORACLE" | jq -S .)"
    [ -n "$_want" ] && [ "$_want" = "$(jq -S . "$_out")" ] \
      || { echo "FAIL: the awk merge disagrees with the jq oracle on $_in:"; diff <(printf '%s\n' "$_want") <(jq -S . "$_out") | head -20; exit 1; }
  done
  PARITY_NOTE="awk merge == jq oracle on 2 fixtures"
else
  PARITY_NOTE="jq-oracle parity SKIPPED (no working jq here; it runs on the CI runners)"
  echo "[adopt-selfheal] SKIP: jq-oracle parity — no working jq on this machine"
fi
# (F) Invalid JSON is refused and left byte-for-byte as it was, and HANDOVER must not claim a merge.
I="$WORK/selfheal-invalid"; mk_stale_install "$I" '{ "permissions": { "ask": [ "Bash(terraform apply:*)" ] '
IOUT="$( cd "$I" && PATH="$STUBS:$PATH" bash adopt.sh --here </dev/null 2>&1 )"
cmp -s "$I/settings.stale" "$I/.claude/settings.json" || { echo "FAIL: an invalid settings.json was overwritten"; exit 1; }
case "$IOUT" in *"INVALID JSON -> merge ABORT"*) ;; *) echo "FAIL: an invalid settings.json was not reported as such"; exit 1 ;; esac
grep -q 'settings.json: NOT merged' "$I/docs/HANDOVER.md" 2>/dev/null || { echo "FAIL: HANDOVER claims a merge that did not run"; exit 1; }
# (C) FIRST adopt (no kit present) · non-interactive · NO --yes -> declines (a brownfield change still needs consent)
F="$WORK/firstadopt"; rm -rf "$F"; mkdir -p "$F"
cp adopt.sh "$F/"; cp -R claude-starter "$F/"; cp VERSION "$F/"; printf '{"name":"x"}' > "$F/package.json"
( cd "$F" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
_L="$(_slog)"; ( cd "$F" && bash adopt.sh --here </dev/null ) >"$_L" 2>&1 || _evidence "adopt.sh in $F" "$_L" $?
[ ! -f "$F/.claude/DISCIPLINE.md" ]                     || { echo "FAIL: first adopt must NOT apply non-interactively without --yes"; exit 1; }
echo "[adopt-selfheal] update self-heals off a TTY, same file with jq/python failing · $PARITY_NOTE · retired §4.4 ask rules dropped, own rules and hooks kept · invalid JSON refused · CLAUDE.md preserved · first adopt still needs --yes"

# (D) TTY + --yes must NOT hang — the /update-csk regression. adopt.sh once tested `-t 0` BEFORE --yes, so an
# --yes run that inherited a TTY (Claude Code drives commands under a pty on Windows) blocked on a prompt. Every
# test above misses it by construction — they close stdin, so `-t 0` is false. Here we allocate a REAL pty and
# assert the refresh completes under --yes. Needs a pty-capable `script`; skipped where none exists (Git-Bash).
T="$WORK/pty-yes"; rm -rf "$T"; mkdir -p "$T"
cp start.sh adopt.sh VERSION "$T/"; cp -R claude-starter "$T/"
# empty baseline commit BEFORE install (no hooksPath yet), then install; the refresh below STAGES only (like
# /update-csk) so no pre-commit trace hook runs — the point here is the prompt behaviour, not a commit.
_L="$(_slog)"; ( cd "$T" && git init -q && git config user.email t@t.t && git config user.name t && git commit -q --allow-empty -m base \
    && printf 'yes\nno\n' | bash start.sh --dotnet ) >"$_L" 2>&1 || _evidence "start.sh --dotnet in $T" "$_L" $?
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

# ---- the panel actually runs, and finds the kit's colours, from an INSTALLED tree ----
# Two claims, both of which were false before this release and neither of which any assertion above can
# see: (a) the installed panel starts at all — the ESM/`--selftest` path, which is what catches a missed
# package.json; (b) its palette resolves the kit's agents from `.claude/`, not only from this checkout.
# (b) is the one that was silently wrong: the old resolver looked for `<parent>/claude-starter/agents`,
# found nothing anywhere but here, and drew all twelve kit agents in the grey reserved for types nobody
# declared — "not measured" rendered as a fact.
PN="$WORK/proj-dotnet"
if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1; then
  NV="$(node --version)"
  # Keep the output. Discarding it and naming the node version in the failure sent
  # exactly one reader hunting a Node 24 incompatibility that did not exist: the
  # real cause was the claude CLI being absent on this runner, which selftest was
  # counting as a failure while calling it a skip in its own text.
  SELFOUT="$( cd "$PN" && node .claude/studio/server/index.js --selftest 2>&1 )" \
    || { echo "FAIL: the installed panel's --selftest exited non-zero on node $NV:"; \
         printf '%s\n' "$SELFOUT" | sed 's/^/    /'; exit 1; }
  INST_AG="$(ls "$PN"/.claude/agents/*.md | wc -l | tr -d ' ')"
  PAL="$( cd "$PN" && node -e "import('./.claude/studio/server/lib/palette.js').then(m=>{const p=m.palette();process.stdout.write(\`\${p.measured}:\${p.kitAgents}:\${p.agentsDir}\`)})" )"
  case "$PAL" in
    "true:$INST_AG:"*) echo "[studio-installed] --selftest ok on node $NV · palette measured, $INST_AG kit agents from ${PAL#true:$INST_AG:}" ;;
    *) echo "FAIL: the installed palette did not resolve the kit's agents — expected true:$INST_AG:<dir>, got '$PAL'"; exit 1 ;;
  esac

  # Everything above this line is reachable without the server ever listening:
  # files exist, modules parse, the palette resolves, the CLI answers. So "the
  # panel works" had been measured on one machine, by hand, and assumed
  # everywhere else. This starts it and drives it over HTTP.
  #
  # The probe is node, not shell, because the shell half is exactly where Windows
  # differs — backgrounding, kill semantics, curl's flags — and Windows is the
  # platform the claim was weakest on.
  echo "[studio-serves] starting the installed panel and driving it over HTTP"
  node packaging/studio-serve-probe.mjs "$PN" || { echo "FAIL: the installed panel did not serve"; exit 1; }
  # And the plugin edition's copy, which is a second deployment of the same panel from a different
  # root. It was measured by hand on one machine and gated nowhere; the probe takes the directory
  # that CONTAINS studio/, so the same nine checks drive both layouts on every platform CI covers.
  echo "[studio-serves] the plugin edition's copy, from the plugin root"
  node packaging/studio-serve-probe.mjs "$ROOT/plugin" || { echo "FAIL: the panel did not serve from the plugin root"; exit 1; }
else
  echo "[studio-installed] SKIPPED (no working node here — the panel needs 18+)"
fi

# ---- UPDATE: a project that ALREADY has the kit gets the panel on its next update ----
# This is the reported bug, end to end. The project is installed from a payload with NO studio/ — the
# shape every 2.8.0 install has — and then updated the way /update-csk drives it. The panel must ARRIVE.
# Asserted in both directions: absent after the old install, present after the update. Asserting only
# the second half would pass against an installer that had shipped it all along, i.e. prove nothing.
UP="$WORK/update-gets-panel"; rm -rf "$UP"; mkdir -p "$UP"
cp start.sh VERSION "$UP/"; cp -R claude-starter "$UP/"; rm -rf "$UP/claude-starter/studio" "$UP/claude-starter/commands/studio-csk.md"
_L="$(_slog)"; ( cd "$UP" && git init -q && git config user.email t@t.t && git config user.name t \
    && git commit -q --allow-empty -m base && printf 'yes\n' | bash start.sh --generic ) >"$_L" 2>&1 || _evidence "start.sh --generic in $UP" "$_L" $?
[ -f "$UP/.claude/VERSION" ] || { echo "FAIL: the pre-panel install did not complete"; exit 1; }
# The installer that ran is THIS one, so it mkdir'd an empty .claude/studio before finding nothing to
# copy. A real 2.8.0 install has no such directory; remove it, or the assertion below is checking that
# an empty directory became a full one rather than that a panel arrived where there was none.
rmdir "$UP/.claude/studio" 2>/dev/null || true
[ ! -e "$UP/.claude/studio" ] || { echo "FAIL: the fixture is wrong — the pre-panel install already has a panel, so the update below would prove nothing"; exit 1; }
[ ! -e "$UP/.claude/commands/studio-csk.md" ] || { echo "FAIL: the fixture is wrong — /studio-csk is already installed"; exit 1; }
cp adopt.sh "$UP/"; cp -R claude-starter "$UP/claude-starter"; cp VERSION "$UP/"
_L="$(_slog)"; ( cd "$UP" && bash adopt.sh --here --yes </dev/null ) >"$_L" 2>&1 || _evidence "adopt.sh in $UP" "$_L" $?
[ -f "$UP/.claude/studio/server/index.js" ] || { echo "FAIL: an existing kit install did NOT get the panel on update — this is the reported bug"; exit 1; }
grep -q '"type": *"module"' "$UP/.claude/studio/package.json" || { echo "FAIL: the updated panel has no \"type\":\"module\" — it would die on first import"; exit 1; }
[ ! -d "$UP/.claude/studio/test" ] || { echo "FAIL: the update shipped studio/test into the project"; exit 1; }
[ -f "$UP/.claude/studio/ensure-node.sh" ] || { echo "FAIL: the update brought the panel but not the runtime finder beside it"; exit 1; }
[ -f "$UP/.claude/commands/studio-csk.md" ] || { echo "FAIL: the update did not deliver /studio-csk"; exit 1; }
echo "[update-gets-panel] a 2.8.0-shaped install gained .claude/studio ($(find "$UP/.claude/studio" -type f | wc -l | tr -d ' ') files) and /studio-csk on update"

# ---- the install WIZARD: unattended runs, the .gitignore question, and what --yes may not approve ----
# These are here rather than in the smoke-test because every one of them needs a real installer run: the
# question is what the wizard DOES to a project, not what a string in it says. Each case carries the reason it
# exists, and where a mistake is recoverable only by a twin that fails, the twin is run.
#
# The hang these first cases pin was MEASURED on stock Windows before it was fixed: `start.sh` with an
# open-but-empty stdin returned rc=124 under `timeout` — a block, separated from EOF by calibration (a bare
# `read` with stdin CLOSED returns rc=1). And it died at the stack chooser, not at `ask_yes`: fixing only the
# one everybody looked at moved the hang from line 72 to line 248 and the installer still hung. So the pins
# below have to cover EVERY read, which is what "no question is reached" means here.
wiz() {                                     # $1 = label -> a fresh project with the installer staged
  local P="$WORK/wiz-$1"; rm -rf "$P"; mkdir -p "$P"
  cp start.sh "$P/"; cp -R claude-starter "$P/"; printf '%s' "$P"
}

# 13 · An unattended install reads NOTHING and completes. stdin is closed rather than a pipe: a pipe would
#      answer the prompts and prove the opposite of what this asserts.
W="$(wiz yes-alone)"
( cd "$W" && bash start.sh --yes >"$W/out.txt" 2>&1 </dev/null )
[ -d "$W/.claude" ] || { echo "FAIL: start.sh --yes did not install with stdin closed"; exit 1; }
# 14 · ...and it does NOT approve the risky one. `--yes` means "install the kit unattended", not "clone a
#      third-party base project into my tree over the network" — the script's own word for that is risky.
[ ! -e "$W/backend" ] || { echo "FAIL: --yes cloned the DevArchitecture base; that is a separate consent"; exit 1; }
grep -q 'does not approve' "$W/out.txt" || { echo "FAIL: --yes declined the risky step without saying why"; exit 1; }
echo "[wizard] --yes installs unattended, reads nothing, and refuses the risky clone with a reason"

# 2 · TWO DIFFERENT STDINs, and the difference is the whole point. CLOSED stdin reaches EOF, so every `read`
#     answers "" and the installer declines. OPEN-BUT-EMPTY never reaches EOF, so a bare `read` waits forever —
#     that is what a pty looks like, which is how Claude Code runs a command on Windows, and it is the case
#     `adopt.sh:46-49` was written for. The first version of this case drove `</dev/null` and passed while
#     measuring the wrong condition, and skipped entirely where `timeout(1)` is absent, which includes macOS.
#
#     The timeout is perl's `alarm` rather than `timeout(1)`: perl ships with macOS AND with Git Bash, so the
#     case runs everywhere instead of announcing a skip on two of three platforms. 142 is SIGALRM.
#     CALIBRATED IN-LINE, because "it hung" is only meaningful if the two stdins demonstrably differ here: a
#     bare `read` must time out on the fifo and must return at once on /dev/null. If those two agree, the
#     fixture proves nothing and says so rather than reporting a pass.
# The bound is a POLLING PARENT, not a timeout utility, and that is the whole point: it cannot itself hang.
# The first version used `perl -e alarm` + exec, and on windows-latest the alarm did not interrupt a blocked
# `read` — so the e2e step ran until the job was killed. Steps 1-7 green, step 8 with no conclusion at all.
# The calibration below was supposed to catch a broken bound and skip; instead it was the FIRST thing to hang,
# because it used the same mechanism. A calibration that can hang is not a calibration. This loop runs at most
# `secs` iterations of `sleep 1` and then SIGKILLs, so every path is bounded by construction.
_bounded(){                     # $1 = seconds, rest = command; prints BLOCKED or rc=<n>
  local secs="$1"; shift
  # THE BUDGET MUST EXCEED THE PRODUCT'S OWN. `csk_read` waits 10 s per prompt and the no-flag path reaches two
  # of them, so a 20 s bound reported BLOCKED for an installer that was about to decline correctly at ~20 s —
  # my harness's budget, not a hang. Measured directly afterwards: rc=0, "Cancelled — nothing changed". 60 s
  # leaves room for three bounded reads plus the work between them.
  # `<&0` is load-bearing: bash redirects a BACKGROUND job's stdin from /dev/null unless it is given one
  # explicitly, so without this the child never sees the caller's fifo, reads EOF and returns rc=1. The
  # calibration below caught exactly that and skipped rather than reporting a pass — which is what it is for.
  # The child's own output is swallowed HERE rather than by the caller: a redirect on the call site silences
  # this function's verdict too, which is how the captured value came back empty and the installer's banner
  # ended up inside a status line.
  "$@" <&0 >/dev/null 2>&1 & local p=$! i=0
  while [ "$i" -lt "$secs" ]; do
    kill -0 "$p" 2>/dev/null || { wait "$p"; echo "rc=$?"; return 0; }
    sleep 1; i=$((i+1))
  done
  kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; echo BLOCKED
}
_FC="$WORK/fifo-cal"; rm -rf "$_FC"; mkdir -p "$_FC"
( cd "$_FC" && mkfifo f && exec 3<>f && _bounded 5 bash -c 'read -r x' <&3 > rc_open; exec 3>&- ) || true
( cd "$_FC" && _bounded 5 bash -c 'read -r x' </dev/null > rc_closed ) || true
if [ "$(cat "$_FC/rc_open")" = BLOCKED ] && [ "$(cat "$_FC/rc_closed")" != BLOCKED ]; then
  W2="$(wiz no-yes-closed)"
  rc="$( cd "$W2" && _bounded 60 bash start.sh </dev/null )"
  [ "$rc" != BLOCKED ] || { echo "FAIL: start.sh blocked even on CLOSED stdin — every piped install would hang"; exit 1; }
  [ ! -d "$W2/.claude" ] || { echo "FAIL: start.sh installed without consent and without --yes"; exit 1; }
  echo "[wizard] closed stdin: declines ($rc) rather than installing or blocking"

  # --yes is what makes an unattended run safe on a pty. Asserted on the OPEN-EMPTY stdin, which is the
  # condition that actually hangs, rather than on the one that returns anyway.
  W2B="$(wiz yes-openempty)"
  ( cd "$W2B" && mkfifo f && exec 3<>f && _bounded 60 bash start.sh --yes <&3 > rc; exec 3>&- ) || true
  [ "$(cat "$W2B/rc")" != BLOCKED ] \
    || { echo "FAIL: start.sh --yes BLOCKED on open-but-empty stdin — unattended runs hang under a pty"; exit 1; }
  echo "[wizard] --yes returns on open-but-empty stdin (the pty shape), $(cat "$W2B/rc")"

  # THE PIPE SHAPE IS CLOSED, and this is a real verdict rather than a recorded state. Without --yes, an
  # open-but-empty stdin used to block forever — measured 142 here and on stock Windows, at the stack chooser
  # with no flags and one prompt later with --generic. All three bare reads are now bounded, so the installer
  # returns and declines instead. The must-fail twin lives with the fix: removing the timeout from `csk_read`
  # puts 142 back on this same fifo.
  W2C="$(wiz noyes-openempty)"
  ( cd "$W2C" && mkfifo f && exec 3<>f && _bounded 60 bash start.sh <&3 > rc; exec 3>&- ) || true
  [ "$(cat "$W2C/rc")" != BLOCKED ] \
    || { echo "FAIL: without --yes an open-but-empty stdin BLOCKS again — the bounded read regressed"; exit 1; }
  [ ! -d "$W2C/.claude" ] \
    || { echo "FAIL: the bounded read answered YES on its own — a timeout must decline, never consent"; exit 1; }
  echo "[wizard] open-but-empty PIPE: returns and declines ($(cat "$W2C/rc")), nothing installed"

  # CANNOT-CLOSE, and named that way on purpose rather than "known-open", which reads as something that will be
  # closed one day. A PTY WITH NO INPUT cannot be distinguished from a human who types slowly: `[ -t 0 ]` is
  # TRUE under a pty, so no stdin test separates the two, and a bounded read would either cut off a real person
  # or consent on their behalf. `--yes` is the answer and the only answer. This is not asserted here because a
  # real pty cannot be allocated from this harness — `winpty` refuses when its own stdin is not a terminal and
  # Git Bash ships no `script` — so it is recorded as unmeasurable rather than left looking pending. The
  # measured half above is the pipe; do not read it as covering the pty.
else
  echo "[wizard] SKIP (fixture): the two stdin shapes did not separate here (open=$(cat "$_FC/rc_open") closed=$(cat "$_FC/rc_closed")), so a hang could not be told from a pass"
fi

# 15 · THE PIPE-ORDER GATE. A new prompt shifts every existing piped call by one answer. Adding the visibility
#      question without a guard did exactly that: the question ate the 'yes', the confirm hit EOF, the install
#      cancelled silently and this suite failed with rc=127. So the non-TTY path must read NOTHING, and the
#      documented piped form must keep working. Removing the `[ ! -t 0 ]` guard turns this red again.
W3="$(wiz piped)"
_L="$(_slog)"; ( cd "$W3" && printf 'yes\n' | bash start.sh --generic ) >"$_L" 2>&1 || _evidence "start.sh in $W3" "$_L" $?
[ -d "$W3/.claude" ] || { echo "FAIL: the documented piped install stopped working — a prompt is reading on the non-TTY path"; exit 1; }
echo "[wizard] the piped form still installs: no question reads on the non-TTY path"

# 4 · A .gitignore with no trailing newline must not have its last line joined to the first entry written.
#     The twin is the point: the old `touch` + `echo >>` shape produces `node_modulesdocs/`, which is a
#     silently broken ignore rule rather than a visible error.
W4="$(wiz nonewline)"
printf 'node_modules' > "$W4/.gitignore"          # deliberately no trailing newline
_L="$(_slog)"; ( cd "$W4" && bash start.sh --yes </dev/null ) >"$_L" 2>&1 || _evidence "start.sh in $W4" "$_L" $?
grep -qx 'node_modules' "$W4/.gitignore" || { echo "FAIL: the pre-existing entry was joined to an added one"; exit 1; }
! grep -q 'node_modules[^$]' "$W4/.gitignore" || { echo "FAIL: an added entry ran onto the last existing line"; exit 1; }
printf 'node_modules' > "$W4/gi.twin"; printf '%s\n' 'docs/' >> "$W4/gi.twin"
grep -q '^node_modulesdocs/$' "$W4/gi.twin" \
  || { echo "FAIL: the must-fail twin did not reproduce the join, so case 4 proves nothing"; exit 1; }
echo "[wizard] .gitignore without a trailing newline keeps its last line intact (twin reproduces the join)"

# 7 · The summary has to NAME the lines it will write. Before this, the user confirmed an install and silently
#     received four .gitignore entries, two of which (CLAUDE.md, docs/) are project-visible paths.
grep -q '\.gitignore' "$W/out.txt" || { echo "FAIL: the install summary never mentions .gitignore"; exit 1; }
for e in 'docs/' '.claude/' 'CLAUDE.md'; do
  grep -qF "$e" "$W/out.txt" || { echo "FAIL: the summary does not list the .gitignore entry '$e' it writes"; exit 1; }
  grep -qxF "$e" "$W/.gitignore" || { echo "FAIL: '$e' was announced but not written"; exit 1; }
done
echo "[wizard] the summary lists every .gitignore line it writes, and writes every line it lists"

# 9,10,11 · docs/ IS THE PRIVACY CASE, and it has two halves that pull against each other: the working
#     documents must be ignored, and the adoption's OWN record must still reach the review diff. Ignoring
#     docs/ without forcing those two files back in is the defect CHANGELOG.md:3328 already records.
DP="$WORK/wiz-adopt-docs"; rm -rf "$DP"; mkdir -p "$DP"
( cd "$DP" && git init -q . && git config user.email t@e.com && git config user.name t \
  && printf '{"name":"x"}\n' > package.json && git add package.json && git commit -qm base )
cp adopt.sh "$DP/"; cp -R claude-starter "$DP/claude-starter"; cp VERSION "$DP/"
_L="$(_slog)"; ( cd "$DP" && bash adopt.sh --here --yes </dev/null ) >"$_L" 2>&1 || _evidence "adopt.sh in $DP" "$_L" $?
( cd "$DP" && git diff --cached --name-only | grep -q '^docs/HANDOVER\.md$' ) \
  || { echo "FAIL: the adoption's own HANDOVER is not in the review diff"; exit 1; }
( cd "$DP" && git diff --cached --name-only | grep -q '^docs/adr/' ) \
  || { echo "FAIL: the adoption's own ADR is not in the review diff"; exit 1; }
( cd "$DP" && : > docs/PLAN.md && git check-ignore -q docs/PLAN.md ) \
  || { echo "FAIL: docs/PLAN.md is NOT ignored after adopt — internal plans would reach a shared repo"; exit 1; }
( cd "$DP" && : > docs/SECURITY_FINDINGS.md && git check-ignore -q docs/SECURITY_FINDINGS.md ) \
  || { echo "FAIL: docs/SECURITY_FINDINGS.md is NOT ignored after adopt"; exit 1; }
# The twin for the half that is easy to lose: with docs/ ignored, a plain `git add docs` stages nothing, so
# dropping the -f would silently remove the adoption from its own review.
( cd "$DP" && git rm -q --cached docs/HANDOVER.md docs/adr/*.md >/dev/null 2>&1; git add docs >/dev/null 2>&1; \
  [ -z "$(git diff --cached --name-only -- docs)" ] ) \
  || { echo "FAIL: the twin did not reproduce the drop, so the -f above proves nothing"; exit 1; }
echo "[wizard] docs/ is private after adopt, and the adoption's own record is still in the diff (twin drops it)"

# 6 · --shared and --private differ in WHAT they ignore, which is the whole point of asking. shared keeps
#     .claude/ and CLAUDE.md committable so a team can review them; private hides them. Both are asserted,
#     because a default that silently matched the other choice would make the question decorative.
W5="$(wiz shared)"
_L="$(_slog)"; ( cd "$W5" && CSK_LANG=en bash start.sh --yes --shared </dev/null ) >"$_L" 2>&1 || _evidence "start.sh in $W5" "$_L" $?
for e in 'docs/' '.private-terms.txt'; do
  grep -qxF "$e" "$W5/.gitignore" || { echo "FAIL: --shared did not ignore '$e'"; exit 1; }
done
for e in '.claude/' 'CLAUDE.md'; do
  ! grep -qxF "$e" "$W5/.gitignore" || { echo "FAIL: --shared ignored '$e' — the team could not review it"; exit 1; }
done
grep -qxF '.claude/' "$W/.gitignore" || { echo "FAIL: the private default did not ignore .claude/"; exit 1; }
echo "[wizard] --shared ignores 2 entries and keeps .claude/ + CLAUDE.md committable; private ignores 4"

# 5 · ASK GIT, DO NOT COMPARE STRINGS. A repo that already ignores `.claude` without the trailing slash is
#     covered, and appending `.claude/` next to it is a second redundant rule. The old whole-line grep could
#     not see that; `git check-ignore` answers the question that matters. Needs a real repo, since that is
#     what makes check-ignore answerable at all.
W6="$WORK/wiz-dupe"; rm -rf "$W6"; mkdir -p "$W6"
cp start.sh "$W6/"; cp -R claude-starter "$W6/"
( cd "$W6" && git init -q . && git config user.email t@e.com && git config user.name t )
printf '.claude\n' > "$W6/.gitignore"                  # no trailing slash, and already effective
_L="$(_slog)"; ( cd "$W6" && CSK_LANG=en bash start.sh --yes </dev/null ) >"$_L" 2>&1 || _evidence "start.sh in $W6" "$_L" $?
[ "$(grep -c '^\.claude' "$W6/.gitignore")" = 1 ] \
  || { echo "FAIL: a repo already ignoring .claude got a second redundant rule ($(grep -c '^\.claude' "$W6/.gitignore"))"; exit 1; }
echo "[wizard] an already-ignored .claude is not ignored twice (git check-ignore, not string equality)"

# 8 · The same helper has to work where there is NO repo to ask. Every wizard case above ran outside a repo,
#     so the fallback is already exercised — this asserts it reached the right answer rather than merely not
#     crashing, which is the difference between a fallback and a silent no-op.
[ -f "$W4/.gitignore" ] && [ "$(grep -c . "$W4/.gitignore")" -ge 2 ] \
  || { echo "FAIL: outside a git repo the gitignore fallback wrote nothing usable"; exit 1; }
echo "[wizard] outside a repo the fallback still writes the entries (and keeps the trailing-newline fix)"

# 12 · `hide` writes nothing itself — it hands the user a command to run after the merge, because ignoring the
#      payload BEFORE the branch commit is what once dropped it from the review diff. So what has to be right
#      is the INSTRUCTION, and the instruction is a static string: asserted on the source rather than by
#      driving the interactive flow. The first attempt here did drive it, and the prompt sequence guessed wrong
#      so the path was never reached — a case that reported a skip while measuring nothing. Reading the string
#      is both complete and deterministic, and it is the whole of what `hide` promises.
# Match the ASSIGNMENT THAT CARRIES THE COMMAND, not the first line whose name matches. `HIDE_NOTE=""` is
# declared empty earlier in the file, and `grep -m1 'HIDE_NOTE='` took that one — so all three checks below
# failed against a perfectly good file, and the must-fail twin then "passed" for the wrong reason: it was not
# the mutation failing, it was the assertion already broken. Anchoring on the command itself removes both.
HN="$(grep -m1 'HIDE_NOTE=.*rm -r --cached' adopt.sh || true)"
case "$HN" in
  *'rm -r --cached'*) ;;
  *) echo "FAIL: the hide instruction does not untrack anything"; exit 1 ;;
esac
case "$HN" in
  *'--cached .claude CLAUDE.md docs'*) ;;
  *) echo "FAIL: the hide instruction does not untrack docs — plans and threat models would stay tracked"; exit 1 ;;
esac
case "$HN" in
  *'docs/'*) ;;
  *) echo "FAIL: the hide instruction does not add docs/ to .gitignore"; exit 1 ;;
esac
echo "[wizard] the hide instruction covers docs in BOTH halves (untrack and ignore)"

# 15 · A SHARED install must pin the hooks to LF, and the proof is the conversion not happening — not the
#      file being written. The ROADMAP carried this as an inference ("çıkarım, gözlem değil — patlamadı");
#      it is now measured. Mechanism, reproduced with git settings alone so it does not need Windows:
#        committed blob                      0 CR
#        clone with core.autocrlf=true       1345 CR in guard-bash.sh · 575 in pre-commit
#      Only `autocrlf=true` produces that; `input` and `false` come back clean even unpinned, and `true` is the
#      Git for Windows system default — so this is for the person who changed nothing.
#      WHO IT PROTECTS, corrected after a real Windows run: NOT Git Bash, where a CRLF hook still runs and
#      returns the identical verdict. It is a non-MSYS bash reading the same tree — WSL, which the kit's own
#      .gitattributes names and which is unmeasured by anyone here. What this case pins is narrower and fully
#      measured: with the pin the working tree matches the blob, without it it does not.
#      FIXTURE NOTE for anyone adding a case here: adopt.sh leaves `claude-starter/` in the project, and
#      committing that trips the kit's OWN trace scanner and floor guard (the payload contains the very
#      expressions they block). A fixture that commits after adopt must remove the payload first or it fails
#      for a reason that has nothing to do with what it is testing.
#      The calibration twin is the point: with the pin removed the same round trip must come back dirty, or
#      this case is asserting that a clone is clean for some reason of its own.
_ga_crs() {   # $1 = project dir, $2 = path inside it -> CR count after a core.autocrlf=true checkout
  # NO BARE REPO AND NO BRANCH NAME. The first version pushed to `refs/heads/main` in a fresh bare whose HEAD
  # came from `init.defaultBranch` — so on a desk where that is `main` the clone checked the tree out and on a
  # runner where it is not, the clone checked out NOTHING ("remote HEAD refers to nonexistent ref") and every
  # file read as MISSING. Green on the machine that wrote it, red on all three runners, for a reason that has
  # nothing to do with what the case measures. Cloning the project directly takes its own HEAD, whatever it is
  # called, and the question of branch names disappears.
  # And it reports WHY rather than a word: the first version swallowed every error into MISSING, so a broken
  # fixture came back wearing the product's failure message and sent the search to the installer.
  local p="$1" f="$2" clone="$1.clone"
  rm -rf "$clone"
  ( cd "$p" && git add -A >/dev/null 2>&1 && git commit -qm shared >/dev/null 2>&1 ) || true
  if ! git clone -q -c core.autocrlf=true "$p" "$clone" 2>"$p.clone.err"; then
    echo "FIXTURE: clone of $p failed: $(head -1 "$p.clone.err")"; return 0
  fi
  if [ ! -f "$clone/$f" ]; then
    echo "FIXTURE: $f is not in the clone (tracked files: $(git -C "$clone" ls-files | wc -l | tr -d ' ')) $(head -1 "$p.clone.err")"
    return 0
  fi
  tr -dc '\r' < "$clone/$f" | wc -c | tr -d ' '
}
W15="$(wiz shared-eol)"
( cd "$W15" && git init -q . && git config user.email t@example.invalid && git config user.name t \
    && printf 'x\n' > README.md && git add README.md && git commit -qm base >/dev/null 2>&1 )
_L="$(_slog)"; ( cd "$W15" && printf 'yes\n' | bash start.sh --generic --shared ) >"$_L" 2>&1 || _evidence "start.sh in $W15" "$_L" $?
grep -qF '.claude/**/*.sh text eol=lf' "$W15/.gitattributes" 2>/dev/null \
  || { echo "FAIL: a shared install did not pin .claude/**/*.sh to LF"; exit 1; }
for f in .claude/hooks/guard-bash.sh .claude/hooks/pre-commit; do
  n="$(_ga_crs "$W15" "$f")"
  case "$n" in FIXTURE:*) echo "FAIL: case 15's own fixture broke, not the product — $n"; exit 1 ;; esac
  [ "$n" = 0 ] || { echo "FAIL: $f came back with $n CR from a core.autocrlf=true clone — the pin is not holding"; exit 1; }
done
rm -f "$W15/.gitattributes"
n="$(_ga_crs "$W15" .claude/hooks/guard-bash.sh)"
case "$n" in FIXTURE:*) echo "FAIL: the twin's own fixture broke — $n"; exit 1 ;; esac
[ "$n" != 0 ] \
  || { echo "FAIL: with the pin removed the clone stayed clean ($n CR) — case 15 proves nothing"; exit 1; }
echo "[wizard] a shared install keeps hooks LF through a core.autocrlf clone (twin: $n CR without the pin)"

# 16 · ...and a PRIVATE install must not touch .gitattributes at all. git never checks .claude/ out there, so
#      there is nothing to convert, and writing repo-wide attributes would be editing a file whose owner has
#      no problem to fix. The condition is asked of git (`check-ignore`), not read from the mode variable.
W16="$(wiz private-eol)"
( cd "$W16" && git init -q . && git config user.email t@example.invalid && git config user.name t \
    && printf 'x\n' > README.md && git add README.md && git commit -qm base >/dev/null 2>&1 )
_L="$(_slog)"; ( cd "$W16" && printf 'yes\n' | bash start.sh --generic --private ) >"$_L" 2>&1 || _evidence "start.sh in $W16" "$_L" $?
[ ! -e "$W16/.gitattributes" ] \
  || { echo "FAIL: a private install wrote .gitattributes, which it has no reason to touch"; exit 1; }
echo "[wizard] a private install leaves .gitattributes alone"

# 17 · A project that ALREADY answers lf for those paths gets nothing appended. The question is asked of git,
#      so any pattern spelling counts — `* text eol=lf` here, which no literal grep would have recognised.
W17="$(wiz already-eol)"
( cd "$W17" && git init -q . && git config user.email t@example.invalid && git config user.name t \
    && printf '* text eol=lf\n' > .gitattributes && git add .gitattributes && git commit -qm ga >/dev/null 2>&1 )
_L="$(_slog)"; ( cd "$W17" && printf 'yes\n' | bash start.sh --generic --shared ) >"$_L" 2>&1 || _evidence "start.sh in $W17" "$_L" $?
[ "$(wc -l < "$W17/.gitattributes" | tr -d ' ')" = 1 ] \
  || { echo "FAIL: an existing eol rule was not recognised; the installer appended redundant pins"; exit 1; }
echo "[wizard] an existing eol rule is recognised, whatever its spelling, and nothing is appended"

# 18 · A Turkish install prints no English sentence. The i18n audit only checks the rows that EXIST in the
#      table; a line that never went through m() is invisible to it — which is how the DevArchitecture prompt,
#      the CLAUDE.md branches and a whole warning block shipped in English under --lang tr. So this asks the
#      output instead: English function words, matched case-sensitively as whole words (Turkish "Not:" is a
#      word, "not" is not). Both backend paths run, because the DevArchitecture block only prints on one.
#      CALIBRATED in-line: the same run in English must hit, or the detector is broken, not the product.
_en_words(){ grep -cwE 'the|and|is|are|to|of|with|will|your|this|not|be|has|was|for' "$1" || true; }
for _shape in "dotnet|evet\nhayır\n" "generic|evet\n"; do
  _stk="${_shape%%|*}"; _inp="${_shape#*|}"
  for _lg in tr en; do
    W18="$(wiz "lang-$_stk-$_lg")"
    _L="$(_slog)"; ( cd "$W18" && printf "$_inp" | NO_COLOR=1 bash start.sh "--$_stk" --lang "$_lg" ) >"$_L" 2>&1 \
      || _evidence "start.sh --lang $_lg in $W18" "$_L" $?
    cp "$_L" "$W18/out-$_lg.txt"
  done
  _n_en="$(_en_words "$W18/out-en.txt")"; W18tr="$WORK/wiz-lang-$_stk-tr"
  [ "$_n_en" -gt 0 ] || { echo "FAIL: FIXTURE — the English $_stk run matched 0 function words; the detector is broken, not the product"; exit 1; }
  [ -d "$W18tr/.claude" ] || { echo "FAIL: the Turkish $_stk install did not complete"; exit 1; }
  _n_tr="$(_en_words "$W18tr/out-tr.txt")"
  [ "$_n_tr" = 0 ] || { echo "FAIL: --lang tr ($_stk) printed $_n_tr English line(s):" >&2
                        grep -wE 'the|and|is|are|to|of|with|will|your|this|not|be|has|was|for' "$W18tr/out-tr.txt" | sed 's/^/    | /' >&2; exit 1; }
  echo "[wizard] --lang tr ($_stk): 0 English lines (calibration: the English run matched $_n_en)"
done
# ...and adopt.sh, twice per language: the first adoption and the refresh print different blocks.
for _lg in tr en; do
  W18a="$WORK/adopt-lang-$_lg"; rm -rf "$W18a"; mkdir -p "$W18a"
  ( cd "$W18a" && git init -q . && git config user.email t@example.invalid && git config user.name t \
      && printf '{"name":"x"}\n' > package.json && git add -A && git commit -qm init >/dev/null 2>&1 )
  : > "$W18a/out.txt"
  for _pass in 1 2; do
    cp adopt.sh VERSION "$W18a/"; cp -R claude-starter "$W18a/"
    _L="$(_slog)"; ( cd "$W18a" && NO_COLOR=1 bash adopt.sh --lang "$_lg" --yes </dev/null ) >"$_L" 2>&1 \
      || _evidence "adopt.sh --lang $_lg (pass $_pass) in $W18a" "$_L" $?
    cat "$_L" >> "$W18a/out.txt"
  done
done
_n_en="$(_en_words "$WORK/adopt-lang-en/out.txt")"
[ "$_n_en" -gt 0 ] || { echo "FAIL: FIXTURE — the English adopt run matched 0 function words; the detector is broken, not the product"; exit 1; }
_n_tr="$(_en_words "$WORK/adopt-lang-tr/out.txt")"
[ "$_n_tr" = 0 ] || { echo "FAIL: adopt.sh --lang tr printed $_n_tr English line(s):" >&2
                      grep -wE 'the|and|is|are|to|of|with|will|your|this|not|be|has|was|for' "$WORK/adopt-lang-tr/out.txt" | sed 's/^/    | /' >&2; exit 1; }
echo "[wizard] adopt.sh --lang tr (adopt + refresh): 0 English lines (calibration: the English run matched $_n_en)"

echo "e2e: all installer rehearsals passed"
