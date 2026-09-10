#!/usr/bin/env bash
# Does installing this kit measurably change what the model does? A/B, graded on artifacts.
#
# Everything else in this repo checks that the kit is well-FORMED — components route, counts match, hooks fire
# on fixtures. None of it checks that the kit WORKS, and "the agents feel better" is not a measurement. This
# runs the same prompt twice: once in a project with the kit installed, once in a bare one, and grades what is
# left on disk afterwards.
#
# Two rules this harness exists to enforce on itself:
#
#   GRADE THE ARTIFACT, NEVER THE TRANSCRIPT. An early hand-rolled attempt false-failed because the model's own
#   commentary ("I left out the co-author trailer per §4.1") contained the very words the grader was grepping
#   for. Graders here read git state and file contents. What the model SAYS it did is not evidence.
#
#   BOTH ARMS GET THE SAME TOOL ACCESS. Otherwise the bare arm fails for permission reasons and the delta
#   measures the harness, not the kit. Both run with identical flags; the only difference is whether .claude/
#   and CLAUDE.md exist.
#
# `claude plugin eval --ablation with-without` is the purpose-built version of this and would replace most of
# the file — still early access as of CLI 2.1.220 (2026-07-29). Re-check with `claude plugin eval .`; when it
# opens, keep the cases and graders and drop the runner.
#
# COSTS REAL TOKENS. Never wired into smoke-test, routing-eval or CI — those must stay hermetic and free. Run
# it deliberately.
#
# Usage:
#   bash evals/run.sh                       # every case, 1 run per arm
#   bash evals/run.sh --runs 3              # 3 runs per arm (nondeterminism is real; 1 run is an anecdote)
#   CSK_EVAL_TRACE=1 bash evals/run.sh      # also capture the event stream: main-thread delegations, cost and tokens per arm
#   CSK_EVAL_ARMS="kit kitb" CSK_EVAL_DISCIPLINE_B=<a CLAUDE.md with the sentinel> CSK_EVAL_TRACE=1 bash evals/run.sh --runs 3
#                                           # same install in both arms, only the discipline text differs: measures a RULE
#   CSK_EVAL_CASES=<dir>                    # run cases from another directory (a draft set, before it lands here)
#   CSK_EVAL_OVERLAY_B=<dir>                # arm kitb only: files that REPLACE installed ones, mirrored under .claude/
#
# stdin is /dev/null for every run: without it the CLI waits 3 s for piped input it will never get, and says so.
#   bash evals/run.sh --case secret-refused # one case
#   bash evals/run.sh --keep                # keep the scratch projects for inspection
#
# A case may declare REQUIRES="tool ..." in its case.env; when one is missing the case is skipped before anything is built.
#
# Exit 0 the report printed · 1 a case is malformed or the CLI is unusable · 3 INCOMPLETE: a run was not measured (a usage
# limit, a stream that ended in an error, or a case skipped for a missing tool), so the totals printed are not a result.
set -uo pipefail
ROOT="${CSK_EVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CASES="${CSK_EVAL_CASES:-$ROOT/evals/cases}"

RUNS=1; ONLY=""; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="${2:-1}"; shift 2 ;;
    --case) ONLY="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d'; exit 0 ;;   # the whole header, not a line count that drifts
    *) echo "run.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v claude >/dev/null 2>&1 || { echo "run.sh: the claude CLI is not on PATH" >&2; exit 1; }
MODEL="$(claude --version 2>/dev/null | head -1)"

# Where the scratch projects live matters more than it looks: Claude Code trusts a workspace per path, and an
# untrusted one silently drops the `permissions.allow` entry the kit ships. Override with CSK_EVAL_WORK to run
# somewhere already trusted.
# A failed mktemp used to leave WORK EMPTY and the run carried on regardless, so every path became "/<case>-kit-1"
# and the runner started creating scratch projects at the FILESYSTEM ROOT. It only looked harmless because macOS
# mounts / read-only; anywhere else it would have scattered directories across the root and then `rm -rf` them on
# exit. A missing CSK_EVAL_WORK is a typo, not a reason to write to /.
WORKBASE="${CSK_EVAL_WORK:-${TMPDIR:-/tmp}}"
[ -d "$WORKBASE" ] || { echo "run.sh: work dir '$WORKBASE' does not exist (CSK_EVAL_WORK) — create it or unset the variable" >&2; exit 2; }
WORK="$(mktemp -d "$WORKBASE/csk-eval.XXXXXX")" || { echo "run.sh: could not create a scratch dir under '$WORKBASE'" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "run.sh: scratch dir is empty/missing — refusing to run" >&2; exit 2; }
trap '[ "$KEEP" = 1 ] && echo "scratch kept: $WORK" || rm -rf "$WORK"' EXIT

# build_project <dir> <arm>  — identical seed in both arms; the kit is the only variable.
build_project() {
  local dir="$1" arm="$2"
  mkdir -p "$dir" || { echo "run.sh: cannot create '$dir'" >&2; return 1; }
  # `cd` MUST be fatal here. It used to sit on its own line, so a failed cd printed an error and the subshell
  # carried straight on IN THE CALLER'S DIRECTORY — which is the kit repo. That is not theoretical: an unset
  # scratch path made this run `git init`, `git config user.email eval@example.invalid`, the case's `seed`
  # (which overwrites README.md) and finally `git add -A && git commit` against the repo itself, committing a
  # working tree of real work under the message "seed". Nothing here may run outside the scratch project.
  ( cd "$dir" || exit 1
    git init -q
    git config user.email eval@example.invalid
    git config user.name  "Eval Runner"
    git config commit.gpgsign false
    seed                                            # case-supplied, runs in the project dir
    git add -A >/dev/null 2>&1
    git commit -q -m "seed" >/dev/null 2>&1
    # Optional, runs AFTER the seed commit: the only way a case can start with something UNTRACKED, which some
    # behaviours (anything about cleaning a working tree) cannot be posed without.
    command -v post_seed >/dev/null 2>&1 && post_seed
  )
  if [ "$arm" = kit ] || [ "$arm" = kitb ]; then
    cp "$ROOT/start.sh" "$dir/"; cp -R "$ROOT/claude-starter" "$dir/"
    ( cd "$dir" && printf 'yes\n' | bash start.sh --fullstack --generic >/dev/null 2>&1 )
    # A bare-arm project has no .claude/, so a leftover installer would be a second difference between the
    # arms. It removes itself on success; make sure.
    rm -f "$dir/start.sh"; rm -rf "$dir/claude-starter"
    [ -d "$dir/.claude" ] || { echo "run.sh: install failed in $dir" >&2; return 1; }
    # Arm kitb: the same install with ONE difference, the discipline half of CSK_EVAL_DISCIPLINE_B. That makes the
    # discipline text the only variable between kit and kitb, which is what a rule change has to be measured on.
    if [ "$arm" = kitb ]; then
      [ -f "${CSK_EVAL_DISCIPLINE_B:-}" ] || { echo "run.sh: arm kitb needs CSK_EVAL_DISCIPLINE_B=<a CLAUDE.md with the sentinel>" >&2; return 1; }
      grep -qE '^<!-- KIT:DISCIPLINE-END' "$CSK_EVAL_DISCIPLINE_B" || { echo "run.sh: CSK_EVAL_DISCIPLINE_B has no '<!-- KIT:DISCIPLINE-END' sentinel" >&2; return 1; }
      awk '/^<!-- KIT:DISCIPLINE-END/{exit} {print}' "$CSK_EVAL_DISCIPLINE_B" > "$dir/.claude/DISCIPLINE.md"
    fi
    # CSK_EVAL_OVERLAY_B carries the half of a rule that does not live in the discipline file: agent definitions. A path the
    # install did not create is refused, not added — a typo would ship a file nobody reads, and the arm would measure the
    # unchanged kit under a new name.
    if [ "$arm" = kitb ] && [ -n "${CSK_EVAL_OVERLAY_B:-}" ]; then
      [ -d "$CSK_EVAL_OVERLAY_B" ] || { echo "run.sh: CSK_EVAL_OVERLAY_B='$CSK_EVAL_OVERLAY_B' is not a directory" >&2; return 1; }
      local rel applied=0
      while IFS= read -r rel; do
        [ -f "$dir/.claude/$rel" ] || { echo "run.sh: overlay file '$rel' replaces nothing under .claude/ — refusing to add it" >&2; return 1; }
        cp "$CSK_EVAL_OVERLAY_B/$rel" "$dir/.claude/$rel" && applied=$((applied+1))
      done < <(cd "$CSK_EVAL_OVERLAY_B" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
      [ "$applied" -gt 0 ] || { echo "run.sh: CSK_EVAL_OVERLAY_B='$CSK_EVAL_OVERLAY_B' is empty" >&2; return 1; }
    fi
  fi
}

# run_arm <dir> <arm> — same flags both sides. The kit arm additionally gets CLAUDE_GIT_OK when the case needs
# a commit to actually land: §4.4 gates the git TOOL behind human approval, which headless cannot answer, and
# without the documented escape the kit arm would be unable to commit for reasons that have nothing to do with
# the behaviour under test. The content gates (trace/secret pre-commit) still run — that is the point.
# eval_trace_metrics <stream.jsonl> <stdout.txt> — one TSV line:
#   agent_top agent_all spawned cost in out cache_read cache_create turns bad_lines has_result tests tests_nested turns_top turns_nested is_error limited final_tested
# The last four were appended, not inserted, so every earlier column keeps its position. `tests` counts Bash calls that run a test
# runner or a build/lint tool — main thread and subagents alike, since the stream carries both — deduplicated by tool_use id. The bare
# word "test" is deliberately not a match: measured on real transcripts, the calls it caught alone were echo banners, not runs.
# agent_top counts Agent/Task calls made by the MAIN thread (no parent_tool_use_id); agent_all includes nested ones.
# has_result=0 means the stream is empty or broken: that run says nothing about delegation and must not be counted.
# is_error=1 and limited=1 mean the same thing for a stream that DID end in a result. A usage-limit rejection is exactly that: a
# result event with subtype success, is_error true and api_error_status 429, preceded by a rate_limit_event whose status is
# "rejected". Measured: a 9-session run hit the five-hour limit in its 2nd session and the next 7 returned in ~0.6 s each, with
# a result event and no tool call. has_result alone counted all of them, and the grader scored 7 untouched projects.
# final_tested: 1 when a test/build run comes after the last Edit/Write, in stream order across the main thread and subagents; 0 when
# it does not; empty when nothing was edited. A change that cuts test runs must not cut this one — it is the run that says the code
# that was left behind works. File edits made through Bash (sed -i, redirection) are not seen.
eval_trace_metrics() {
  python3 - "$1" "$2" <<'PYM'
import json, sys, re
src, txt = sys.argv[1], sys.argv[2]
RUNRX = re.compile(r'(^|[\s;&|(])(pytest|jest|vitest|mocha|make|mvn|gradle|tsc|eslint|ruff|flake8|mypy)\b|(dotnet|go|cargo)\s+(test|build)\b|(npm|pnpm|yarn)\s+(run\s+)?(test|build|lint)\b|\bnode\s+--test\b')
top = allc = bad = limited = 0; res = None
tests = tnest = 0; seen_tu = set(); msgs_top = set(); msgs_nest = set(); k = last_edit = last_test = edits = 0
try: lines = open(src, errors='replace').read().splitlines()
except OSError: lines = []
for line in lines:
    line = line.strip()
    if not line: continue
    try: e = json.loads(line)
    except Exception: bad += 1; continue
    if e.get('type') == 'assistant':
        m = e.get('message') or {}; nested = bool(e.get('parent_tool_use_id'))
        if m.get('id'): (msgs_nest if nested else msgs_top).add(m.get('id'))
        for c in m.get('content') or []:
            if not (isinstance(c, dict) and c.get('type') == 'tool_use') or c.get('id') in seen_tu: continue
            seen_tu.add(c.get('id')); k += 1
            if c.get('name') in ('Agent', 'Task'):
                allc += 1
                if not nested: top += 1
            elif c.get('name') in ('Edit', 'Write', 'MultiEdit', 'NotebookEdit'):
                edits += 1; last_edit = k
            elif c.get('name') == 'Bash' and RUNRX.search((c.get('input') or {}).get('command') or ''):
                tests += 1; last_test = k
                if nested: tnest += 1
    elif e.get('type') == 'rate_limit_event':
        if (e.get('rate_limit_info') or {}).get('status') == 'rejected': limited = 1
    elif e.get('type') == 'result':
        res = e
open(txt, 'w').write((res or {}).get('result') or '')
u = (res or {}).get('usage') or {}
sp = ((res or {}).get('subagent_stats') or {}).get('spawned', '')
print('\t'.join(str(x) for x in (top, allc, sp, (res or {}).get('total_cost_usd', ''), u.get('input_tokens', ''),
      u.get('output_tokens', ''), u.get('cache_read_input_tokens', ''), u.get('cache_creation_input_tokens', ''),
      (res or {}).get('num_turns', ''), bad, 1 if res else 0, tests, tnest, len(msgs_top), len(msgs_nest),
      1 if (res or {}).get('is_error') else 0, 1 if limited or (res or {}).get('api_error_status') == 429 else 0,
      '' if not edits else (1 if last_test > last_edit else 0))))
PYM
}

run_arm() {
  local dir="$1" arm="$2"
  local env_prefix=""
  { [ "$arm" = kit ] || [ "$arm" = kitb ]; } && [ "${NEEDS_GIT_OK:-0}" = 1 ] && env_prefix="CLAUDE_GIT_OK=1"
  # Both arms run with the permission LAYER out of the way, deliberately. What is under test here is what the
  # kit does to the model's output — commit shape, how a credential is handled — not whether the approval
  # prompt fires; that is a permission-layer contract, unit-tested in smoke-test §7 where it can be asserted
  # exactly rather than inferred from a headless denial. Leaving the prompt in play measured neither: the kit
  # arm simply stopped every run with "denied at the permission layer", which grades the absence of a human,
  # not the presence of a discipline. The git-hook gates (trace, secret) are unaffected by permission mode and
  # still run — those ARE part of what is being measured.
  # `Task`/`Agent` are in the default tool list DELIBERATELY, and their absence was a real defect: without them the
# kit arm cannot delegate at all, so every result this harness produced measured the discipline TEXT with the agent
# layer switched off — while the kit's central claim is the agent layer. Both arms get them (a bare project has no
# agents, so it simply never uses them, and the arms stay identical in tool access).
# Override with CSK_EVAL_PERM if your environment refuses the default.
  # CSK_GATE_LOG turns on the hooks' write-only observability channel (see claude-starter/hooks/guard-bash.sh).
  # It exists because "the model never reached for the command" and "the gate stopped it" leave behind IDENTICAL
  # artifacts: permission-pressure had to report "guard-bash never fired" as an inference, and that inference is
  # the difference between evidence for the always-on discipline TEXT and evidence for the GATE. Set in both arms
  # so they stay identical in environment; the bare arm has no hooks, so its log simply never appears.
  ( cd "$dir" || exit 1
    if [ "${CSK_EVAL_TRACE:-0}" = 1 ]; then
      # Delegation and tokens are invisible in text output. The event stream carries both; the reply text is
      # re-derived into .eval-stdout.txt so anything reading it sees the same thing as before.
      env $env_prefix CSK_GATE_LOG="$dir/.eval-gates.log" claude -p "$PROMPT" --output-format stream-json --verbose \
          --permission-mode "${CSK_EVAL_PERM:-bypassPermissions}" \
          --allowedTools ${CSK_EVAL_TOOLS:-Bash Read Write Edit Task Agent} \
          </dev/null >"$dir/.eval-stream.jsonl" 2>"$dir/.eval-stderr.txt"
      eval_trace_metrics "$dir/.eval-stream.jsonl" "$dir/.eval-stdout.txt" > "$dir/.eval-metrics.tsv"
    else
      env $env_prefix CSK_GATE_LOG="$dir/.eval-gates.log" claude -p "$PROMPT" \
          --permission-mode "${CSK_EVAL_PERM:-bypassPermissions}" \
          --allowedTools ${CSK_EVAL_TOOLS:-Bash Read Write Edit Task Agent} \
          </dev/null >"$dir/.eval-stdout.txt" 2>"$dir/.eval-stderr.txt"
    fi
  ) || true   # a non-zero exit is itself a result; the grader decides
}

# Arms come from CSK_EVAL_ARMS (default "kit bare"). The totals below were written for exactly those two and filed
# every non-kit arm under "bare": a kit-vs-kitb run would have printed kitb's score as bare's and dropped kitb's checks.
ARMS="${CSK_EVAL_ARMS:-kit bare}"; ARM_A="${ARMS%% *}"; ARM_B=""; [ "$ARMS" != "$ARM_A" ] && ARM_B="${ARMS#* }"; ARM_B="${ARM_B%% *}"
printf '== kit A/B eval ==  %s · %s runs/arm · arms: %s\n\n' "$MODEL" "$RUNS" "$ARMS"
[ -d "$CASES" ] || { echo "run.sh: no cases under evals/cases" >&2; exit 1; }

TOTAL_KIT=0; TOTAL_BARE=0; TOTAL_CHECKS=0; TOTAL_CHECKS_B=0; NOT_MEASURED=0; LIMITED=0; SKIPPED=0
for cdir in "$CASES"/*/; do
  [ "$LIMITED" = 1 ] && break
  cname="$(basename "$cdir")"
  [ -n "$ONLY" ] && [ "$ONLY" != "$cname" ] && continue
  [ -f "$cdir/case.env" ] && [ -f "$cdir/grade.sh" ] || { echo "run.sh: $cname is missing case.env or grade.sh" >&2; exit 1; }

  # shellcheck disable=SC1090
  NEEDS_GIT_OK=0; REQUIRES=""; unset -f seed post_seed 2>/dev/null; . "$cdir/case.env"
  echo "-- $cname --"
  [ -n "${DESC:-}" ] && echo "   $DESC"
  # A case whose grader needs a tool this machine lacks is skipped BEFORE anything is built or paid for. Run anyway, it
  # fails in every arm for a reason that has nothing to do with the kit, and a tie of failures reads like a result.
  missing=""; for t in $REQUIRES; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    printf '   ! SKIPPED, NOT MEASURED — needs%s, not on PATH; nothing was built or run\n\n' "$missing"
    SKIPPED=$((SKIPPED+1)); continue
  fi

  for arm in $ARMS; do
    [ "$LIMITED" = 1 ] && break
    passed=0; checks=0; detail=""; gates=""; arm_nm=0; arm_graded=0
    for r in $(seq 1 "$RUNS"); do
      [ "$LIMITED" = 1 ] && break
      P="$WORK/$cname-$arm-$r"
      # A failed install must never degrade into "the kit arm behaved like the bare one" — that is the single
      # result this harness could produce that looks like a finding and is actually a bug in itself.
      build_project "$P" "$arm" || { echo "run.sh: could not build $cname/$arm run $r — aborting" >&2; exit 1; }
      run_arm "$P" "$arm"
      # An arm that could not use its tools produces the same shape of result as an arm that chose not to act,
      # and the second reads like a finding. Surface the environment instead of scoring it.
      # SCOPE, MEASURED (2026-07-31), because the earlier wording was broad enough to make every result under it
      # look doubtful. An untrusted workspace drops `permissions.allow` entries AND NOTHING ELSE: a probe project
      # carrying both an allow entry and a PreToolUse hook produced this exact warning, and the hook still ran and
      # still returned exit 2 (the tool did not execute). So the GATES are armed in an untrusted scratch project
      # and a gate result measured there is valid. What is genuinely lost is any case that depends on a
      # pre-approved permission — see evals/README.md on commit-format and secret-refused.
      if { [ "$arm" = kit ] || [ "$arm" = kitb ]; } && grep -q "has not been trusted" "$P/.eval-stderr.txt" 2>/dev/null; then
        echo "   ! workspace untrusted: permissions.allow was dropped for this run (hooks/gates are NOT affected)." >&2
        echo "     Only matters for cases needing a pre-approved permission. Re-run with CSK_EVAL_WORK=<a trusted path>," >&2
        echo "     or trust $P once interactively." >&2
      fi
      # A run that never happened must not be graded. A usage-limit rejection leaves the seed project untouched, and an
      # untouched project passes every "was not changed" check: measured, 7 rejected runs scored 2 checks each. So a run is
      # graded only on evidence that it ran. In trace mode that is a result that is neither an error nor limited. Without the
      # stream it is a reply that is not the limit message, in the one form seen so far, the result text of a rejected run:
      # "You've hit your session limit · resets …".
      nm=""
      if [ "${CSK_EVAL_TRACE:-0}" = 1 ]; then
        m_has=""; m_err=""; m_lim=""
        read -r m_has m_err m_lim < <(LC_ALL=C awk -F'\t' '{print ($11==""?0:$11), ($16==""?0:$16), ($17==""?0:$17)}' "$P/.eval-metrics.tsv" 2>/dev/null)
        if [ "${m_has:-0}" != 1 ]; then nm="the stream is empty or broken"
        elif [ "${m_err:-0}" = 1 ] || [ "${m_lim:-0}" = 1 ]; then
          nm="the run ended in an error or hit the usage limit: $(head -1 "$P/.eval-stdout.txt" 2>/dev/null | cut -c1-160)"
        fi
        [ "${m_lim:-0}" = 1 ] && LIMITED=1
      elif head -1 "$P/.eval-stdout.txt" 2>/dev/null | grep -qiE "^you.ve hit your .*limit"; then
        nm="$(head -1 "$P/.eval-stdout.txt" | cut -c1-160)"; LIMITED=1
      fi
      if [ -n "$nm" ]; then
        NOT_MEASURED=$((NOT_MEASURED+1)); arm_nm=$((arm_nm+1))
        printf '   ! %s run %s NOT MEASURED, not graded — %s\n' "$arm" "$r" "$nm"
        [ -s "$P/.eval-metrics.tsv" ] && cat "$P/.eval-metrics.tsv" >> "$WORK/trace-$cname-$arm.tsv"
        [ "$LIMITED" = 1 ] && { printf '   ! usage limit reached — no further run is started\n'; break; }
        continue
      fi
      arm_graded=$((arm_graded+1))
      # KIT_ROOT lets a grader reuse the kit's own pattern files. It must come from the RUNNER, not be
      # discovered inside the project: the bare arm has no .claude/, so a grader that looked there would score
      # "cannot grade" as a failure and quietly penalise the arm for being the control.
      out="$( cd "$P" && KIT_ROOT="$ROOT" EVAL_SECRET="${EVAL_SECRET:-}" bash "$cdir/grade.sh" 2>/dev/null )"
      checks=$(( checks + $(printf '%s\n' "$out" | grep -c '^\(PASS\|FAIL\) ') ))
      passed=$(( passed + $(printf '%s\n' "$out" | grep -c '^PASS ') ))
      # Every run's lines are kept, not just the first. With --runs 3 the totals are the only thing that
      # matters and a single sample cannot explain them: a 7/9 against a 9/9 is unreadable without knowing
      # WHICH check failed and how often.
      detail="$(printf '%s\n%s' "$detail" "$out")"
      # REPORTED, NEVER SCORED. A channel only the kit arm can produce cannot enter the denominator without
      # handing the kit points the control is structurally unable to earn — the same bias that had to be fixed
      # in adr-recorded and no-secret-logging. It answers a different question from the grade: WHO produced the
      # outcome. A case the kit wins with an empty gate log is evidence for the discipline text; the same win
      # with a BLOCK line in it is the first direct evidence for "rule -> gate".
      [ -s "$P/.eval-gates.log" ] && gates="$(printf '%s\n%s' "$gates" "$(cut -f1,2,3 "$P/.eval-gates.log")")"
      [ -s "$P/.eval-metrics.tsv" ] && cat "$P/.eval-metrics.tsv" >> "$WORK/trace-$cname-$arm.tsv"
    done
    if [ "${CSK_EVAL_TRACE:-0}" = 1 ]; then
      LC_ALL=C awk -F'\t' -v arm="$arm" '
        { n++; if ($11 != 1 || $16 == 1 || $17 == 1) { empty++; next } ok++; if ($1 > 0) deleg++; cost += $4; tin += $5; tout += $6; cr += $7; cc += $8; tst += $12; tsn += $13; ttop += $14; tnst += $15 }
        END {
          if (n == 0) { printf "     trace %-5s NO TRACE FILE — the runs wrote no metrics; this measured nothing\n", arm; exit }
          printf "     trace %-5s delegated %d/%d · cost $%.3f · in %d out %d cache_read %d cache_create %d · test runs %d (nested %d) · turns %d (nested %d)", arm, deleg, ok, cost, tin, tout, cr, cc, tst, tsn, ttop, tnst
          if (empty) printf " · %d EMPTY/BROKEN/ERROR stream(s), not counted", empty
          printf "\n"
        }' "$WORK/trace-$cname-$arm.tsv" 2>/dev/null || printf '     trace %-5s NO TRACE FILE — the runs wrote no metrics; this measured nothing\n' "$arm"
    fi
    if [ "$arm" = "$ARM_A" ]; then TOTAL_KIT=$((TOTAL_KIT+passed)); TOTAL_CHECKS=$((TOTAL_CHECKS+checks));
    elif [ "$arm" = "$ARM_B" ]; then TOTAL_BARE=$((TOTAL_BARE+passed)); TOTAL_CHECKS_B=$((TOTAL_CHECKS_B+checks)); fi
    printf '   %-5s %s/%s checks' "$arm" "$passed" "$checks"
    if [ "$arm_graded" -lt "$RUNS" ]; then printf ' (%s of %s runs graded · %s NOT MEASURED)' "$arm_graded" "$RUNS" "$arm_nm"
    elif [ "$RUNS" -gt 1 ]; then printf ' (over %s runs)' "$RUNS"; fi
    printf '\n'
    # Tally each distinct check across the runs instead of printing them N times.
    printf '%s\n' "$detail" | grep -E '^(PASS|FAIL) ' \
      | awk '{v=$1; $1=""; c[$0]=c[$0]; if(v=="PASS") p[$0]++; n[$0]++}
             END{for(k in n) printf "         %s/%s %s\n", p[k]+0, n[k], substr(k,2)}' | sort -t/ -k1,1n
    # Diagnosis line, printed outside the score. "none" in the kit arm means the model never attempted a gated
    # command — which is a result about the discipline text, not about the gate, and must not be read as either
    # one working. The bare arm has no hooks and prints nothing at all; its silence is the absence of a gate.
    if [ "$arm" != bare ]; then
      if [ -n "$gates" ]; then
        printf '         gates fired:\n'
        printf '%s\n' "$gates" | grep -E '^(BLOCK|ASK|ALLOW)' | sort | uniq -c \
          | awk '{c=$1; $1=""; printf "           %sx%s\n", c, $0}'
      else
        printf '         gates fired: none — no gated command was attempted in any run\n'
      fi
    fi
  done
  echo
done

echo "== summary =="
printf '   %-4s %s/%s\n' "$ARM_A" "$TOTAL_KIT" "$TOTAL_CHECKS"
[ -n "$ARM_B" ] && printf '   %-4s %s/%s\n' "$ARM_B" "$TOTAL_BARE" "$TOTAL_CHECKS_B"
if [ -n "$ARM_B" ] && [ "$TOTAL_CHECKS" -gt 0 ] && [ "$NOT_MEASURED" = 0 ] && [ "$LIMITED" = 0 ] && [ "$SKIPPED" = 0 ]; then
  printf '   delta %s - %s: %+d checks\n' "$ARM_A" "$ARM_B" "$((TOTAL_KIT - TOTAL_BARE))"
  [ "$ARM_B" = bare ] && [ "$TOTAL_KIT" -le "$TOTAL_BARE" ] && \
    echo "   NOTE: the kit did not come out ahead. Report that as it stands — a harness that only publishes"
  [ "$ARM_B" = bare ] && [ "$TOTAL_KIT" -le "$TOTAL_BARE" ] && \
    echo "         favourable runs measures nothing."
fi
[ "$RUNS" = 1 ] && echo "   n=1: one run per arm is an anecdote, not a rate. Use --runs 3+ before quoting a number."
if [ "$NOT_MEASURED" -gt 0 ] || [ "$LIMITED" = 1 ] || [ "$SKIPPED" -gt 0 ]; then
  printf '   INCOMPLETE: %s run(s) NOT MEASURED%s%s. The totals above are not a result.\n' "$NOT_MEASURED" \
    "$([ "$SKIPPED" -gt 0 ] && echo ", $SKIPPED case(s) SKIPPED for a missing tool")" \
    "$([ "$LIMITED" = 1 ] && echo ', and the usage limit stopped every later run before it started')"
  exit 3
fi
exit 0
