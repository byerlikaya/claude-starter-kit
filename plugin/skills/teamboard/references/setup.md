# Setting a board up — one person, one command

Read this only when a board is being created or its level changed. Claiming, dropping and finishing an item never
need it: a teammate who clones the repo configures nothing.

## Who runs what

- **Whoever starts it:** `/board-crew init`, then add the items. It probes what the server accepts, creates the
  board on the code repo's own `origin`, and that is the whole setup — no account, no token, no service.
- **A separate board repository:** `/board-crew init --remote <url>` (or an existing remote's name). Use it when
  the board is shared across several repos, or when people who must claim work cannot push to the code repo. It
  gets its own `csk-board` remote and never touches `origin`.
- **Everyone else: nothing.** They clone as usual. Session start fetches the board on its own (detached), the
  ref namespace is auto-detected including the orphan-branch fallback, and `/board-crew` fetches on the spot if
  the background refresh has not landed yet. Never tell a teammate to run `init` — a second `init` is how a team
  ends up with two boards.

## The ref namespace, and the fallback

`init` first probes whether the server accepts a custom ref namespace (`refs/csk/board`); if it does not, it
falls back to the orphan branch `refs/heads/csk-board`, which every server accepts and which enforces the same
fast-forward rule. Do not merge that branch into code.

## Which level to create

Do not create a board because a repo merely has more than one contributor; create one when the user says the team
keeps colliding. Three levels, and the user picks:

| | Effect |
|---|---|
| no board (default) | nothing at all |
| `require_item: referenced` in the board's `config` | claims and the shared memory, but no gate: a commit is only checked when it names an item |
| `require_item: all` (what `init` writes) | claim before you edit, and every commit names an item or `[chore]` |

A board with no remote is fine too — you get the item list, the dependency order and the gates, just nothing
shared. Turning the gates off on an existing board is in SKILL.md, not here: someone a gate has just stopped
needs that answer without opening a second file.
