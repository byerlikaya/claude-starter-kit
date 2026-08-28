# CSK Studio

A visual orchestration panel for Claude Code: which agent is running, what it is
doing right now, what it has spent, and which gates fired.

Studio is **not installed into your project**. It lives in this repository only,
alongside the kit it observes. `claude-starter/` — the payload that becomes a
user's `./.claude/` — is untouched by it.

## Run

```bash
npm run studio                         # http://127.0.0.1:7777
node studio/server/index.js --port 8080
node studio/server/index.js --selftest # offline checks, no browser
```

There is no `/studio-csk` slash command, and that is deliberate. Commands live
in `claude-starter/commands/` and are copied into every user's `.claude/`, while
Studio is not: `start.sh` installs five directories and this is not one of them,
and the npm tarball carries 130 files of which none are Studio's. A command
shipped to every project pointing at a directory none of them have is a broken
promise, not a convenience.

There is no install step. Studio has **zero dependencies** — `node:http` and
`node:child_process` are the whole stack, matching the kit's own promise. If
`studio/node_modules` ever exists, something has gone wrong.

Requires Node 18+. `bash packaging/verify.sh studio` runs the same checks CI
runs; a machine without node reports a skip rather than a pass.

## What it does

**Watches.** The delegation graph of any session on this machine, live: one node
per agent, what it is doing right now, what it has spent, what it reported.
Nodes are draggable and their positions are remembered; a workflow run is a
container you can fold.

**Talks.** Sessions the panel starts are driven over stdin/stdout, so you can
write to one and watch its agents appear beneath it. They are given a session id
up front, which means their transcripts land where every other session's do and
the graph reads them without a special case.

**Asks before it acts.** Every tool call in an owned session is parked by a
PreToolUse hook and shown in the panel — the command itself, not just the tool's
name — until you allow it, allow that tool for the session, or deny it.

**Runs several at once.** Each session the panel starts is a tab that keeps its
own stream open whether or not it is on screen, so work continuing in the
background is continuing, not replayed when you look back.

**Hands a session to a real terminal.** The panel cannot drive a session it did
not start, so for an observed one it offers the only thing that is true: a
button that opens it where it can be driven. What it will run is shown before
anything launches.

**Reaches other machines.** Transcripts are local files and nothing enumerates
another machine's sessions, so a peer is another Studio.

## What it reads

| Source | What it gives |
|---|---|
| `claude agents --json` | Live sessions on this machine: name, cwd, busy/waiting/idle, what it is waiting for |
| `<session>.jsonl` and `<session>/subagents/` | The delegation graph, nested workflow runs included |
| `.claude/VERSION` per project | Which projects run an old kit, against the npm dist-tags feed |

That call spawns a process, so it is cached rather than repeated. Measured on
the development machine: **min 161 ms · median 164 ms · max 171 ms** over three
runs. The browser polls every 2 s and the server caches for 1 s, which bounds
the cost at one spawn per poll. `--selftest` re-measures it wherever it runs, so
a slower machine reports its own number instead of inheriting this one.

More sources land in later sprints: the transcript tree (per-agent live JSONL),
the owned-session event stream, `gate-log.tsv`, and the team board.

## Two honesty rules

These are load-bearing, not stylistic.

**"Not measured" is never drawn as zero.** If the `claude` CLI is missing or a
read fails, the panel says so and names the reason. An empty list would read as
a quiet, healthy machine — which is the kind of lie this panel exists to stop
telling.

**Unknown data is never coerced into something familiar.** An unrecognised
status keeps a neutral ring; an unrecognised field is carried through untouched
rather than dropped. Claude Code's event shapes are undocumented and move with
the version, so the panel is built to notice that rather than to guess.

## Other machines

```bash
# on the other machine
node studio/server/index.js

# here — forward its port, then point at the forwarded one
ssh -N -L 7778:127.0.0.1:7777 other-machine
node studio/server/index.js --peer http://127.0.0.1:7778 --name mac
```

Sessions, projects, graphs and agent reports from a peer appear alongside local
ones, tagged with the machine they came from. A peer that cannot be reached is
reported as unreachable, never as empty.

Nothing listens on a network interface in this arrangement: both Studios stay on
loopback and the tunnel does the crossing.

## The permission gate

A hook injected through `--settings` parks each tool call, writes it into a
spool, and waits for the panel's answer. Exit 0 allows, exit 2 blocks.

It answers at 45 seconds against a 90-second harness timeout, and that gap is
the whole design. Measured here: a hook killed at its timeout emits nothing and
**the tool proceeds** — `permission_denials` came back 0 and the command ran. A
hook the harness never has to kill fails closed instead, so a shut panel is a
denial rather than an opening.

The waiting costs no processes. A bounded read on a fifo held open read-write
blocks for its timeout and never sees EOF; the alternative, a `sleep` per poll,
spends seconds of fork overhead on Git Bash. Both the fifo and the shell's
support for fractional timeouts are probed with exactly what the loop will run —
bash 3.2 ignores a fractional `-t` and turns the poll into a hot spin, which is
how the first version passed while spinning 185,000 times in five seconds.

Interactive prompts have a limit worth stating: `AskUserQuestion`, `ExitPlanMode`
and `EnterPlanMode` are absent from a headless session's 78-tool list, in every
permission mode, while an interactive session has them. So there is no
structured choice to render. When a reply offers options in prose the panel
makes them clickable, which sends that text — a shortcut for typing it, not a
channel that does not exist.

## Raw shells

Off unless asked for:

```bash
node studio/server/index.js --enable-pty
```

This is the one surface in the panel that steps outside the kit's own gates. A
command typed in a raw shell never reaches a PreToolUse hook, because there is
no tool call to intercept — so `guard-bash.sh` and everything beside it are
blind to it. The panel says so on the screen, in the tab, and in the startup
log, and everything else it offers routes shell work through a session's `Bash`
tool where the gates do apply.

The terminal itself needs nothing installed: Python's `pty` is in the standard
library, and this repo already depends on python3. Measured: a real `/dev/ttys*`,
`[ -t 0 ]` true inside it, and `TIOCSWINSZ` resizing. Unix only — the `pty`
module does not exist on Windows, which is reported rather than worked around.

What it renders is scrollback with colour, carriage returns, backspaces and the
common erase sequences: `ls --color`, `git status`, a test run. It is not a
screen, so a full-screen program (vim, htop) is out of scope by design — the
view says as much when it sees one painting.

## Security

The server binds to `127.0.0.1` only, and the host is deliberately not
configurable — it reads a developer's live sessions and can start new ones.

A token is always required for `/api/`. Supply one, or let the server generate
one and print it with the URL:

```bash
CSK_STUDIO_TOKEN=$(uuidgen) node studio/server/index.js
```

Anything that changes state needs, on top of the token, a header no cross-origin
page can attach without a preflight this server never answers. Permission modes
are an allow-list — `plan` (the default), `acceptEdits`, `default` — so a mode
that skips the kit's gates cannot be requested, and the panel never has to name
one to refuse it.
