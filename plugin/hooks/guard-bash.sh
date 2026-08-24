#!/usr/bin/env bash
# Claude Code PreToolUse (Bash) guard. PreToolUse runs in EVERY permission mode, including bypass.
# stdin JSON: {"tool_name":"Bash","tool_input":{"command":"..."},"permission_mode":"default|acceptEdits|auto|dontAsk|plan|bypassPermissions"}
#
# §4.5 destructive operations -> HARD BLOCK (exit 2). No key, no mode, no escape.
#
# §4.4 git commit / git push -> ASK THE USER, IN SESSION. The hook answers with
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask", ...}}
# and Claude Code escalates to a permission prompt that ONLY the human can answer. Approve once and Claude
# runs the commit itself — you never have to paste commands into your own terminal. The model cannot
# self-approve (it never sees the keypress) and cannot forge the decision (this hook is a separate process).
#
# Verified on Claude Code 2.1.205: a hook "ask" is honoured — the tool does not run until the user says yes —
# in permission_mode default, acceptEdits, auto and dontAsk. It is NOT verified under bypassPermissions, so
# there (and for any mode this hook does not recognise, i.e. anything added in a future release) we FAIL
# CLOSED and hard-block instead of trusting a prompt that may never reach the user.
#
# That gap was carried as "unverified" for a long time, as though a measurement would eventually close it.
# Checked against the published hooks reference (2026-07-29): the docs describe permissionDecision and they
# describe the permission modes, but they say NOTHING about how the two interact, or whether hooks run at all
# under bypassPermissions. So there is no documented contract to rely on — and a security gate resting on
# observed-but-unspecified behaviour is a bug even while it happens to work, because nothing stops a release
# from changing it. Failing closed is therefore the correct answer regardless of what a test would show, and
# this stops being an open question: it is a decision. Should the interaction ever be specified, revisit.
#
# CSK_GATE_LOG=<path>, exported by the user, appends one TSV line per gate decision (BLOCK/ASK/ALLOW, section,
# rule, command) to that file. Absent by default and write-only — it never influences a verdict. It exists
# because a gate that cannot be observed firing cannot be measured: "the model never tried it" and "the gate
# stopped it" leave identical artifacts behind. guard-write.sh writes to the same file.
#
# CLAUDE_GIT_OK=1, exported by the user before the session starts, pre-authorises the session. It exists for
# headless/CI runs where no one is at the keyboard. It does NOT replace approval: present the message first.
set -uo pipefail
INPUT="$(cat)"

# Extract the command + the permission mode: jq > python3 > pure-bash JSON slice.
#
# THE THIRD TIER IS NOT A DEGRADED MODE, it is the Windows default. Git Bash ships neither jq nor python3, so
# on a stock Windows install this is THE path every gate decision takes. It used to read `CMD="$INPUT"` — the
# whole hook payload handed to the rules as though it were the command — and that is not a weaker gate, it is
# a WRONG one, in both directions:
#   * False positive, measured: session_id `...-f872-...` (any session id whose second group starts `f8`) contains `-f8`, the §4.5 force-push rule matches
#     `-f([^a-z]|$)`, and so EVERY `git push` was hard-blocked as "push --force" no matter what was typed.
#     A gate that blocks the innocent teaches the user to reach for --no-verify, which disarms all of §4.
#   * Broken approval, measured: when it did not misfire, the §4.4 prompt rendered the raw JSON blob as "the
#     command Claude wants to run". §4.4's entire purpose is to show the human what they are approving; an
#     unreadable prompt is consent theatre.
# CI never caught it because GitHub's windows-latest image HAS jq preinstalled — the verification ran on a path
# no Windows user is on. smoke-test §7b pins the fallback branch itself for exactly that reason.
#
# The slice is pure parameter expansion: zero forks, so it is CHEAPER than the sed it replaces (Git Bash charges
# 20-50ms per process, and this hook runs on every Bash call). `${INPUT#*"command"}` is shortest-match, so it
# takes the FIRST occurrence — greedy matching would let a command containing the literal text `"command":"`
# relocate the parse and walk a payload straight past the rules.
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
  local s="$1" out="" c
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
        u) s="${s#????}"; out="$out?" ;;
        *) out="$out$c" ;;
      esac
    else
      out="$out$c"
    fi
  done
  printf '%s' "$out"
}
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  PERM_MODE="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
  PERM_MODE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("permission_mode",""))' 2>/dev/null)"
else
  CMD="$(_json_unescape "$(_json_slice "$INPUT" command)")"
  PERM_MODE="$(_json_slice "$INPUT" permission_mode)"
fi
PERM_MODE="${PERM_MODE:-}"
[ -z "$CMD" ] && exit 0

# Gate observability. A gate that cannot be seen firing cannot be measured: "the model never reached for the
# command" and "the gate stopped it" leave behind exactly the same artifacts, and the A/B harness spent a whole
# case (evals/permission-pressure) unable to tell them apart — it had to report "guard-bash never fired" as an
# inference. One TSV line per decision, write-only, and it never touches the decision itself: every call site
# logs AFTER the verdict is settled.
#
# ON BY DEFAULT since 2.5.0, into .claude/gate-log.tsv — an evidence channel nobody switches on records nothing,
# and "the gates hold" is a claim that needs a record, not a test suite alone. CSK_GATE_LOG overrides the path;
# CSK_GATE_LOG=/dev/null (or a read-only .claude) turns it off. Only BLOCK/ASK decisions reach here, so an
# ordinary command writes nothing.
#
# The COMMAND TEXT IS NOT RECORDED by default. It is the one field that can carry a path, an argument or a
# token, and `/gates-csk` never prints it — the report is rule names and counts. Recording it by default would
# buy nothing and add a place for a secret to sit. `CSK_GATE_LOG_CMD=1` puts it back for debugging a false
# positive, which is the only thing it is good for.
# Where the default log may go. An explicit CSK_GATE_LOG is the operator's call and is used as given. The
# DEFAULT path is only used when writing there cannot surprise anyone: outside a git repo, or inside one where
# the path is already ignored. A kit install gitignores .claude/, so this is the normal case — but the plugin
# edition drops into repos the installer never touched, and this repo proved the failure itself: the suite left
# a gate-log.tsv sitting in `git status` as an untracked file waiting to be committed. One `git check-ignore`
# runs only when a gate actually fires (never on an allowed command), so the hot path is untouched.
_gatelog_path(){
  if [ -n "${CSK_GATE_LOG:-}" ]; then printf '%s' "$CSK_GATE_LOG"; return; fi
  [ -d ".claude" ] || return 0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git check-ignore -q ".claude/gate-log.tsv" 2>/dev/null || return 0
  fi
  printf '%s' ".claude/gate-log.tsv"
}
gatelog(){  # $1 = verdict (BLOCK|ASK|ALLOW)  $2 = section  $3 = rule
  _GL="$(_gatelog_path)"; [ -n "$_GL" ] || return 0
  if [ "${CSK_GATE_LOG_CMD:-0}" = 1 ]; then
    printf '%s\t§%s\t%s\t%s\n' "$1" "$2" "$3" \
      "$(printf '%s' "$CMD" | tr -d '\000-\037' | cut -c1-200)" >> "$_GL" 2>/dev/null || true
  else
    printf '%s\t§%s\t%s\t\n' "$1" "$2" "$3" >> "$_GL" 2>/dev/null || true
  fi
}

block(){
  gatelog BLOCK "$2" "$1"
  echo "GUARD (§$2): '$1' stopped AT THE TOOL LEVEL." >&2
  echo "This destructive operation is only performed if the user EXPLICITLY requests it. If approved, run the command manually in the terminal." >&2
  exit 2
}

# One matcher for "git invoked with subcommand X", tolerant of the forms that used to slip past the old
# 'git +subcmd' rules: interposed options (git -C <path> …, git -c k=v …), TAB separators, and a
# quote/backtick/paren/pipe right before `git` (eval "git …", bash -c 'git …', `git …`, and the raw-JSON
# fallback where CMD is the whole blob and git is preceded by the `"` of "command":"). The boundary
# [^A-Za-z0-9_-] before git = any non-word char (so mygit / gitk / digit never match); the token run
# [^;&|[:space:]]+ skips -C/-c and their values up to the subcommand. Used by BOTH the §4.5 blocks and the
# §4.4 approval gate, so the destructive ops no longer have a weaker matcher than commit/push.
git_has() {  # $1 = command text, $2 = subcommand alternation (e.g. 'commit|push')
  # The subcommand is the first NON-option token after `git`. We skip only git GLOBAL OPTIONS — the value-taking
  # ones (-C <path>, -c <kv>, --git-dir/--work-tree/--namespace/--config-env/--super-prefix/--exec-path <v>) consume
  # their next token, plain flags don't. Skipping *arbitrary* tokens (the old behaviour) would false-match a commit
  # whose MESSAGE contains a subcommand word, e.g. git commit -m "reset --hard".
  # Trailing boundary allows quote/backtick/backslash too, so an argless subcommand that ends the string works in
  # the raw-JSON fallback (CMD is the whole blob; `git push` appears as …"git push" — push is followed by `"`).
  printf '%s' "$1" | grep -qiE "(^|[^A-Za-z0-9_-])git[[:space:]]+((-[Cc][[:space:]]+[^[:space:];&|]+|--(git-dir|work-tree|namespace|config-env|super-prefix|exec-path)[[:space:]=]+[^[:space:];&|]+|-[^[:space:];&|]+)[[:space:]]+)*($2)([[:space:]]|[;&|\"'\`\\\\]|\$)"
}
has() { printf '%s' "$CMD" | grep -qiE -- "$1"; }   # flag/substring test on the command (-- so a -flag pattern is safe)

{ git_has "$CMD" 'reset'  && has '--hard'; }                                                && block "git reset --hard" "4.5"
{ git_has "$CMD" 'push'   && has '(--force(-with-lease|-if-includes)?|-f([^a-z]|$)|[[:space:]]\+[A-Za-z])'; } && block "git push --force" "4.5"
{ git_has "$CMD" 'clean'  && has '-[A-Za-z]*f'; }                                           && block "git clean -f" "4.5"
has '--no-verify'                                          && block "hook skip (--no-verify)" "4.5"
git_has "$CMD" 'rebase'                                    && block "git rebase" "4.5"
git_has "$CMD" 'filter-branch|filter-repo'                && block "git filter-branch/filter-repo" "4.5"
{ git_has "$CMD" 'commit' && has '--amend'; }                                              && block "git commit --amend" "4.5"
# Scoped to targets carrying `/`, `*` or `~` ON PURPOSE — `rm -rf build` is a routine local delete and blocking
# it would make the gate noise. What was NOT on purpose: the recursive flag was matched as lowercase `r` in one
# short cluster, so `rm -Rf /`, `rm -fR /`, `rm -f -r /` and `rm --recursive --force /` all walked past while
# `rm -rf /` was blocked. Same class as the chmod hole found in evals/permission-pressure: one spelling gated,
# another reaching the identical state. Case, flag order and the long form are all the same command.
echo "$CMD" | grep -qE 'rm +(-[A-Za-z]* +|--[a-z-]+ +)*(-[A-Za-z]*[rR][A-Za-z]*|--recursive)( +(-[A-Za-z]+|--[a-z-]+))* +.*(/|\*|~)' && block "destructive rm -rf" "4.5"
# A whole-tree `git checkout -- .` / `git restore .` destroys every uncommitted change with no reflog and no
# undo — the same loss as `reset --hard`, which has been gated since the beginning, by a command that was not.
# Not hypothetical: a verification subagent ran exactly this over uncommitted work in this repo and took the
# working tree with it. Scoped to the WHOLE-TREE pathspec (`.` · `*` · `./` · `:/`) on purpose — reverting one
# named file is an everyday, recoverable act and gating it would make the rule noise. The option-skipping
# prefix is git_has's, so `git -C <path>` and `git -c k=v` cannot walk around it and a commit MESSAGE
# containing the word "checkout" does not trip it; both are pinned as cases.
echo "$CMD" | grep -qE '(^|[^A-Za-z0-9_-])git[[:space:]]+((-[Cc][[:space:]]+[^[:space:];&|]+|--(git-dir|work-tree|namespace|config-env|super-prefix|exec-path)[[:space:]=]+[^[:space:];&|]+|-[^[:space:];&|]+)[[:space:]]+)*(checkout|restore)([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+(\.|\*|\./|:/)([[:space:]]|[;&|]|$)' && block "whole-tree revert (git checkout/restore over everything)" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])(mkfs|dd +if=)'       && block "disk-level destructive command" "4.5"

# §4.5 remote-code-execution & permission-nuke -> HARD BLOCK. A downloaded script piped straight into a shell
# runs code no one has read; a world-writable chmod or a disk-overwriting dd is irreversible.
echo "$CMD" | grep -qE '(curl|wget|fetch)([^|]|\|\|)*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|python[0-9.]*|node|perl|ruby)([[:space:]]|$)' && block "pipe-to-shell (curl|bash RCE)" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])dd[[:space:]]+([^|]*[[:space:]])?of='  && block "dd of= (disk overwrite)" "4.5"
# The rule is WORLD-WRITABLE, so the pattern matches the resulting permission and not one spelling of it. It
# used to match `777`, `0777`, `a+rwx` and `+rwx` only, which let `1777`, `2777`, `666` and `o+w` reach exactly
# the same state — and this was not theoretical: in the A/B harness (evals/permission-pressure) a model asked to
# open a directory "wide enough for any account" reached for `chmod 1777` unprompted, sticky bit and all. A gate
# that blocks one spelling while another arrives at the same place has protected nothing.
# Numeric: 3 or 4 octal digits whose LAST digit carries the write bit for other (2·3·6·7). Symbolic: any subject
# list containing `o` or `a`, with `+` or `=`, granting `w`. `755`, `644`, `u+w` and `chmod +x` stay untouched —
# each of those carries its own case in smoke-test §7, because a gate this repo cannot prove is not a gate.
echo "$CMD" | grep -qE '(^|[^a-zA-Z])chmod[[:space:]]+(-[A-Za-z]*[[:space:]]+)*([0-7]?[0-7][0-7][2367]|[ugoa]*[oa][ugoa]*[+=][rwxXst]*w[rwxXst]*|a=?\+?rwx|\+rwx)([[:space:]]|$)' && block "chmod world-writable (777/1777/666/o+w …)" "4.5"

# §4.5 PowerShell equivalents -> HARD BLOCK. The PowerShell tool sends the SAME payload shape (tool_input.command)
# and Claude Code's own hooks reference says to match `Bash|PowerShell`, because on Windows wherever that tool is
# enabled PowerShell IS the shell — and with no Git Bash the Bash tool is never registered at all. The git rules
# above already carry over (git's syntax does not change), but every POSIX-shaped rule below them missed its
# PowerShell twin. Measured on this payload before the rules existed: `Remove-Item -Recurse -Force C:\proj\*`,
# `rm -Recurse -Force .`, `irm https://x/i.ps1 | iex` and `Get-Content .env` all returned rc=0 — allowed.
#
# Two PowerShell facts these patterns are built on:
#   * parameters match on any unambiguous PREFIX, so -Recurse is also -Rec/-r and -Force is also -Fo/-f;
#   * the destructive verbs have short aliases (rm/del/erase/rd/ri for Remove-Item), and `rm` there is
#     Remove-Item, not POSIX rm — the same word with different flags, which is why the POSIX rule misses it.
PS_RM='(remove-item|ri|rm|rmdir|rd|del|erase)'
PS_RECURSE='-r(e(c(u(r(s(e)?)?)?)?)?)?([[:space:]]|$)'
PS_FORCE='-f(o(r(c(e)?)?)?)?([[:space:]]|$)'
# Recursive+forced removal aimed at a glob, a drive root, a UNC path, or $HOME — the shapes that take a tree out.
{ has "(^|[^A-Za-z0-9_-])$PS_RM[[:space:]]" && has "$PS_RECURSE" && has "$PS_FORCE" \
  && has '(\*|[A-Za-z]:\\|\\\\|\$HOME|\$env:USERPROFILE|~)'; } \
  && block "PowerShell recursive force delete (Remove-Item -Recurse -Force)" "4.5"
# Download-and-execute, the PowerShell shape of curl|bash: any fetcher piped into Invoke-Expression.
echo "$CMD" | grep -qiE '(invoke-webrequest|iwr|invoke-restmethod|irm|curl|wget)[^|]*\|[[:space:]]*(invoke-expression|iex)([[:space:]]|$)' \
  && block "PowerShell download-and-execute (… | iex)" "4.5"
# Disk-level destruction. No POSIX equivalent of these names, so the mkfs/dd rule never saw them.
echo "$CMD" | grep -qiE '(^|[^A-Za-z0-9_-])(format-volume|clear-disk|remove-partition|initialize-disk|set-disk)([[:space:]]|$)' \
  && block "PowerShell disk-level destructive command" "4.5"
# World-writable ACL: icacls is what chmod 777 looks like on Windows.
echo "$CMD" | grep -qiE '(^|[^A-Za-z0-9_-])icacls\b[^;&|]*/grant[^;&|]*(everyone|users|authenticated users)[^;&|]*:\(?[^)]*[FM]' \
  && block "PowerShell world-writable ACL (icacls /grant Everyone:F)" "4.5"

# §4.5 gate-tampering -> HARD BLOCK. A gate you can silently remove is not a gate: redirecting core.hooksPath,
# or deleting/overwriting/patching the hook scripts, would disarm the trace/secret/approval gates in one line.
echo "$CMD" | grep -qE 'git[[:space:]]+config\b[^|]*core\.hooksPath'                       && block "git config core.hooksPath (disarms the git hooks)" "4.5"
# Inline config override: `git -c core.hooksPath=…` / `git --config-env core.hooksPath=…` turns the hooks off for
# that one command WITHOUT the word `config` (so the rule above misses it) — the exact equivalent of --no-verify.
echo "$CMD" | grep -qiE 'git[[:space:]]+([^;&|]*[[:space:]])?(-c|--config-env)[[:space:]=]+core\.hooksPath' && block "git -c core.hooksPath (disarms the git hooks)" "4.5"
# A write to a gate path (hook script, settings.json, or .git/hooks) via ANY common mechanism — writer verbs, the
# in-place editors, and the interpreters an evasion reaches for (perl/python/ruby/node/ed) — plus the variable-
# indirected redirect (VAR=.claude/hooks; … > $VAR). Reading a gate file stays allowed, and `chmod +x` is NOT
# blocked so doctor's re-arm fix still works (a chmod -x disable is caught by doctor, not here). Honest scope:
# the shell is Turing-complete, so this is defence-in-depth — guard-write.sh covers the Write/Edit tools (the
# model's natural path to a file), and install-time read-only hook files would be the airtight layer.
GATE='\.(claude/(hooks|settings\.json)|git/hooks)'
# Scoped to ONE command segment. These used to span `[^|]*`, which crosses `;` and `&&`, so the writer verb and
# the gate path only had to appear somewhere in the same line — `cp a b && bash .claude/hooks/board.sh status`
# was refused as tampering. That was harmless while nobody typed a hook path; the team board made
# `.claude/hooks/board.sh` an everyday argument, and a gate that fires on ordinary work is the one people learn
# to route around. A verb in one command and a path in another was never evidence of anything: the two forms
# that matter — `rm .claude/hooks/x` and `x > .claude/hooks/y` — both put them in the SAME segment, and both
# are still blocked (asserted in smoke-test, in both directions).
echo "$CMD" | grep -qiE "(rm|mv|cp|truncate|tee|install|ln|perl|python[0-9.]*|ruby|node|ex|ed|set-content|add-content|clear-content|out-file|new-item|rename-item|copy-item|move-item|remove-item)\b[^;&|]*$GATE" && block "write/tamper of a gate file (hook/settings/.git-hooks)" "4.5"
echo "$CMD" | grep -qiE "(sed|perl|awk|ruby)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-i[^;&|]*$GATE"          && block "in-place edit of a gate file" "4.5"
# The redirect TARGET must be the gate path, not merely something later on the line: a target is one token, so
# it cannot contain whitespace or a command separator.
echo "$CMD" | grep -qiE ">[[:space:]]*['\"]?[^[:space:];&|<>]*$GATE"                                          && block "redirect over a gate file" "4.5"
{ has "=[^;&|]*$GATE" && has '>>?[[:space:]]*\$'; }                                                          && block "indirected write to a gate path (variable + redirect)" "4.5"

# §4.5-adjacent: a .env file holds secrets. The settings.json Read-tool deny does NOT cover the Bash tool, so a
# `cat .env` would surface them. Block the direct-file readers/copiers and a `< .env` input redirect on a
# .env / .env.<env> file; the templates (.env.example/.sample/.template/.dist) stay readable. Arg-taking readers
# (grep/awk/sed) are deliberately excluded — there a `.env` token is usually a search pattern, not the file.
# The PowerShell readers sit in the SAME alternation rather than in a rule of their own: one concern, one rule.
# `cat` was already here and happens to be a PowerShell alias for Get-Content, which is exactly how this gap
# stayed invisible — the alias worked, so the rule looked like it covered PowerShell while Get-Content/gc/type
# walked straight through.
# `Select-String`/`sls` is left OUT on purpose, for the same reason grep/awk/sed are: it takes the pattern
# first, so `.env` on that line is as likely to be what is being searched for as what is being searched.
{ { has '(^|[^A-Za-z0-9_/.-])(cat|less|more|head|tail|tac|nl|xxd|od|strings|hexdump|base64|sort|uniq|cp|scp|rsync|get-content|gc|type|get-item|gi)[[:space:]]+(-[^;&|[:space:]]*[[:space:]]+)*([^;&|[:space:]]*/)?\.env(\.[A-Za-z0-9_-]+)?([[:space:]]|$|[;&|>])' \
    || has '<[[:space:]]*([^;&|[:space:]]*/)?\.env(\.[A-Za-z0-9_-]+)?([[:space:]]|$|[;&|])'; } \
    && ! has '\.env\.(example|sample|template|dist)([^A-Za-z0-9_-]|$)'; } \
    && block "reading a .env secret via the Bash tool" "4.5"

# The same reasoning, one scope wider. `.env` was the only credential file either gate covered, which left the
# ones that actually unlock other systems wide open: an SSH private key, AWS credentials, a kubeconfig, a .netrc.
# Read them and they are in the context, one summary or one web call away from leaving the machine — and unlike a
# commit, nothing downstream scans for that. Reader verbs only (grep/awk/sed still take these as patterns), and
# a PUBLIC key or a .pub/.example path stays readable because neither is a secret.
CRED='(\.ssh/(id_[A-Za-z0-9_]+|identity)|(^|/)id_(rsa|dsa|ecdsa|ed25519)|\.aws/credentials|\.netrc|\.git-credentials|\.docker/config\.json|\.npmrc|\.pypirc|kube/config|kubeconfig|\.(pem|p12|pfx|keystore|jks)|service-account.*\.json)'
{ { has "(^|[^A-Za-z0-9_/.-])(cat|less|more|head|tail|tac|nl|xxd|od|strings|hexdump|base64|cp|scp|rsync|curl|wget|get-content|gc|type|get-item|gi)[[:space:]]+(-[^;&|[:space:]]*[[:space:]]+)*[^;&|[:space:]]*$CRED" \
    || has "<[[:space:]]*[^;&|[:space:]]*$CRED"; } \
    && ! has '(\.pub|\.example|\.sample|\.template)([^A-Za-z0-9_-]|$)'; } \
    && block "reading a private key / credential file via the Bash tool" "4.5"

# §4.5 force-add bypasses .gitignore (sneaks build output / secrets past the bloat & ignore rules); deleting a
# lockfile is a §4.5 op the discipline already names. Both are only done on an explicit request.
{ git_has "$CMD" 'add' && has '(-[A-Za-z]*f[A-Za-z]*|--force)([[:space:]]|$)'; } && block "git add -f (bypasses .gitignore)" "4.5"
echo "$CMD" | grep -qE '(rm|git[[:space:]]+rm)\b[^|]*(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|npm-shrinkwrap\.json|Gemfile\.lock|poetry\.lock|Pipfile\.lock|Cargo\.lock|composer\.lock|go\.sum|packages\.lock\.json)' && block "lockfile deletion" "4.5"

# --- §4.4 commit/push approval gate ---
# Escape a shell string into a JSON string body. A raw control character inside a JSON string is a parse
# error, and the reason text is attacker-adjacent (it is the model's own command line), so:
#   - delete every control char except tab and newline (this also removes CR, which a CRLF here-doc leaks);
#   - fold a surviving tab to a space (display-only text; the command Claude runs is untouched);
#   - escape backslash and double quote;
#   - fold newlines to the two-character \n escape.
json_escape(){
  printf '%s' "$1" \
    | tr -d '\000-\010\013-\037\177' \
    | tr '\011' ' ' \
    | sed 's/\\/\\\\/g; s/"/\\"/g' \
    | awk 'NR>1{printf "\\n"} {printf "%s", $0}'
}
# Escalate to a permission prompt only the user can answer, then let Claude run the command itself.
ask_user(){
  gatelog ASK 4.4 "commit/push approval prompt"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  exit 0
}
# A pre-authorised session has to clear BOTH gates, and only an explicit decision does that.
allow_preauthorised(){
  gatelog ALLOW 4.4 "CLAUDE_GIT_OK pre-authorised session"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "CLAUDE_GIT_OK: session pre-authorised before it started (§4.4 headless/CI)")"
  exit 0
}
# The approval-gated git set is guarded in two places: this hook asks for commit/push, and settings.json also
# asks for `git add` and `git checkout -b`. The key used to answer only the first, by exiting 0 — which means
# "this hook has no opinion" and leaves the settings rule in force. So a headless run could not even STAGE,
# while §4.4 advertised the key as the way to work with nobody at the keyboard: the flag's only purpose, and
# it did not achieve it. Measured with the A/B harness (evals/), where the kit arm proposed a commit and
# stopped in every run while the bare arm committed freely.
# Reached only AFTER the §4.5 blocks above, so a pre-authorised session still cannot force-push, amend,
# reset --hard or `git add -f` — the key opens the approval gate, never the destructive one.
if git_has "$CMD" 'add|commit|push|checkout'; then
  # The key is granted by the user's environment, never by the command line the model composes.
  if printf '%s' "$CMD" | grep -q 'CLAUDE_GIT_OK'; then
    gatelog BLOCK 4.4 "approval key set inside the command"
    echo "GUARD (§4.4): the attempt to set the approval key (CLAUDE_GIT_OK) inside the command was rejected." >&2
    echo "The key is set only by the user, before the session starts." >&2
    exit 2
  fi
  case "${CLAUDE_GIT_OK:-}" in
    1|yes|true|on|YES|TRUE|ON) allow_preauthorised ;;   # pre-authorised session (headless/CI)
  esac
fi
if git_has "$CMD" 'commit|push'; then
  case "$PERM_MODE" in
    default|acceptEdits|auto|dontAsk)
      # A prompt provably reaches the user in these modes: ask, and let them approve in one keypress.
      SHORT="$CMD"
      [ "${#SHORT}" -gt 300 ] && SHORT="$(printf '%s' "$SHORT" | cut -c1-300)…"
      # §4.4 branch guard: committing straight onto main/master is not blocked (a fresh project legitimately
      # lives on main), but it is surfaced in the approval prompt so the user can send it to a branch instead.
      BRANCH_WARN=""
      case "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" in
        main|master) BRANCH_WARN="⚠️  This commits DIRECTLY to the default branch. Prefer a feature branch unless you meant to.

" ;;
      esac
      ask_user "§4.4 commit/push approval gate. Claude wants to run:

$SHORT

${BRANCH_WARN}Approve only if the commit message above was shown to you and you agree with it. Approving lets Claude run the command itself."
      ;;
    *)
      # bypassPermissions, plan, or an unrecognised/absent mode: we cannot prove the prompt would reach a
      # human, so we fail closed rather than let the gate silently evaporate.
      gatelog BLOCK 4.4 "commit/push under a mode that cannot prompt (${PERM_MODE:-unknown})"
      echo "GUARD (§4.4): 'git commit/push' is gated by approval AT THE TOOL LEVEL, and this session's permission mode ('${PERM_MODE:-unknown}') cannot show you an approval prompt." >&2
      echo "Present the commit MESSAGE to the user and get EXPLICIT approval. Then either:" >&2
      echo "  (a) the user re-runs Claude in a normal permission mode, where this gate asks them directly and Claude commits, OR" >&2
      echo "  (b) the user starts the session with 'CLAUDE_GIT_OK=1' (headless/CI), OR" >&2
      echo "  (c) the user runs the command in their own terminal." >&2
      exit 2 ;;
  esac
fi

exit 0
