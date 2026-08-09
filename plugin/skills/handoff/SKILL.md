---
name: handoff
description: |
  Session handover: when context fills, a phase closes, or the topic changes, write an action-oriented handover
  to docs/SESSION_STATE.md, then recommend /clear.
---

# Session Handover (Handoff)

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "handoff", "hand off", "session summary", "session state", "clear context", "I'll continue"

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

## Measure the session before summarising it
Run **`bash .claude/hooks/session-stats.sh`** first. What it reports belongs in the handover as fact, not
impression — an auto-compaction means state was already dropped before you started writing (say what was lost),
a runaway loop marks an approach the next session should not walk back into, and repeated prompts mark context
that never landed and has to be written down explicitly this time. Missing script (plugin install) → say so.

## Principles
- **Action-oriented:** focused not on "what was done" but on "exactly where to resume now."
- Preserve the rationale behind decisions (why this path was chosen) — so context isn't lost.
- Once written, start a fresh session with `/clear`.

## Holding a board item? The handover is owed to the TEAM, not just to the next session
`docs/SESSION_STATE.md` is gitignored — it survives your `/clear`, and nobody else can read it. If a
`teamboard` claim is open, the same "exactly where it stands, and why" also goes to the item
(`/board-csk note <id>`, or `drop <id> "<note>"` when you are releasing it). A teammate inheriting the work
reads the board, never your local file.

## Redaction (`<private>` marker)
`docs/SESSION_STATE.md` is a **shared, often committed** artifact — never persist a secret, token, credential, or
personal note into it. Any content wrapped in **`<private>…</private>`** is a redaction marker: strip it from the
written handover and leave a `[redacted]` placeholder in its place. If a resume genuinely needs a sensitive value,
point to *where it lives* (env var, secret manager, the person to ask) — never the value itself.

## DoD
- A handover file; a new session can resume where it left off by reading only this file.
