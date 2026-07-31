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
#   bash evals/run.sh --case secret-refused # one case
#   bash evals/run.sh --keep                # keep the scratch projects for inspection
#
# Exit 0 the report printed · 1 a case is malformed or the CLI is unusable.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$ROOT/evals/cases"

RUNS=1; ONLY=""; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="${2:-1}"; shift 2 ;;
    --case) ONLY="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
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
  if [ "$arm" = kit ]; then
    cp "$ROOT/start.sh" "$dir/"; cp -R "$ROOT/claude-starter" "$dir/"
    ( cd "$dir" && printf 'yes\n' | bash start.sh --fullstack --generic >/dev/null 2>&1 )
    # A bare-arm project has no .claude/, so a leftover installer would be a second difference between the
    # arms. It removes itself on success; make sure.
    rm -f "$dir/start.sh"; rm -rf "$dir/claude-starter"
    [ -d "$dir/.claude" ] || { echo "run.sh: install failed in $dir" >&2; return 1; }
  fi
}

# run_arm <dir> <arm> — same flags both sides. The kit arm additionally gets CLAUDE_GIT_OK when the case needs
# a commit to actually land: §4.4 gates the git TOOL behind human approval, which headless cannot answer, and
# without the documented escape the kit arm would be unable to commit for reasons that have nothing to do with
# the behaviour under test. The content gates (trace/secret pre-commit) still run — that is the point.
run_arm() {
  local dir="$1" arm="$2"
  local env_prefix=""
  [ "$arm" = kit ] && [ "${NEEDS_GIT_OK:-0}" = 1 ] && env_prefix="CLAUDE_GIT_OK=1"
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
    env $env_prefix CSK_GATE_LOG="$dir/.eval-gates.log" claude -p "$PROMPT" \
        --permission-mode "${CSK_EVAL_PERM:-bypassPermissions}" \
        --allowedTools ${CSK_EVAL_TOOLS:-Bash Read Write Edit Task Agent} \
        >"$dir/.eval-stdout.txt" 2>"$dir/.eval-stderr.txt"
  ) || true   # a non-zero exit is itself a result; the grader decides
}

printf '== kit A/B eval ==  %s · %s runs/arm\n\n' "$MODEL" "$RUNS"
[ -d "$CASES" ] || { echo "run.sh: no cases under evals/cases" >&2; exit 1; }

TOTAL_KIT=0; TOTAL_BARE=0; TOTAL_CHECKS=0
for cdir in "$CASES"/*/; do
  cname="$(basename "$cdir")"
  [ -n "$ONLY" ] && [ "$ONLY" != "$cname" ] && continue
  [ -f "$cdir/case.env" ] && [ -f "$cdir/grade.sh" ] || { echo "run.sh: $cname is missing case.env or grade.sh" >&2; exit 1; }

  # shellcheck disable=SC1090
  NEEDS_GIT_OK=0; unset -f seed post_seed 2>/dev/null; . "$cdir/case.env"
  echo "-- $cname --"
  [ -n "${DESC:-}" ] && echo "   $DESC"

  for arm in kit bare; do
    passed=0; checks=0; detail=""; gates=""
    for r in $(seq 1 "$RUNS"); do
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
      if [ "$arm" = kit ] && grep -q "has not been trusted" "$P/.eval-stderr.txt" 2>/dev/null; then
        echo "   ! workspace untrusted: permissions.allow was dropped for this run (hooks/gates are NOT affected)." >&2
        echo "     Only matters for cases needing a pre-approved permission. Re-run with CSK_EVAL_WORK=<a trusted path>," >&2
        echo "     or trust $P once interactively." >&2
      fi
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
    done
    if [ "$arm" = kit ]; then TOTAL_KIT=$((TOTAL_KIT+passed)); TOTAL_CHECKS=$((TOTAL_CHECKS+checks));
    else TOTAL_BARE=$((TOTAL_BARE+passed)); fi
    printf '   %-5s %s/%s checks' "$arm" "$passed" "$checks"
    [ "$RUNS" -gt 1 ] && printf ' (over %s runs)' "$RUNS"
    printf '\n'
    # Tally each distinct check across the runs instead of printing them N times.
    printf '%s\n' "$detail" | grep -E '^(PASS|FAIL) ' \
      | awk '{v=$1; $1=""; c[$0]=c[$0]; if(v=="PASS") p[$0]++; n[$0]++}
             END{for(k in n) printf "         %s/%s %s\n", p[k]+0, n[k], substr(k,2)}' | sort -t/ -k1,1n
    # Diagnosis line, printed outside the score. "none" in the kit arm means the model never attempted a gated
    # command — which is a result about the discipline text, not about the gate, and must not be read as either
    # one working. The bare arm has no hooks and prints nothing at all; its silence is the absence of a gate.
    if [ "$arm" = kit ]; then
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
printf '   kit  %s/%s\n   bare %s/%s\n' "$TOTAL_KIT" "$TOTAL_CHECKS" "$TOTAL_BARE" "$TOTAL_CHECKS"
if [ "$TOTAL_CHECKS" -gt 0 ]; then
  printf '   delta %+d checks\n' "$((TOTAL_KIT - TOTAL_BARE))"
  [ "$TOTAL_KIT" -le "$TOTAL_BARE" ] && \
    echo "   NOTE: the kit did not come out ahead. Report that as it stands — a harness that only publishes"
  [ "$TOTAL_KIT" -le "$TOTAL_BARE" ] && \
    echo "         favourable runs measures nothing."
fi
[ "$RUNS" = 1 ] && echo "   n=1: one run per arm is an anecdote, not a rate. Use --runs 3+ before quoting a number."
exit 0
