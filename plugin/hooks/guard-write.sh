#!/usr/bin/env bash
# Claude Code PreToolUse guard for the FILE tools (Write / Edit / MultiEdit / NotebookEdit).
# Companion to guard-bash.sh: that one covers shell tampering, this one covers the model editing the gate
# scripts directly with its file tools. A gate you can silently rewrite is not a gate.
#
# stdin JSON: {"tool_name":"Write|Edit|...","tool_input":{"file_path":"...", ...}}
#
# HARD BLOCK (exit 2, every permission mode) when the target is a gate FILE:
#   - .claude/hooks/*       (guard-bash.sh, guard-write.sh, pre-commit, commit-msg, session-guard.sh, blocklists)
#   - .git/hooks/*          (the armed git hooks themselves)
#   - .claude/DISCIPLINE.md (kit-owned, @imported every session, and the text of §4.1-§4.5 itself — the gates
#     enforce those rules, so leaving the rules writable means the gates can be emptied without touching a gate)
# settings.json is deliberately NOT blocked: the update-config skill legitimately edits it, and a hook/permission
# change there is reviewable — the irreversible, silent move is rewriting the scripts, so that is what we gate.
#
# THE PATH IS NORMALISED BEFORE IT IS MATCHED, and that is the whole point of this file's second half.
# Until this version the gate compared the RAW string, so it recognised exactly one spelling of each gate path.
# Every line below was measured against the shipped hook and reached rc=0 — a SINGLE Write call, no shell
# access, no symlink, no second step:
#     .claude/skills/../hooks/guard-bash.sh      .claude//hooks/…       .claude/./hooks/…
#     .git/refs/../hooks/pre-commit              C:\…\.claude\hooks\…    (backslashes)
# The backslash row is a string fact, measured here: the matcher recognised `/` only, while five other hooks in
# this kit already fold Windows separators and this one did not. What a real Windows install actually puts in
# `file_path` is NOT measured on the machine this was written on and must not be assumed — it is verified on
# Windows. Folding both spellings is correct either way, which is why the fix does not wait for that answer.
# NotebookEdit was a sixth hole on any machine with neither jq nor python3 — the pre-tier-3 fallback read
# only `file_path`, and `notebook_path` is a different key.
# Claude Code passes file_path to the hook VERBATIM (measured: a `..` survives into the payload) while the
# filesystem resolves it, so the string the model writes and the file it opens are two different things.
# Normalise first, match second — and normalise with parameter expansion only, because this hook runs before
# EVERY Write/Edit and a fork per call is a freeze on Windows (Git Bash charges 62-135 ms per process, measured).
set -uo pipefail
INPUT="$(cat)"

# The two helpers below are a byte-identical copy of guard-bash.sh's block. A shared file would have to be
# added to build-plugin.sh's explicit copy list and a miss there breaks the plugin channel silently — the same
# reasoning as the CSK-TRANSCRIPT-DIR resolver, which is duplicated for the same reason. Two copies are only
# safe while they cannot drift, so smoke-test pins these markers byte-identical rather than trusting it.
# ---- CSK-JSON-PARSE ------------------------------------------------------------------------------------
_json_slice(){  # $1 = whole payload, $2 = key -> the raw (still JSON-escaped) string value, "" if absent
  local rest="${1#*\"$2\"}" seg tail out bs
  [ "$rest" != "$1" ] || return 0          # key absent: emit nothing
  rest="${rest#*\"}"                       # skip `: "` up to the value's opening quote
  out=""; tail="$rest"
  # Walk to the closing quote that is NOT escaped. A `"` preceded by an odd number of backslashes is content.
  while :; do
    seg="${tail%%\"*}"
    [ "$seg" != "$tail" ] || { out="$out$seg"; break; }   # no closing quote at all: take the rest
    out="$out$seg"
    bs="${seg##*[!\\]}"                    # trailing backslash run ("" when the last char is not a backslash)
    case "$seg" in *[!\\]*) ;; *) bs="$seg" ;; esac       # all-backslash segment: the run is the whole segment
    if [ $(( ${#bs} % 2 )) -eq 1 ]; then out="$out\""; tail="${tail#"$seg"\"}"; else break; fi
  done
  printf '%s' "$out"
}
_json_unescape(){  # single left-to-right pass; a two-pass sed would corrupt `\\"` (escaped backslash + quote)
  local s="$1" out="" c h
  case "$s" in *\\*) ;; *) printf '%s' "$s"; return 0 ;; esac   # no escapes: the common case pays nothing
  while [ -n "$s" ]; do
    c="${s%"${s#?}"}"; s="${s#?}"
    if [ "$c" = "\\" ] && [ -n "$s" ]; then
      c="${s%"${s#?}"}"; s="${s#?}"
      case "$c" in
        n) out="$out
" ;;
        t) out="$out	" ;;
        r) ;;
        b|f) out="$out " ;;
        u) h="${s%"${s#????}"}"; s="${s#????}"
           # A `\uXXXX` used to become a literal `?`. That is not a lossy nicety, it is a hole: `\u002e` is `.`,
           # so `\u002eclaude/hooks/guard-bash.sh` decoded to `?claude/…` and matched no gate pattern, while jq
           # decoded the same bytes to the real path — the two tiers disagreed on whether a payload was an
           # attack. Printable ASCII is decoded properly (builtin printf, no fork); anything else still becomes
           # `?`, which is only ever a display concern because this value is used for MATCHING, never to write.
           case "$h" in
             00[2-7][0-9a-fA-F]) printf -v c "\\x${h#00}"; out="$out$c" ;;
             *)                  out="$out?" ;;
           esac ;;
        *) out="$out$c" ;;
      esac
    else
      out="$out$c"
    fi
  done
  printf '%s' "$out"
}
# ---- /CSK-JSON-PARSE -----------------------------------------------------------------------------------

block(){  # $1 = rule name for the log (must keep the `gate-file edit` prefix — /gates-csk groups on it), $2 = why
  # Same write-only observability channel as guard-bash.sh, on by default into .claude/gate-log.tsv since 2.5.0
  # and with the same rule about the payload: the path is NOT recorded unless CSK_GATE_LOG_CMD=1, because
  # /gates-csk reports rule names and counts and never the argument. Logged after the verdict; it cannot
  # change it. CSK_GATE_LOG overrides the path; point it at /dev/null to turn recording off.
  _GL="${CSK_GATE_LOG:-}"
  if [ -z "$_GL" ] && [ -d ".claude" ]; then
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git check-ignore -q ".claude/gate-log.tsv" 2>/dev/null; then
      _GL=".claude/gate-log.tsv"
    fi
  fi
  if [ -n "$_GL" ]; then
    if [ "${CSK_GATE_LOG_CMD:-0}" = 1 ]; then
      printf 'BLOCK\t§4.5\t%s\t%s\n' "$1" \
        "$(printf '%s' "$FP" | tr -d '\000-\037' | cut -c1-200)" >> "$_GL" 2>/dev/null
    else
      printf 'BLOCK\t§4.5\t%s\t\n' "$1" >> "$_GL" 2>/dev/null
    fi
  fi
  echo "GUARD (§4.5): editing '$FP' is blocked AT THE TOOL LEVEL." >&2
  echo "$2" >&2
  echo "Kit updates go through the installer/update script, not the assistant's file tools. If the user explicitly wants it changed, they edit it in their own editor." >&2
  exit 2
}
WHY_SCRIPT="This file is a gate script — rewriting it would disarm the trace/secret/approval gates."
WHY_DISC="This file is the kit's discipline document — it IS the text of §4.1-§4.5, so editing it empties the rules the gates enforce."
WHY_LINK="A parent directory of this path is a symlink and it resolves into a gate directory, so the write would land on a gate file."
WHY_LONG="The path in this payload is longer than any filesystem accepts. It is refused rather than parsed, because parsing it is the slow path an attacker would aim at."
# Sized from the cost curve, not from PATH_MAX. Tier 3 walks the value character by character and bash string
# append is O(n) each time, so the walk is quadratic: measured 0.09s at 512 raw bytes, 0.52s at 1,024, 3.7s at
# 2,048, ~30s at 4,096. Real paths are nowhere near: measured on a Windows install, actual `file_path` values
# average ~60 bytes and Windows itself stops at 260 without the long-path opt-in (macOS PATH_MAX is 1,024).
# 2,048 therefore keeps every path anyone can really produce and bounds the worst case at a few seconds,
# well inside this hook's 60s timeout — the number that matters, because a hook killed at its timeout emits
# no exit 2 and the write proceeds.
MAXPATH=2048

# ---- extract ---------------------------------------------------------------------------------------------
# Tiers are selected on whether they WORK, not on whether they exist — see the long note in guard-bash.sh.
# Short version, measured on a stock Windows 11 desktop: Windows ships a Microsoft Store redirector stub named
# python3 on PATH by default, `command -v` finds it, it exits 49 with an empty stdout, FP came back "" and
# `[ -z "$FP" ] && exit 0` let the model rewrite .claude/hooks/guard-bash.sh with its Write tool.
FP=""; _parsed=0
if command -v jq >/dev/null 2>&1 && FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"; then
  _parsed=1
elif command -v python3 >/dev/null 2>&1 && FP="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("tool_input",{});print(d.get("file_path") or d.get("notebook_path") or "")' 2>/dev/null)"; then
  _parsed=1
fi
if [ "$_parsed" = 0 ]; then
  # Tier 3 is pure parameter expansion, so it cannot fail the way the two above can. It replaces a sed that
  # truncated the value at the first escaped quote and never looked at notebook_path.
  _raw="$(_json_slice "$INPUT" file_path)"
  [ -n "$_raw" ] || _raw="$(_json_slice "$INPUT" notebook_path)"
  # THE CAP GOES BEFORE THE UNESCAPER, and the cost it bounds is one THIS CHANGE INTRODUCES — worth saying
  # plainly rather than dressing up as a pre-existing bug. What it replaces was a single `sed`, which is linear
  # and was never slow; it was replaced because it truncated the value at the first escaped quote and never
  # looked at `notebook_path`. The parser that fixes those walks character by character, which is quadratic in
  # bash, and this is the tier a stock Windows install lands on — where every separator is a backslash, i.e.
  # an escape, so the "no escapes" fast path never fires. Uncapped, that is a gate with an off switch: a hook
  # killed at its 60s timeout emits no exit 2 and the write proceeds. Refusing above the cap is safe in the
  # direction that matters, and the cap sits far above any path a filesystem will accept.
  [ "${#_raw}" -le "$MAXPATH" ] || { FP="(oversized path: ${#_raw} bytes)"; block "gate-file edit (oversized path)" "$WHY_LONG"; }
  FP="$(_json_unescape "$_raw")"
fi
# The jq tier reaches the fold below with no unescaper in front of it, and a global replace on a huge string is
# quadratic too, so the cap is re-applied to whatever any tier produced.
[ "${#FP}" -le "$MAXPATH" ] || { FP="(oversized path: ${#FP} bytes)"; block "gate-file edit (oversized path)" "$WHY_LONG"; }

# Nothing extractable. Exiting 0 unconditionally is what a future field rename turns into a silent bypass, so
# look at the RAW payload instead: refuse only when the text itself names a gate tree. A payload that mentions
# no gate path still passes, so a rename cannot lock anyone out of ordinary work — it can only cost a false
# block on a file whose own path says `.claude/…hooks`, which is the trade this gate exists to make.
if [ -z "$FP" ]; then
  case "$INPUT" in
    *.claude*hooks*|*.git*hooks*|*DISCIPLINE.md*) FP="(unparsed payload naming a gate path)"; block "gate-file edit (unparsed payload)" "$WHY_SCRIPT" ;;
  esac
  exit 0
fi

# ---- normalise -------------------------------------------------------------------------------------------
# Windows separators first: the kit folds `\\` then `\` in five other hooks and this is the same idiom.
RP="${FP//\\\\//}"; RP="${RP//\\//}"; NP="$RP"
# Lexical resolution of `.`, `..` and repeated slashes. Lexical is the right kind here: it is what makes
# `.claude/skills/../hooks/x` and `.claude/hooks/x` the same string, it costs zero processes, and it cannot be
# defeated by a directory that does not exist yet (a `realpath` on an unborn path returns the input unchanged,
# which is exactly the hole this closes). Symlinks are the one thing lexical resolution gets wrong, and they
# are handled separately below.
_norm(){                               # assigns NORM; NOT `NP="$(_norm …)"` — a command substitution is a
  local p="$1" lead="" seg rest out="" # fork, and a fork per Write/Edit is the cost this whole file avoids
  case "$p" in /*) lead="/" ;; esac
  rest="$p"
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    case "$seg" in
      ''|'.') continue ;;
      '..')
        if [ -n "$out" ] && [ "${out##*/}" != ".." ]; then
          case "$out" in */*) out="${out%/*}" ;; *) out="" ;; esac
        elif [ -z "$lead" ]; then
          out="${out:+$out/}.."          # relative path climbing above the cwd: keep it, it is not a gate path
        fi
        continue ;;                      # absolute path at the root: `/..` is `/`, so drop it
    esac
    # Trailing dots and spaces are stripped from every component, because Win32 strips them when it OPENS the
    # file: `.claude./hooks/x` and `DISCIPLINE.md ` reach the same inode as the plain spelling there. The
    # `DISCIPLINE.md` rule is an exact tail match with no trailing wildcard, so one trailing byte defeated it.
    # This value is only ever compared, never written through, so a POSIX file genuinely named `foo.` is
    # unaffected in every way except that it would be matched as `foo`.
    while :; do case "$seg" in *.|*' ') seg="${seg%?}" ;; *) break ;; esac; done
    [ -n "$seg" ] || continue
    out="${out:+$out/}$seg"
  done
  NORM="$lead$out"
}
_norm "$NP"; NP="$NORM"

# ---- match -----------------------------------------------------------------------------------------------
# One place where "is this a gate file?" is answered, because it has to be asked twice — once on the path as
# written, once on the path as it resolves through a symlink.
#
# THE PATTERNS FOLD CASE. APFS and NTFS are case-insensitive by default, so `.CLAUDE/HOOKS/GUARD-BASH.SH` and
# `.claude/hooks/guard-bash.sh` are the SAME FILE — measured on this machine: identical inode, and a write
# through the uppercase spelling landed in the real gate script. The shell-side guard already folds case
# (`grep -i`), so the two guards disagreed on the same path. The bracket form needs no `shopt`, cannot leak
# into a later `case`, and works on bash 3.2.
_is_gate(){   # 0 = gate file; sets GATE_RULE and GATE_WHY
  case "$1" in
    */.[Cc][Ll][Aa][Uu][Dd][Ee]/[Hh][Oo][Oo][Kk][Ss]/*|.[Cc][Ll][Aa][Uu][Dd][Ee]/[Hh][Oo][Oo][Kk][Ss]/*)
      GATE_RULE="gate-file edit (Write/Edit tools)"; GATE_WHY="$WHY_SCRIPT"; return 0 ;;
    */.[Gg][Ii][Tt]/[Hh][Oo][Oo][Kk][Ss]/*|.[Gg][Ii][Tt]/[Hh][Oo][Oo][Kk][Ss]/*)
      GATE_RULE="gate-file edit (Write/Edit tools)"; GATE_WHY="$WHY_SCRIPT"; return 0 ;;
    */.[Cc][Ll][Aa][Uu][Dd][Ee]/[Dd][Ii][Ss][Cc][Ii][Pp][Ll][Ii][Nn][Ee].[Mm][Dd]|.[Cc][Ll][Aa][Uu][Dd][Ee]/[Dd][Ii][Ss][Cc][Ii][Pp][Ll][Ii][Nn][Ee].[Mm][Dd])
      GATE_RULE="gate-file edit (discipline document)"; GATE_WHY="$WHY_DISC"; return 0 ;;
    # The plugin edition keeps the SAME gate scripts at $CLAUDE_PLUGIN_ROOT/hooks/, which is not `.claude/hooks/`
    # and so matched nothing above — one of the kit's four channels shipped an unguarded copy of its own gates.
    # Matched by the kit's own filenames rather than by guessing a plugin path, so a project's unrelated
    # `hooks/` directory is untouched.
    */[Hh][Oo][Oo][Kk][Ss]/[Gg][Uu][Aa][Rr][Dd]-*.[Ss][Hh]|*/[Hh][Oo][Oo][Kk][Ss]/[Ss][Ee][Ss][Ss][Ii][Oo][Nn]-[Gg][Uu][Aa][Rr][Dd].[Ss][Hh])
      GATE_RULE="gate-file edit (kit gate script)"; GATE_WHY="$WHY_SCRIPT"; return 0 ;;
  esac
  return 1
}
_is_gate "$NP" && block "$GATE_RULE" "$GATE_WHY"

# The one thing lexical resolution cannot see: a symlinked ancestor. Two directions matter and only the second
# one is dangerous — a link INTO the config tree (`cfg -> .claude`, then write `cfg/hooks/guard-bash.sh`),
# which names no gate path at all and so passes every pattern above. Measured before this loop existed: rc=0,
# and the file really was overwritten. The reverse direction — a symlink ABOVE the project (`~/Projects ->
# /Volumes/…`, or plain `/tmp -> private/tmp` on macOS) — is routine and must stay allowed.
#
# So the walk runs for EVERY path (`[ -L ]` is a builtin: no process, and the loop is bounded), and only when
# an ancestor really is a symlink does it pay ONE fork to resolve it and ask the same question again about the
# real location. That fork is charged to the rare case instead of to every Write, which is what the hot-path
# budget requires; an ordinary repo pays nothing at all.
# The walk runs over RP — the folded path BEFORE `..` was collapsed — and that ordering is the rule, not a
# detail. Lexical `..` collapsing is only valid when no component before it is a symlink: with `c -> .claude/
# skills`, the written path `c/../hooks/guard-bash.sh` collapses to `hooks/guard-bash.sh` (no gate) while the
# filesystem resolves `c/..` through the link to `.claude`, landing on the real gate script. Collapsing first
# would delete the very component that has to be examined. Resolving from RP and re-normalising afterwards
# gets both: `<real>/.claude/skills` + `/../hooks/guard-bash.sh` normalises back onto the gate.
_anc="$RP"; _sfx=""; _depth=0
while case "$_anc" in */*) true ;; *) false ;; esac; do
  _depth=$((_depth+1)); [ "$_depth" -gt 64 ] && break
  _sfx="${_anc##*/}${_sfx:+/$_sfx}"
  _anc="${_anc%/*}"
  [ -n "$_anc" ] || break
  if [ -L "$_anc" ]; then
    _real="$(cd -P "$_anc" 2>/dev/null && pwd)"
    if [ -n "$_real" ]; then
      _norm "$_real/$_sfx"
      _is_gate "$NORM" && { FP="$FP  (resolves to $NORM)"; block "gate-file edit (symlinked ancestor)" "$WHY_LINK"; }
    fi
    break
  fi
done

# ---- team board: you may not start work nobody knows you started -----------------------------------------------
# The claim lock already makes it impossible for two people to HOLD the same item — a losing claim is refused in
# under a second, before any code exists. The hole this closes is the other one: somebody who never claims at all.
# Caught only at commit time, that is hours of work discovered as duplicated at the end, which is exactly the
# wasted effort the board exists to prevent. So the first file edit is where it is caught instead.
#
# Cost: this runs before EVERY Write/Edit, so it must not shell out. board.sh maintains a one-bit flag file
# (present == a board exists, it requires a claim, and this user holds none); everything here is a file test.
[ -n "${CSK_NO_BOARD:-}" ] && exit 0
GD=".git"
[ -d "$GD" ] || GD="$(git rev-parse --git-common-dir 2>/dev/null)"   # worktree/submodule: .git is a file
if [ -n "$GD" ] && [ -f "$GD/csk-board-guard" ]; then
  case "$FP" in
    */docs/*|docs/*|*/.claude/*|.claude/*) ;;   # planning notes and kit config are not the work being claimed
    *)
      echo "BOARD GATE: you hold no work item, so nobody else can see what you are starting." >&2
      echo "Claim one first: /board-csk  (lists what is free, what is blocked, and who holds the rest)." >&2
      echo "Work that belongs to no item: set CSK_NO_BOARD=1 for this session, and commit it with [chore]." >&2
      echo "Just claimed one elsewhere? The board view is cached — /board-csk sync refreshes it." >&2
      exit 2 ;;
  esac
fi
exit 0
