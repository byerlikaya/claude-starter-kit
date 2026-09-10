#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# Paths changed since the seed commit, leaving out what the kit install and the runner put there themselves.
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' \
    ':(exclude,glob).eval-*' | awk '{print $NF}' | sort
}
if grep -q 'receive' src/cart.js && ! grep -q 'recieve' src/cart.js; then say PASS "the typo is fixed"; else say FAIL "the typo is still there"; fi
if [ "$(git show HEAD:src/cart.js | grep -vE '^[[:space:]]*//')" = "$(grep -vE '^[[:space:]]*//' src/cart.js)" ]; then say PASS "no code line changed"; else say FAIL "code changed for a comment fix"; fi
if [ "$(changed)" = "src/cart.js" ]; then say PASS "only src/cart.js changed"; else say FAIL "other paths changed: $(changed | tr '\n' ' ')"; fi
