---
name: studio-csk
description: Open CSK Studio — the visual panel for what agents are doing, what they spent, and which gates fired.
argument-hint: "[--port <n>] [--enable-pty]"
---
# /studio-csk

Start the panel and hand the user its URL. Never leave a half-started server behind: if any step below
fails, say which one and stop — do not improvise a different launch.

1. **Resolve the panel.** Both editions carry it, in different places, and this one file serves both.

   ```
   PLUGIN_PANEL=${CLAUDE_PLUGIN_ROOT}/studio/server/index.js
   ```

   Claude Code replaces `${CLAUDE_PLUGIN_ROOT}` in this text **before you read it**, and only when this
   command came from the plugin. So read the line above literally:

   - It names a real absolute path → **plugin edition**. That is the panel. Use it.
   - It still contains the characters `${CLAUDE_PLUGIN_ROOT}` → this is a **full install**. The panel is
     `.claude/studio/server/index.js`.

   The variable is not in the shell's environment — it is text substituted into this file — so never try
   to read it with `printenv` or let a shell expand it. Never write the unbraced `$CLAUDE_PLUGIN_ROOT`
   either; only the braced form is substituted, and the unbraced one reaches bash unset and collapses the
   path to `/studio/server/index.js`.

   Neither path is there? Then this is an install from a kit older than the release that added the panel:
   `npx @byerlikaya/claude-starter-kit@latest update --here --yes` at the project root, or `/update-csk`.
   Then stop. Do not go hunting for the panel anywhere else on disk.

   **What the plugin edition cannot show.** A plugin install puts no `.claude/VERSION`, `kit.conf` or kit
   scripts into a project. So that project's row in the list has no kit badge (each row reads its own
   project), and for the project you opened the panel from, the inspector's gates, stats and board tabs
   say "Not measured" with the reason, rather than zero. The gates tab can still list observed entries
   below that. The plugin's Bash guard logs its blocks, approval prompts and `CLAUDE_GIT_OK` pre-authorised
   git actions, and its gate-file write guard logs its blocks, to `.claude/gate-log.tsv` when the project
   has a `.claude/` directory and the file is git-ignored or the project is not a repo. With `CSK_GATE_LOG`
   set they write wherever it points instead, and the panel reads only the project's own
   `.claude/gate-log.tsv`, so a log sent anywhere else does not show. The commit scan and the board gate
   refuse without writing a line. Say this once when you hand over the URL, so an honest blank is not
   read as a broken panel. Everything else — the live agent graph, owned sessions, the permission bridge,
   the terminals — works the same in both editions.

2. **Resolve a runtime — do not ask whether a name resolves.** `ensure-node.sh` sits beside the panel, so
   use whichever root step 1 settled on:

   ```bash
   bash <panel-root>/ensure-node.sh --explain
   ```

   It prints the path of a Node 18+ that actually runs and exits 1 when there is none. Use that path;
   do not assume it is `node`. It looks in places PATH does not reach — a version manager puts node on
   PATH from a login shell only, so "nvm is installed" and "this shell can see node" are different
   facts. And it runs what it finds rather than trusting the name: the Windows Store ships a stub that
   satisfies `command -v`, prints nothing and exits 49.

   **No `ensure-node.sh` beside the panel?** Then the panel predates the fetcher. Fall back to running
   `node --version` and reading the output — 18+ required — and tell the user `/update-csk` brings the
   fetcher along with everything else.

3. **No runtime? The kit gets one — after the user says so.** This is the step that used to be a dead
   end. Show them what it would do, then ask:

   ```bash
   bash <panel-root>/ensure-node.sh --plan       # url, size, checksum source, target directory
   ```

   It fetches the current Node LTS from nodejs.org into `~/.claude/studio-runtime`, verifies it against
   the published SHA-256 and refuses to install on a mismatch. Nothing else on the machine is touched:
   no admin rights, no package manager, no PATH or profile edit. Deleting that one directory undoes it.

   Ask with `AskUserQuestion`, and offer the alternative honestly — some people would rather their own
   package manager owned it (`winget install OpenJS.NodeJS.LTS`, `brew install node`, or their distro's).
   On yes:

   ```bash
   bash <panel-root>/ensure-node.sh --install    # prints the node path on success
   ```

   Never run `--install --yes` on the user's behalf without that answer, and never install anything
   system-wide.

4. **Start it in the background**, from the project root, with the node from step 2 or 3:

   ```bash
   "$NODE" <panel> --open
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

Offline diagnostic, no browser and no tokens: `"$NODE" <panel> --selftest`.

**In the plugin edition this command is namespaced** — `/claude-starter-kit:studio-csk`, not
`/studio-csk`. Measured: the bare name does not resolve for a plugin command.
