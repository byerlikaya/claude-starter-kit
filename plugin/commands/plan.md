---
name: plan
description: Spec-first planning — break down ambiguously scoped work with planner-csk.
argument-hint: "[task/feature description]"
---
# /plan
Argument: $ARGUMENTS

Delegate to the **planner-csk** agent (spec-planning skill). For ambiguously scoped work:
1. Clarify the goal + what's out of scope.
2. Split into vertical slices; give each task a measurable acceptance criterion.
3. Order by dependency + put the riskiest first.
4. Ask about ambiguities with **explicit options**; write down the assumptions.

Write the output to `docs/PLAN.md`, return a summary + pointer to the main thread (token-budget).
Do NOT write code — this is a planning step.
