---
name: studio-csk
description: Open CSK Studio — the visual panel for what agents are doing, what they spent, and which gates fired.
argument-hint: "[--port <n>] [--enable-pty]"
---
# /studio-csk

Start the panel and hand the user its URL. Never leave a half-started server behind: if any step below
fails, say which one and stop — do not improvise a different launch.

1. **Resolve the panel.** It is `.claude/studio/server/index.js`.
   Not there? Then this is either the **plugin edition**, which does not carry the panel, or an install
   from a kit older than the release that added it. Say which — `.claude/VERSION` present means a full
   install that is out of date, absent means a plugin install — and give the one fix:
   `npx @byerlikaya/claude-starter-kit@latest update --here --yes` at the project root, or `/update-csk`.
   Then stop. Do not go hunting for the panel anywhere else on disk.

2. **Probe node — do not ask whether the name resolves.** Run `node --version` and read the output;
   Node 18+ is required. A name that resolves is not a working interpreter (a Windows Store stub passes
   `command -v`, prints nothing and exits 49). Missing, stubbed or older than 18 → report exactly what
   the probe printed and stop. Never offer to install node.

3. **Start it in the background**, from the project root:

   ```bash
   node .claude/studio/server/index.js --open
   ```

   It prints a tokenised URL (`http://127.0.0.1:7777/?token=…`) and keeps running. **Report that URL**
   whether or not a browser opened — over SSH or headless nothing can open, and a running server with no
   way in is the worst outcome here. Tell the user it runs until they stop it, and how (Ctrl-C in that
   shell, or kill the process). Do not hold it in a foreground tool call.

4. **Port already in use** → retry once with `--port <n>` and report the new URL.

5. **`--enable-pty` only if the user asks for raw shells.** When they do, say this before starting it: a
   command typed into a raw shell never becomes a tool call, so it reaches no `PreToolUse` hook and
   `guard-bash.sh` is blind to it. Everything else in the panel routes through a tool call and therefore
   through the gates.

**What the panel's scope actually is.** It reads `~/.claude/projects` — every Claude Code session on this
machine, not this project's. Starting it from a project root only decides which project it opens on. Say
that when you hand over the URL, so nobody reports "it shows other projects" as a bug.

Offline diagnostic, no browser and no tokens: `node .claude/studio/server/index.js --selftest`.
