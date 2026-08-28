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

## What it reads

| Source | What it gives |
|---|---|
| `claude agents --json` | Live sessions on this machine: name, cwd, busy/waiting/idle, what it is waiting for |

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

## Security

The server binds to `127.0.0.1` only, and the host is deliberately not
configurable — it reads a developer's live sessions and transcripts.

Auth is opt-in while every endpoint is read-only:

```bash
CSK_STUDIO_TOKEN=$(uuidgen) node studio/server/index.js
```

It becomes mandatory in the sprint that introduces write endpoints.
