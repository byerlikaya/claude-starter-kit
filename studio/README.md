# CSK Studio

A visual orchestration panel for Claude Code: which agent is running, what it is
doing right now, what it has spent, and which gates fired.

Studio is **not installed into your project**. It lives in this repository only,
alongside the kit it observes. `claude-starter/` — the payload that becomes a
user's `./.claude/` — is untouched by it.

## Run

```bash
node studio/server/index.js            # http://127.0.0.1:7777
node studio/server/index.js --port 8080
node studio/server/index.js --selftest # offline checks, no browser
```

There is no install step. Studio has **zero dependencies** — `node:http` and
`node:child_process` are the whole stack, matching the kit's own promise. If
`studio/node_modules` ever exists, something has gone wrong.

Requires Node 18+.

## What it does

**Watches.** The delegation graph of any session on this machine, live: one node
per agent, what it is doing right now, what it has spent, what it reported.
Nodes are draggable and their positions are remembered; a workflow run is a
container you can fold.

**Talks.** Sessions the panel starts are driven over stdin/stdout, so you can
write to one and watch its agents appear beneath it. They are given a session id
up front, which means their transcripts land where every other session's do and
the graph reads them without a special case.

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
