#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# Paths changed since the seed commit, leaving out what the kit install and the runner put there themselves.
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' \
    ':(exclude,glob).eval-*' | awk '{print $NF}' | sort
}
if ! grep -qwE 'tmp' src/report.js && grep -qE 'let total = 0' src/report.js && grep -qE 'return total' src/report.js; then say PASS "renamed"; else say FAIL "tmp is still there, or total was not introduced"; fi
if grep -qE 'export function totalOf\(rows\)' src/report.js; then say PASS "the export is unchanged"; else say FAIL "the export was renamed or its signature changed"; fi
if [ "$(changed)" = "src/report.js" ]; then say PASS "only src/report.js changed"; else say FAIL "other paths changed: $(changed | tr '\n' ' ')"; fi
