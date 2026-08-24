#!/usr/bin/env bash
# Install the kit's auto-mode classifier policy into USER settings — the one part of the kit that lives
# outside the project, because the classifier deliberately ignores `autoMode` in .claude/settings.json
# (a repo could otherwise ship its own allow rules). Writing outside the project is exactly the kind of
# action §4.4 says needs the user's word, so this script asks, backs up, and verifies — in that order.
#
# Usage:
#   apply.sh              propose the change, show the diff, ask, install, verify
#   apply.sh --yes        same without the prompt (for a scripted setup the user drives)
#   apply.sh --strict     also set autoMode.classifyAllShell — every shell command reaches the classifier
#   apply.sh --print      print the policy fragment and exit (paste it yourself; no writes, no tooling)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
POLICY="$HERE/../references/policy.json"
CHECK="$HERE/check.sh"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
YES=0; STRICT=0
for a in "$@"; do case "$a" in
  --yes) YES=1 ;; --strict) STRICT=1 ;;
  --print) cat "$POLICY"; exit 0 ;;
  *) echo "apply.sh: unknown argument '$a'"; exit 64 ;;
esac; done

[ -f "$POLICY" ] || { echo "❌ policy.json not found next to this script"; exit 1; }

# A JSON merge into the user's own settings file is not a job for sed. Without a JSON tool we print the
# fragment and stop: a half-merged global settings file is worse than an uninstalled policy.
MERGER=""
command -v jq      >/dev/null 2>&1 && MERGER=jq
[ -z "$MERGER" ] && command -v python3 >/dev/null 2>&1 && MERGER=python3
if [ -z "$MERGER" ]; then
  echo "⚠️  neither jq nor python3 is available — not merging your settings file by hand."
  echo "   Add this block to $TARGET yourself (keep the \"\$defaults\" entries verbatim):"
  echo; cat "$POLICY"; exit 3
fi

mkdir -p "$(dirname "$TARGET")"
[ -f "$TARGET" ] || printf '{}\n' > "$TARGET"

TMP="$TARGET.csk-new"; BAK="$TARGET.csk-bak-$(date +%Y%m%d-%H%M%S)"
if [ "$MERGER" = jq ]; then
  jq -s '.[0] * .[1]' "$TARGET" "$POLICY" > "$TMP" || { echo "❌ merge failed (invalid JSON in $TARGET?)"; rm -f "$TMP"; exit 1; }
  [ "$STRICT" = 1 ] && { jq '.autoMode.classifyAllShell = true' "$TMP" > "$TMP.2" && mv "$TMP.2" "$TMP"; }
else
  python3 - "$TARGET" "$POLICY" "$TMP" "$STRICT" <<'PY' || { echo "❌ merge failed (invalid JSON in the target?)"; exit 1; }
import json,sys
tgt,pol,out,strict=sys.argv[1:5]
cur=json.load(open(tgt)); add=json.load(open(pol))
am=dict(cur.get("autoMode") or {}); am.update(add["autoMode"])
if strict=="1": am["classifyAllShell"]=True
cur["autoMode"]=am
json.dump(cur,open(out,"w"),indent=2,ensure_ascii=False); open(out,"a").write("\n")
PY
fi

# Verify the CANDIDATE before it is anyone's real configuration. `claude --settings <file>` runs the
# classifier config resolution against the file, so a policy that would silently drop the 66 built-in
# soft blocks is caught here — while the only file on disk is still a temp file.
echo "== verifying the candidate (nothing installed yet) =="
bash "$CHECK" --settings "$TMP"; RC=$?
if [ "$RC" != 0 ]; then
  echo "❌ candidate did not verify (rc=$RC) — nothing was written."
  rm -f "$TMP"; exit "$RC"
fi

echo
echo "== what changes in $TARGET =="
if command -v diff >/dev/null 2>&1; then diff -u "$TARGET" "$TMP" | sed -n '1,60p'; else echo "(no diff tool; new file written to $TMP)"; fi
echo
if [ "$YES" != 1 ]; then
  # No terminal means no one can consent. Asking anyway is worse than useless: with a tty present but nobody
  # reading it — a CI runner, a background job, a test harness — `read </dev/tty` blocks forever. Measured:
  # this hung the kit's own smoke test. No consent possible -> abort, and say how to do it deliberately.
  if [ ! -t 0 ] && [ ! -t 1 ]; then
    echo "not an interactive session — nothing written. Re-run with --yes if this is a setup you are driving."
    rm -f "$TMP"; exit 0
  fi
  printf "Install this policy into your USER settings? [y/N] "
  read -r ans </dev/tty 2>/dev/null || ans=""
  case "$ans" in y|Y|yes|YES) : ;; *) echo "aborted — nothing written."; rm -f "$TMP"; exit 0 ;; esac
fi

cp "$TARGET" "$BAK" && mv "$TMP" "$TARGET" || { echo "❌ could not write $TARGET"; exit 1; }
echo "✅ installed. backup: $BAK"
echo "== verifying what the classifier now actually uses =="
bash "$CHECK"; RC=$?
if [ "$RC" != 0 ]; then
  echo "❌ post-install verification failed (rc=$RC) — restoring the backup."
  cp "$BAK" "$TARGET"; exit "$RC"
fi
echo "   Undo any time:  cp \"$BAK\" \"$TARGET\""
