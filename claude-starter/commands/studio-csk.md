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

2. **Resolve a runtime — do not ask whether a name resolves.**

   ```bash
   bash .claude/studio/ensure-node.sh --explain
   ```

   It prints the path of a Node 18+ that actually runs and exits 1 when there is none. Use that path;
   do not assume it is `node`. It looks in places PATH does not reach — a version manager puts node on
   PATH from a login shell only, so "nvm is installed" and "this shell can see node" are different
   facts. And it runs what it finds rather than trusting the name: the Windows Store ships a stub that
   satisfies `command -v`, prints nothing and exits 49.

   **No `ensure-node.sh`?** Then the panel is installed but predates the fetcher. Fall back to running
   `node --version` and reading the output — 18+ required — and tell the user `/update-csk` brings the
   fetcher along with everything else.

3. **No runtime? The kit gets one — after the user says so.** This is the step that used to be a dead
   end. Show them what it would do, then ask:

   ```bash
   bash .claude/studio/ensure-node.sh --plan      # url, size, checksum source, target directory
   ```

   It fetches the current Node LTS from nodejs.org into `~/.claude/studio-runtime`, verifies it against
   the published SHA-256 and refuses to install on a mismatch. Nothing else on the machine is touched:
   no admin rights, no package manager, no PATH or profile edit. Deleting that one directory undoes it.

   Ask with `AskUserQuestion`, and offer the alternative honestly — some people would rather their own
   package manager owned it (`winget install OpenJS.NodeJS.LTS`, `brew install node`, or their distro's).
   On yes:

   ```bash
   bash .claude/studio/ensure-node.sh --install   # prints the node path on success
   ```

   Never run `--install --yes` on the user's behalf without that answer, and never install anything
   system-wide.

4. **Start it in the background**, from the project root, with the node from step 2 or 3:

   ```bash
   "$NODE" .claude/studio/server/index.js --open
   ```

   It prints a tokenised URL (`http://127.0.0.1:7777/?token=…`) and keeps running. **Report that URL**
   whether or not a browser opened — over SSH or headless nothing can open, and a running server with no
   way in is the worst outcome here. Tell the user it runs until they stop it, and how (Ctrl-C in that
   shell, or kill the process). Do not hold it in a foreground tool call.

5. **Port already in use** → retry once with `--port <n>` and report the new URL.

6. **`--enable-pty` only if the user asks for raw shells.** When they do, say this before starting it: a
   command typed into a raw shell never becomes a tool call, so it reaches no `PreToolUse` hook and
   `guard-bash.sh` is blind to it. Everything else in the panel routes through a tool call and therefore
   through the gates.

**What the panel's scope actually is.** It reads `~/.claude/projects` — every Claude Code session on this
machine, not this project's. Starting it from a project root only decides which project it opens on. Say
that when you hand over the URL, so nobody reports "it shows other projects" as a bug.

Offline diagnostic, no browser and no tokens: `"$NODE" .claude/studio/server/index.js --selftest`.
