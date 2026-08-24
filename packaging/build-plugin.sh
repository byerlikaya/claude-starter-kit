#!/usr/bin/env bash
# Generate the Claude Code plugin edition from the payload — the "lite" channel.
# It ships the agents, skills, commands, AND the tool-level gate hooks (auto-discovered via hooks/hooks.json,
# invoked through ${CLAUDE_PLUGIN_ROOT}). What it does NOT ship: the git-hook gates (pre-commit / commit-msg
# trace/secret/bloat scan) — those are wired by core.hooksPath, which only the full install (start.sh / adopt.sh)
# can set. So a plugin user gets the Claude Code gates (commit/push approval, destructive-op & write guards,
# context measurement, session rehydration) but the commit-time trace scan still needs the full install.
# Single source of truth stays claude-starter/; this regenerates plugin/ from it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/claude-starter"
OUT="$ROOT/plugin"

rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin" "$OUT/hooks"
cp -R "$SRC/agents"   "$OUT/agents"
cp -R "$SRC/skills"   "$OUT/skills"
cp -R "$SRC/commands" "$OUT/commands"

# The Claude Code hooks that work standalone (self-locate via $0, read stdin).
# skill-trust.sh is left out: it decides kit-owned vs project-owned from .claude/kit-manifest.txt, which only a
# start.sh/adopt.sh install writes. Shipped here it could only ever exit silently — an idle component.
# session-update-check.sh IS shipped: it reads the plugin's own .claude-plugin/plugin.json and compares it against
# the marketplace repo's copy, so a plugin user hears about a release on the channel that delivers it.
# board.sh is not itself a hook: it is the engine board-sync.sh and commit-msg both call by path. It ships in the
# same directory because both of those callers resolve it as "$HERE/board.sh", and a plugin edition without it
# would carry the board's session-start awareness and none of its claim gate — the exact one-channel-is-weaker
# asymmetry the git hooks below were added to close.
for h in guard-bash.sh guard-write.sh context-usage.sh session-guard.sh session-rehydrate.sh session-stats.sh \
         guard-commit-scan.sh route-hint.sh session-update-check.sh board.sh board-sync.sh; do
  cp "$SRC/hooks/$h" "$OUT/hooks/$h"
  chmod +x "$OUT/hooks/$h"
done

# The git hooks and their pattern files now DO ship — not to be wired through core.hooksPath (a plugin cannot
# set that), but because guard-commit-scan.sh runs them from PreToolUse. Without them the plugin edition had
# the commit APPROVAL gate and none of the commit CONTENT gates: a credential or an authorship trailer could
# land, and of four distribution channels one was quietly weaker than the rest.
for h in pre-commit commit-msg; do
  cp "$SRC/hooks/$h" "$OUT/hooks/$h"
  chmod +x "$OUT/hooks/$h"
done
cp "$SRC/hooks/trace-blocklist.txt" "$SRC/hooks/secret-blocklist.txt" "$OUT/hooks/"

# hooks/hooks.json — auto-discovered by Claude Code when the plugin is enabled (no plugin.json field needed).
# Same structure as settings.json's "hooks", but paths resolve through ${CLAUDE_PLUGIN_ROOT} (the plugin's install
# dir) instead of ${CLAUDE_PROJECT_DIR}/.claude. Quoted heredoc: ${CLAUDE_PLUGIN_ROOT} stays literal for Claude Code.
cat > "$OUT/hooks/hooks.json" <<'HOOKS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/guard-bash.sh\"", "timeout": 60 },
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/guard-commit-scan.sh\"", "timeout": 60 }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/guard-write.sh\"", "timeout": 60 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/context-usage.sh\"", "timeout": 60 },
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/route-hint.sh\"", "timeout": 60 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/session-guard.sh\"", "timeout": 60 }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact|clear|resume",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/session-rehydrate.sh\"", "timeout": 60 }
        ]
      },
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/board-sync.sh\"", "timeout": 60 }
        ]
      },
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/session-update-check.sh\"", "timeout": 60 }
        ]
      }
    ]
  }
}
HOOKS

VERSION="$(cat "$ROOT/VERSION")"
cat > "$OUT/.claude-plugin/plugin.json" <<JSON
{
  "\$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "claude-starter-kit",
  "displayName": "Claude Starter Kit",
  "description": "Agentic Working Kit — disciplined agents, skills, slash commands, and tool-level gate hooks (commit/push approval, destructive-op & write guards, context-fill measurement, session rehydration) for Claude Code. The git-commit trace/secret/bloat scan needs the full install (start.sh / adopt.sh).",
  "version": "${VERSION}",
  "author": { "name": "Barış Yerlikaya" },
  "homepage": "https://github.com/byerlikaya/claude-starter-kit",
  "repository": "https://github.com/byerlikaya/claude-starter-kit",
  "license": "MIT",
  "keywords": ["claude-code", "agents", "skills", "workflow", "hooks"]
}
JSON

echo "plugin/ generated (v${VERSION}): $(ls "$OUT/agents"/*.md | wc -l | tr -d ' ') agents, $(ls -d "$OUT/skills"/*/ | wc -l | tr -d ' ') skills, $(ls "$OUT/commands"/*.md | wc -l | tr -d ' ') commands, $(ls "$OUT/hooks"/*.sh | wc -l | tr -d ' ') hooks"
