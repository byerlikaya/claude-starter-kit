---
name: board-csk
description: Team board — see who holds which item, claim one, hand it over, complete it.
argument-hint: "[claim <id> | done <id> | drop <id> | add <id> <title> | init | sync]"
---
# /board-csk
Argument: $ARGUMENTS

Apply the `teamboard` skill. The engine is `bash .claude/hooks/board.sh`; never hand-edit the board.

- **no argument** → `board.sh status`. Report it as: who holds what (and for how long), what is claimable now,
  what is blocked and by which item, and any STALE claim. End with a concrete recommendation of which item to take.
- **`claim <id>`** → `board.sh claim <id>`. A refusal is an answer, not an error: name who holds it and offer the
  claimable alternatives. Never work around a refusal. On success it prints the **connected work** — what each
  dependency actually delivered, and which items are waiting on this one. Read that back to the user before
  writing anything; it is the context the previous person had and you do not.
- **`done <id>`** → ask for what shipped (commit/PR), then `board.sh done <id> "<note>"`, and tell the user which
  items this unblocked.
- **`drop <id>`** → write the handover note FIRST — exactly where it stands, which files, and why the discarded
  approach was discarded — then `board.sh drop <id> "<note>"`. The engine refuses an empty note.
- **`add <id> <title> [deps]`** → add items. From `docs/PLAN.md`, carry each task's dependency edges across.
- **`init`** → create the board (probes the server's ref support first), then add the items. `init --remote <url>`
  puts it in a separate repository instead. Run by ONE person, once — everyone else configures nothing and the
  board reaches them on its own. If a board already exists this fetches it rather than creating a second.
- **`sync`** → fetch and re-read; use it when the board looks stale or a gate message disagrees with reality.
- **`off` / `on`** → release every board gate for this repo (`off --global` for all of them) and put them back.
  The board is untouched either way. A repo that never ran `init` has no gates to begin with — never imply the
  user must turn something off to work alone.

Before writing any code for an item, confirm this user holds it. Commits are gated: `[#<id>]` for a held item,
`[chore]` otherwise. Strip secrets from anything written to the board — it is pushed to the whole team.
