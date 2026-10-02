# Studio

A delegation three levels deep is, in a terminal, a scrollback you have already lost. **Crewforth Studio** is a local panel that draws it instead: one card per agent, appearing as they spawn, each carrying its status and the task it was given. Selecting a card opens what the agent last reached for, what it has spent and what it reported back. The same session can be read three ways: as a graph of who started whom, as a timeline against the clock, and as a list sorted by what needs someone.

It reads `~/.claude/projects` — where Claude Code keeps every session on this machine — so one running panel sees all of them at once, whether or not a project has Crewforth installed, and without being started inside any of them.

```bash
/crew-studio                                       # in any project that has Crewforth
node .claude/studio/server/index.js --open        # the same, without the command menu
npx crewforth studio                              # without installing anything
# `node` not on PATH? Crewforth keeps its promise not to edit it — ask for the one it fetched:
#   NODE="$(bash .claude/studio/ensure-node.sh)" && "$NODE" .claude/studio/server/index.js --open
```

| In the panel | What it rests on |
|:--|:--|
| The delegation of any session, live, as a **Graph**, a **Timeline** or a **List** (`g`, `t`, `l`) | the transcript tree on disk, re-read on a size signature every 700 ms; the three views are drawn from that one reading |
| Sessions the panel starts, driven from the conversation panel | `claude -p` in stream-json, over the child's stdin and stdout |
| Every tool call in one of those parked in the approval dock until you answer | a `PreToolUse` hook injected through the panel's own settings file, matching `*`. It answers at 45 s against the harness's 90 s, and **silence is a denial** — a panel that is closed does not become permission |
| Continuing a session rather than copying it | a bare `--resume` when no process holds that session, which keeps its id and appends to its transcript; a fork when one does, because two writers on one transcript corrupt it |
| The gate log, session stats and board | Crewforth's existing scripts, read rather than recomputed — and gate-log entries are labelled as carrying no timestamp, because that format has none |

<div align="center">
  <img src="../../../assets/studio-panels.gif" alt="Using the panel: a session opens from the navigator, an agent's inspector opens beside the graph, the Timeline shows the same session against time with the failed agent's last error in a drawer, the List sorts the agents by status, a tool call from another session arrives in the approval dock and is allowed, and the New session panel opens" width="900">
  <br><sub>The same panel, driven: the graph and an agent's inspector, the Timeline, the List, a request answered in the dock, the New session panel.</sub>
</div>

## Three views of one session

- **Graph**: the delegation in its own shape. The session is on the left, the agents it started are to its right, and a workflow run is one group that folds. A strip above the canvas names what needs attention, and a click goes to it.
- **Timeline**: the same agents against the clock, one row each, and a drawer with the selected agent's last error. The time an agent spent waiting for you is drawn only for a session Studio started, and only since the panel started, because that record is kept in memory. For any other session the Timeline says `Not measured: this session's approvals are not seen by Studio` instead of drawing a session in which nobody waited.
- **List**: the agents sorted by what needs someone. Requests waiting for you come first, then failed and running; done and ended are folded.

Selecting an agent in any view opens the inspector, with four tabs: **Overview** (tool calls, tokens, elapsed time, errors, the last tool, the skills it applied, who delegated it, and its report), **Conversation**, **Gates** and **Stats**.

## The approval dock

A tool call in a session Studio started waits in a dock along the bottom of the panel, whichever session and view are on screen. It shows the agent that asked, the tool and its input, and three answers: **Allow once**, **Allow _tool_ this session** and **Deny** (`a`, `s`, `d`). Unanswered, the call is denied at 45 s. A session allowance is listed in the inspector's Gates tab and can be revoked there.

Allow is an answer to Claude Code. It does not go around anything:

- In the Accept edits and Default modes, Allow hands Claude Code an explicit allow. In Plan it says nothing, and Claude Code's own plan rules decide.
- A Crewforth gate or a `deny` rule in the project's settings still refuses a call you allowed (measured on Windows, in a real session). The conversation then carries a line saying the call was allowed here and who refused it.
- Studio's hook runs beside the project's other hooks, not after them, so the dock can ask about a call that another gate refuses anyway. That is a known limit.

## Starting a session

**New session** opens a panel on the right: the project the session runs in, its permission mode, and an optional first message. Three modes are offered. **Plan** is the default: it reads and plans, and cannot change files. **Accept edits** and **Default** edit files and run commands, each call after you allow it in the dock. Modes that skip Crewforth's gates are not offered. If Studio is closed while such a session runs, its requests are denied.

## A narrow window

Below 640 px the panel is one column. The navigator becomes a drawer, the inspector and the conversation each take the whole stage and stop above the dock, and the panel opens on the List, where a request's three answers sit one under the other. The Graph and the Timeline still open, and say `Best on a wider screen`. This is the layout a phone-sized window gets. It was checked in a narrow desktop browser window and is not measured on a phone, and the panel still listens on `127.0.0.1` only.

**Studio installs with Crewforth.** `start.sh` and `adopt.sh` create six directories under `.claude/` and Studio is the sixth, so in any project that has Crewforth you open it with **`/crew-studio`** — or, without the command menu, `node .claude/studio/server/index.js --open`. It has zero npm dependencies, wants Node 18+, binds to `127.0.0.1` only and requires a per-run token on every API path. **No Node on the machine? Crewforth goes and gets one.** `.claude/studio/ensure-node.sh --plan` shows exactly what it would fetch — the current LTS from nodejs.org, checked against the published SHA-256 and unpacked into `~/.claude/studio-runtime` — and installs nothing until you say yes. No admin rights, no package manager, no PATH edit; deleting that one directory undoes it.

| Channel | Studio |
|:--|:--|
| `npx crewforth` · release tarball · git clone | installed to `.claude/studio/` |
| Claude Code plugin | shipped inside the plugin, opened with `/crewforth:crew-studio` (plugin commands are namespaced) |

All three channels carry it. One command file serves both editions: Claude Code substitutes the plugin's own install path into it, so the panel is found wherever it actually is. The panel behaves identically in both, with one honest gap — its telemetry reads the project you opened it from, and a plugin install puts no Crewforth files into a project, so the Gates and Stats tabs and the board report "not measured" with the reason rather than a misleading zero. The Gates tab still lists the gate decisions the plugin's guards logged to that project's `.claude/gate-log.tsv`.

It reads `~/.claude/projects`, which holds **every** Claude Code session on the machine. Starting it from a project root only decides which project it opens on.

<div align="center">
  <img src="../../../assets/studio-graph.png" alt="The Graph view of one session: the session card on the left, its agents to the right with their status and task, a workflow run as one group of four, and the failed agent named in the strip above the canvas" width="900">
  <br><sub>Who is running, who finished and who failed. The failed agent is named in the strip above the canvas, one click away.</sub>
</div>
