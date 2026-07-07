---
name: handoff
description: |
  Session handover summary: when context fills up / a phase closes / the topic changes, write an
  action-oriented handover to docs/SESSION_STATE.md, then recommend /clear. Triggered by session-manager-cck.
  Trigger phrases: "handoff", "hand off", "session summary", "session state", "clear context", "I'll continue"
---

# Session Handover (Handoff)

## When
`/context` > 75% · phase closure · topic change. Goal: the next session should **not start from scratch**.

## Output (docs/SESSION_STATE.md, local)
```
# Session Handover — <date>
## Done
- <completed work + which files>
## In progress
- <what's half-finished + exactly where it was left off>
## Next step
- <a clear, single high-value step>
## Open decisions
- <pending decision + options>
## File pointers
- docs/PLAN.md, relevant modules...
## Blockers / risks
- <if any>
```

## Principles
- **Action-oriented:** focused not on "what was done" but on "exactly where to resume now."
- Preserve the rationale behind decisions (why this path was chosen) — so context isn't lost.
- Once written, start a fresh session with `/clear`.

## DoD
- A handover file; a new session can resume where it left off by reading only this file.
