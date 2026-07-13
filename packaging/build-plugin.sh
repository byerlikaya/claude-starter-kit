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

# The Claude Code hooks that work standalone (self-locate via $0, read stdin) — NOT the git hooks
# (pre-commit / commit-msg) and NOT their blocklist data files, which only apply under core.hooksPath.
for h in guard-bash.sh guard-write.sh context-usage.sh session-guard.sh session-rehydrate.sh; do
  cp "$SRC/hooks/$h" "$OUT/hooks/$h"
  chmod +x "$OUT/hooks/$h"
done

# hooks/hooks.json — auto-discovered by Claude Code when the plugin is enabled (no plugin.json field needed).
# Same structure as settings.json's "hooks", but paths resolve through ${CLAUDE_PLUGIN_ROOT} (the plugin's install
# dir) instead of ${CLAUDE_PROJECT_DIR}/.claude. Quoted heredoc: ${CLAUDE_PLUGIN_ROOT} stays literal for Claude Code.
cat > "$OUT/hooks/hooks.json" <<'HOOKS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard-bash.sh\"", "timeout": 30 }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard-write.sh\"", "timeout": 30 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/context-usage.sh\" 2>/dev/null || true", "timeout": 30 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-guard.sh\"", "timeout": 30 }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact|clear|resume",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-rehydrate.sh\"", "timeout": 30 }
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
