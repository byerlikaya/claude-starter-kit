---
name: performance
description: |
  Stack-agnostic performance discipline: measure first, find the bottleneck, then optimize. N+1, needless
  allocation, wrong async boundary, missing index/cache, heavy payload. Avoids premature optimization.
  Trigger phrases: "performance", "performance", "slow", "optimization", "profiling", "N+1", "latency", "memory leak", "load test"
---

# Performance

Core rule: **measure first, optimize later.** Optimization without measurement is a guess; it usually speeds up the
wrong place and adds complexity. Stack-agnostic; do a web search when you need the profiling tool/library.

## Method (in order)
1. **Set a target** — what is "acceptable"? (p95 latency, throughput, memory ceiling). Numeric.
2. **Measure** — find the real bottleneck with a profiler/APM/benchmark; don't start from a guess.
3. **Fix the single most expensive thing** — Amdahl: speeding up a 5% path by 2x is wasted; target the hot path.
4. **Measure again** — did it actually improve, is there a regression.
5. **Stop** — once you hit the target, finish; no endless micro-optimization.

## Common bottlenecks
| Area | Pattern | Fix |
|---|---|---|
| **DB** | N+1 query, missing index, `SELECT *`, table scan | eager/batch loading, index (db-migration), only needed columns |
| **Memory** | needless allocation, holding large objects, leak | pooling, streaming, releasing references |
| **Async** | wrong sync/async boundary, blocking I/O, serial await | parallel await, non-blocking I/O |
| **Network/payload** | oversized response, no compression, chatty API | pagination, field selection, gzip, batch (api-design) |
| **Cache** | repeated expensive computation, no/wrong cache | cache at the right layer + correct invalidation |
| **Frontend** | needless render, large bundle, blocking resource | memo, code-split, lazy, critical CSS |

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
