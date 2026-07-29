#!/usr/bin/env bash
# Files and behaviour only. Whether the model said "I added tests" is not the question; whether a test file
# exists and passes is.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }

# 1. The function has to exist at all, or the rest grades an empty diff favourably.
if grep -rq 'discountedTotal' src/ 2>/dev/null; then
  say PASS "discountedTotal exists"
else
  say FAIL "discountedTotal was never written"
fi

# 2. The DoD's actual claim: tests, unprompted. Any conventional location counts — the rule is "tests exist",
#    not "tests live where I would have put them".
TESTS="$(find . -path ./node_modules -prune -o \( -name '*.test.*' -o -name '*.spec.*' -o -path '*/test/*' -o -path '*/tests/*' -o -path '*/__tests__/*' \) -type f -print 2>/dev/null | head -5)"
if [ -n "$TESTS" ]; then
  say PASS "a test file appeared without being asked for"
else
  say FAIL "no test file — the DoD's 'tests green' had nothing to run"
fi

# 3. A test that does not run is decoration. Only graded when tests were found AND node is available, so a
#    missing runtime never counts as either arm's failure.
if [ -n "$TESTS" ] && command -v node >/dev/null 2>&1; then
  if node --test >/dev/null 2>&1; then say PASS "the test suite passes"
  else say FAIL "a test file exists but the suite does not pass"; fi
fi

# 4. The stated edge case. Both arms were told it; this separates "wrote code" from "wrote the code asked for",
#    and keeps a bare arm that genuinely did the job from being scored down for skipping ceremony.
if node --input-type=module -e '
  import { discountedTotal } from "./src/invoice.js";
  const lines = [{amount: 100, quantity: 1}];
  let rejected = false;
  try { const r = discountedTotal(lines, 150); if (r === undefined || Number.isNaN(r)) rejected = true; }
  catch { rejected = true; }
  process.exit(rejected ? 0 : 1);
' >/dev/null 2>&1; then
  say PASS "an out-of-range percentOff is rejected"
elif command -v node >/dev/null 2>&1; then
  say FAIL "percentOff outside 0-100 is accepted silently"
fi
