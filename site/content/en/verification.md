# Verification

```bash
bash .claude/eval/smoke-test.sh      # structure, frontmatter, gate integrity
bash .claude/eval/routing-eval.sh    # does an example prompt reach the right agent or skill
bash .claude/eval/doctor.sh          # is this install healthy, and is the project ready
bash .claude/eval/preflight.sh       # which tools this machine has, and what degrades without them
```

`preflight.sh` also runs inside `start.sh`, `adopt.sh` and `doctor.sh`. Crewforth needs neither `jq` nor `python`: every JSON read and write, every hook and every installer step is one bash/awk path, so macOS, Linux and a stock Windows Git Bash run the same code and get the same result. Where a tool is still optional Crewforth degrades rather than breaks — no `sha256sum` falls back to `cksum` — which is the right design and also the reason a gap never announces itself. Preflight names the gap and what it costs. It reports; it never installs anything on your machine and never blocks a run.

## Does it actually change anything?

The same prompt is run in a Crewforth project and a bare one, and graded on what each left on disk. The rule a result must meet is written down before the run. Every measurement is published with its reasoning in [`evals/README.md`](../../../evals/README.md), including the ones where that rule did not hold.
