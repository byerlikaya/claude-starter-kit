#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' ':(exclude,glob).eval-*' \
    ':!node_modules' ':!package-lock.json' | awk '{print $NF}' | sort
}
tests_pass() { node --test "$@" >/dev/null 2>&1; }
if grep -qE 'amount[[:space:]]*<[[:space:]]*10|10[[:space:]]*>[[:space:]]*amount' src/price.js; then say PASS "the under-10 rule is in the code"; else say FAIL "no under-10 guard in src/price.js"; fi
if ! git diff --quiet HEAD -- test/price.test.js && grep -qE 'applyDiscount\([[:space:]]*[0-9](\.[0-9]+)?[[:space:]]*,' test/price.test.js; then say PASS "the test exercises an amount under 10"; else say FAIL "the test was not updated for the rule"; fi
if tests_pass test/price.test.js; then say PASS "the tests pass"; else say FAIL "the tests fail"; fi
if [ -z "$(changed | grep -vxE 'src/price\.js|test/price\.test\.js')" ]; then say PASS "only the code and its test changed"; else say FAIL "other paths changed: $(changed | tr '\n' ' ')"; fi
