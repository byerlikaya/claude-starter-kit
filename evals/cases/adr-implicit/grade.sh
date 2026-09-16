#!/usr/bin/env bash
# Graded on what a maintainer would find six months later, exactly like adr-recorded — but here nothing in the
# prompt said a decision was being made, so a pass means the model recognised one on its own.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }

# 1. The work has to have been done, or a record describes something that does not exist.
if grep -rqiE 'tenant' src/limits.js 2>/dev/null; then
  say PASS "the limiter is actually scoped to the tenant"
else
  say FAIL "src/limits.js still holds the global ceiling — nothing was applied"
fi

# 2. Is the reasoning anywhere durable? Any path, any filename — the rule is that it survives, not that it
#    lives at docs/adr/0001-….md.
#
#    `.claude/` is excluded for the reason adr-recorded records: the kit's own payload discusses rate limits
#    and tenancy, so counting it would let the treatment pass on its own shipped text. A harness that reads the
#    treatment as evidence measures nothing but its own presence.
DOC="$(grep -rliE 'tenant' --include='*.md' . 2>/dev/null \
        | grep -v node_modules | grep -v '^\./\.claude/' | grep -v '^\./README\.md$' | head -3)"
if [ -n "$DOC" ]; then
  say PASS "the reasoning is written down ($(printf '%s' "$DOC" | tr '\n' ' '))"
else
  say FAIL "no document records why it is this way — only the code knows"
fi

# 3. THE CHECK THIS CASE EXISTS FOR. A note saying "made it per-tenant" records the outcome, which the diff
#    already shows. What a future maintainer needs is the question that was open and the answer that lost:
#    per-tenant vs per-user vs per-key, and what happens to a request that carries no tenant. Emitted
#    unconditionally so both arms are judged over the same number of checks — an arm that writes nothing and an
#    arm that writes a document must not end up with different denominators.
if [ -z "$DOC" ]; then
  say FAIL "no document exists, so no alternative is recorded either"
elif grep -rqiE 'per-user|per user|per-key|per key|global|instead of|rather than|alternative|rejected|trade-?off' $DOC 2>/dev/null; then
  say PASS "the record names what was weighed, not only what was built"
else
  say FAIL "the record states the outcome the diff already shows, and not the choice behind it"
fi

# 4. The decision nobody asks about until it bites: a request with no tenant. Recording that this was thought
#    about is the difference between a decision and an accident.
if grep -rqiE 'no tenant|without a tenant|missing tenant|null tenant|untenanted|anonymous' $DOC src/limits.js 2>/dev/null; then
  say PASS "the untenanted request is accounted for somewhere"
else
  say FAIL "nothing says what happens to a request that carries no tenant"
fi
