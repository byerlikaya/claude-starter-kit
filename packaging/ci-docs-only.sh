#!/usr/bin/env bash
# Reads changed paths on stdin, one per line, and prints `docs` when EVERY one of them is documentation, `code`
# otherwise. ci.yml uses it to skip the macOS and Windows jobs on a documentation-only pull request: those legs
# measure how bash, git and the installers behave on another OS, and a README edit cannot change that.
#
# The list is deliberately short and pinned by smoke-test.sh. A pattern that could match a script, a hook or
# anything under kit/ would let a real change skip the only platforms where it can break, so smoke goes red if
# one appears. An empty list is `code`: no diff to read means nothing is known, and unknown runs everything.
#
#   git diff --name-only BASE HEAD | bash packaging/ci-docs-only.sh
set -uo pipefail

# DOCS-PATTERNS-START
is_doc() {
  case "$1" in
    README*.md)         return 0 ;;
    site/content/*)     return 0 ;;
    evals/README.md)    return 0 ;;
    evals/results/*)    return 0 ;;
    CHANGELOG.md)       return 0 ;;
  esac
  return 1
}
# DOCS-PATTERNS-END

seen=0
while IFS= read -r f || [ -n "$f" ]; do
  f="${f%$'\r'}"
  [ -n "$f" ] || continue
  seen=1
  is_doc "$f" || { echo code; exit 0; }
done
[ "$seen" = 1 ] && echo docs || echo code
