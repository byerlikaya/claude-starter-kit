---
name: performance
description: |
  Stack-agnostic performance: measure first, find the bottleneck, then optimise. N+1, needless allocation, wrong
  async boundary, missing index/cache, heavy payload. No premature optimisation.
  Use when something is slow, before optimising anything, and when a change touches a hot path.
---

# Performance

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "performance", "slow", "optimization", "profiling", "N+1", "latency", "memory leak", "load test"

Core rule: **measure first, optimize later.** Optimization without measurement is a guess; it usually speeds up the
wrong place and adds complexity. Stack-agnostic; do a web search when you need the profiling tool/library.

## Method (in order)
1. **Set a target** — what is "acceptable"? (p95 latency, throughput, memory ceiling). Numeric.
2. **Measure** — find the real bottleneck with a profiler/APM/benchmark; don't start from a guess.
3. **Fix the single most expensive thing** — Amdahl: speeding up a 5% path by 2x is wasted; target the hot path.
4. **Measure again** — did it actually improve, is there a regression.
5. **Stop** — once you hit the target, finish; no endless micro-optimization.

## Common bottlenecks

Catalog of common bottlenecks + fixes to consult: **`references/bottlenecks.md`**.

## Measurement tips
- Measure **under load** (a single request misleads); with a realistic data volume.
- **Not p50, but p95/p99** — tail latency is what burns the user.
- Don't trust micro-benchmarks; an end-to-end profile is more honest.

## Invariant rules
1. **Don't optimize without measuring** — a change without a profile = a guess.
2. **Target the hot path** — don't speed up the small share.
3. **Don't break correctness** — don't sacrifice behavior/edge cases for speed.
4. **Complexity budget** — make an optimization that seriously hurts readability only if there is a measured gain; comment it.
5. **Stop once you hit the target** — YAGNI; no premature/excessive optimization.
