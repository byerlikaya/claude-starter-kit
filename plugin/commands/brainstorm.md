---
name: brainstorm
description: Diverge before planning — turn a fuzzy ask into scoped options and a chosen direction.
argument-hint: "[fuzzy idea / problem to explore]"
---
# /brainstorm
Argument: $ARGUMENTS

Delegate to the **planner-csk** agent applying the **brainstorm** skill. For an under-defined ask:
1. Restate the real goal separately from the requested solution.
2. Generate **2–4 genuinely different** directions (include a cheap/minimal one); give each its trade-off.
3. Surface assumptions + open questions; mark which are blocking.
4. Ask the user to choose WITH **explicit numbered options**; log the rejected directions + why.

Write a long exploration to `docs/DISCOVERY.md`; return the option headings + the chosen direction (token-budget).
Do NOT write code — this is discovery. Once a direction is chosen, hand off to `/plan` (spec-planning).
