#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' ':(exclude,glob).eval-*' \
    ':!node_modules' ':!package-lock.json' | awk '{print $NF}' | sort
}
tests_pass() { node --test "$@" >/dev/null 2>&1; }
if grep -qE '\.reduce\(' src/report.js; then say PASS "totalOf uses reduce"; else say FAIL "totalOf does not use reduce"; fi
if tests_pass test/report.test.js; then say PASS "the tests pass"; else say FAIL "the tests fail"; fi
if git diff --quiet HEAD -- test; then say PASS "the tests were not changed"; else say FAIL "the tests were changed"; fi
if [ "$(changed)" = "src/report.js" ]; then say PASS "only src/report.js changed"; else say FAIL "other paths changed: $(changed | tr '\n' ' ')"; fi
