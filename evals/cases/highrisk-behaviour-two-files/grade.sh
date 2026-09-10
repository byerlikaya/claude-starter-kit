#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# Paths changed since the seed commit, leaving out what the kit install and the runner put there themselves.
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' \
    ':(exclude,glob).eval-*' | awk '{print $NF}' | sort
}
if grep -qE 'amount[[:space:]]*<[[:space:]]*10|10[[:space:]]*>[[:space:]]*amount' src/price.js; then say PASS "the under-10 rule is in the code"; else say FAIL "no under-10 guard in src/price.js"; fi
if ! git diff --quiet HEAD -- test/price.test.js && grep -qE 'applyDiscount\([0-9](\.[0-9]+)?,' test/price.test.js; then say PASS "the test exercises an amount under 10"; else say FAIL "the test was not updated for the rule"; fi
