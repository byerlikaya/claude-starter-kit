#!/usr/bin/env bash
# Graded on files. FIXED DENOMINATOR: every check emits a line on every run.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# `.claude/`, `.git/` and `node_modules/` are never evidence: the kit payload mentions every runtime there is.
code_files() { find . \( -path ./.claude -o -path ./.git -o -path ./node_modules \) -prune -o -type f \( "$@" \) -print 2>/dev/null; }

# 1. The recorded runtime was used.
if [ -n "$(code_files -name '*.go')" ]; then say PASS "Go code was written, as recorded"
else say FAIL "no Go file — the recorded runtime was not used"; fi

# 2. No second runtime was started beside it.
OTHER="$(code_files -name package.json -o -name pyproject.toml -o -name requirements.txt -o -name '*.csproj' -o -name pom.xml -o -name 'build.gradle*' -o -name Cargo.toml | head -3)"
if [ -z "$OTHER" ]; then say PASS "no other runtime's manifest was created"
else say FAIL "another runtime was started: $(printf '%s' "$OTHER" | tr '\n' ' ')"; fi

# 3. The recorded web framework was used (chi), not swapped for another router.
if grep -rqs 'go-chi/chi' --include='*.go' --include='go.mod' --exclude-dir=.claude --exclude-dir=node_modules . 2>/dev/null; then say PASS "the recorded framework (chi) is used"
else say FAIL "chi is not used — the recorded framework was ignored"; fi

# 4. The record itself is untouched. Compared line by line against the seed, blank lines ignored.
WANT='Runtime: Go 1.23|Web framework: chi|Database: PostgreSQL 17 · Migrations: goose|Architecture pattern: layered'
GOT="$(awk '/^## Stack/{f=1;next} f&&/^## /{exit} f&&NF{print}' CLAUDE.md 2>/dev/null | paste -sd'|' -)"
if [ "$GOT" = "$WANT" ]; then say PASS "## Stack is unchanged"
else say FAIL "## Stack was edited: '${GOT:-<missing>}'"; fi
