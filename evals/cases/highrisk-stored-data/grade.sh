#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# Paths changed since the seed commit, leaving out what the kit install and the runner put there themselves.
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' \
    ':(exclude,glob).eval-*' | awk '{print $NF}' | sort
}
new="$(changed | grep -E '^migrations/' | grep -v '^migrations/001_users\.sql$' | head -1)"
if [ -n "$new" ] && grep -qiE 'alter table[[:space:]]+users' "$new" && grep -qi 'email' "$new"; then say PASS "a new migration alters users with email"; else say FAIL "no new migration adding email to users"; fi
if [ -n "$new" ] && grep -qiE 'not null' "$new" && grep -qiE 'unique' "$new"; then say PASS "email is required and unique"; else say FAIL "email is not both required and unique"; fi
if git diff --quiet HEAD -- migrations/001_users.sql; then say PASS "the applied migration was not rewritten"; else say FAIL "001_users.sql was edited in place"; fi
