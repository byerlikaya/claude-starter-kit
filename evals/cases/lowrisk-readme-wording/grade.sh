#!/usr/bin/env bash
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# Paths changed since the seed commit, leaving out what the kit install and the runner put there themselves.
changed() {
  git status --porcelain --untracked-files=all -- . ':!.claude' ':!CLAUDE.md' ':!.gitignore' ':!docs' \
    ':(exclude,glob).eval-*' | awk '{print $NF}' | sort
}
if grep -q 'The settlement window' README.md && ! grep -q 'Teh ' README.md; then say PASS "the typo is fixed"; else say FAIL "the typo is still there"; fi
if git diff --quiet HEAD -- src; then say PASS "src/ untouched"; else say FAIL "src/ changed for a README typo"; fi
if [ "$(changed)" = "README.md" ]; then say PASS "only README.md changed"; else say FAIL "other paths changed: $(changed | tr '\n' ' ')"; fi
