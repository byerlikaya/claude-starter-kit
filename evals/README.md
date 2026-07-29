# evals — does the kit change what the model does?

Everything else in this repo checks that the kit is well-**formed**. This checks whether it **works**.

Same prompt, two projects: one with the kit installed, one bare. Graded on what is left on disk.

```bash
bash evals/run.sh                      # every case, 1 run per arm
bash evals/run.sh --runs 3             # 3 runs per arm
bash evals/run.sh --case secret-refused
bash evals/run.sh --keep               # keep the scratch projects
```

**This costs real tokens.** It is wired into no gate, no hook and no CI job — smoke-test and routing-eval stay
hermetic and free. Run it when you want the number, not on every change.

## Two rules the harness enforces on itself

**Grade the artifact, never the transcript.** An early attempt false-failed because the model's own commentary
— "I left out the co-authorship trailer per §4.1" — contained the string the grader was grepping for. Graders
read git state and files. What the model *says* it did is not evidence.

**Both arms get identical tool access.** Otherwise the bare arm fails for permission reasons and the delta
measures the harness. The only difference between the arms is whether `.claude/` and `CLAUDE.md` exist.

## Environment

The permission layer is deliberately out of the way (`--permission-mode bypassPermissions`, override with
`CSK_EVAL_PERM`). What is measured here is what the kit does to the model's **output** — commit shape, how a
credential is handled — not whether the approval prompt fires. That is a permission-layer contract, asserted
exactly in `smoke-test §7`; inferring it from a headless denial measures the absence of a human instead. The
git-hook gates (trace, secret) ignore permission mode and still run, and those *are* part of the measurement.

Scratch projects default to `$TMPDIR`; point `CSK_EVAL_WORK` at a path Claude Code already trusts if you see
the "workspace has not been trusted" warning — an untrusted workspace silently drops the kit's
`permissions.allow` entry, and the runner will tell you when that happened rather than scoring it.

## Reading a result

`--runs 1` is an anecdote. Model output is nondeterministic; a single run tells you a thing *can* happen, not
how often. Use `--runs 3` or more before quoting a number anywhere, and quote the date, the CLI version and
the run count with it. A number without those is the kind of claim this project's gates exist to prevent.

If the kit loses, publish that. A harness that only reports favourable runs measures nothing.

## What it has found so far

- A bare-project commit landed with a co-authorship trailer and a non-conventional subject — caught by the
  kit's own `trace-blocklist.txt`, not by a second matcher written for the grader.
- **`CLAUDE_GIT_OK` did nothing.** §4.4 advertised it as the way to work headless; the hook answered `exit 0`,
  which means "no opinion" and left `settings.json`'s `ask` rules in force, so a keyed session could not even
  stage. Now an explicit `allow`. The flag had exactly one purpose and was not achieving it — and no unit test
  caught it, because they all asserted the exit code, which was always right.

## When `claude plugin eval` opens

`claude plugin eval --ablation with-without` is the purpose-built version of this and would replace `run.sh`
outright. Still early access as of CLI 2.1.220 (2026-07-29) — re-check with `claude plugin eval .`. When it
opens, keep `cases/` and the graders and delete the runner.
