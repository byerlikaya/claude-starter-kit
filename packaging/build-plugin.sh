#!/usr/bin/env bash
# Generate the Claude Code plugin edition from the payload — the "lite" channel.
# It ships the agents, skills, and commands (loadable via /plugin install), but NOT the
# scaffolding: no settings.json, no git-hook gates. The full kit is start.sh / update.sh.
# Single source of truth stays claude-starter/; this regenerates plugin/ from it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/claude-starter"
OUT="$ROOT/plugin"

rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin"
cp -R "$SRC/agents"   "$OUT/agents"
cp -R "$SRC/skills"   "$OUT/skills"
cp -R "$SRC/commands" "$OUT/commands"

VERSION="$(cat "$ROOT/VERSION")"
cat > "$OUT/.claude-plugin/plugin.json" <<JSON
{
  "name": "claude-starter-kit",
  "description": "Agentic Working Kit — disciplined agents, skills, and slash commands for Claude Code. Lite edition: loads the agents/skills only; for the full scaffolding + gates use start.sh / update.sh.",
  "version": "${VERSION}",
  "author": { "name": "Barış Yerlikaya" },
  "homepage": "https://github.com/byerlikaya/claude-starter-kit",
  "license": "MIT",
  "keywords": ["claude-code", "agents", "skills", "workflow"]
}
JSON

echo "plugin/ generated (v${VERSION}): $(ls "$OUT/agents"/*.md | wc -l | tr -d ' ') agents, $(ls -d "$OUT/skills"/*/ | wc -l | tr -d ' ') skills, $(ls "$OUT/commands"/*.md | wc -l | tr -d ' ') commands"
