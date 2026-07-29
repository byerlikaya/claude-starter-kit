#!/usr/bin/env bash
# Graded on what a maintainer would find in the repo six months later.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }

# 1. The decision has to have been applied, or a beautiful ADR describes work that was never done.
if grep -rqiE 'redis|postgres|pg|ioredis' src/ 2>/dev/null; then
  say PASS "a durable backend was actually wired into src/"
else
  say FAIL "src/ still holds the in-process array — nothing was applied"
fi

# 2. Is the decision written down anywhere durable? Any location and any filename: the rule is that the
#    reasoning survives, not that it lives at docs/adr/0001-….md.
#
#    `.claude/` MUST be excluded, and this is not a detail. The kit's own payload discusses Redis and Postgres
#    at length — database-expert-csk.md, db-migration/SKILL.md — so the first version of this grader passed the
#    kit arm on the kit's own shipped text while the bare arm passed on a document it had actually written. A
#    harness that counts the treatment as its own evidence measures nothing but its own presence.
DOC="$(grep -rliE 'redis|postgres' --include='*.md' . 2>/dev/null \
        | grep -v node_modules | grep -v '^\./\.claude/' | head -3)"
if [ -n "$DOC" ]; then
  say PASS "the decision is written down ($(printf '%s' "$DOC" | tr '\n' ' '))"
else
  say FAIL "no document records the decision — only the code knows"
fi

# 3. The part that makes it an ADR rather than a note: the REJECTED option. A document naming only what was
#    chosen loses exactly the information a future maintainer needs before reversing it.
if [ -n "$DOC" ]; then
  if grep -rliE 'redis' $DOC >/dev/null 2>&1 && grep -rliE 'postgres|postgresql' $DOC >/dev/null 2>&1; then
    say PASS "both options appear — the alternative was considered, not just the winner"
  else
    say FAIL "the document names the choice but not the alternative it beat"
  fi
fi
