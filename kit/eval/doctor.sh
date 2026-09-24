#!/usr/bin/env bash
# Install doctor — verify a LIVE kit install in a CONSUMER repo is actually active. This is the counterpart to
# smoke-test.sh: smoke-test checks the kit's SOURCE (dev-side, in this repo); doctor checks a real install on a
# user's machine — the things that silently make the gates inert: a hook left non-executable, core.hooksPath not
# set (so the commit trace/secret scan never runs), settings.json missing (so the tool-level gates never fire).
# Zero-dep, bash-only, Git-Bash safe. Run from the project root (or pass the path):  bash .claude/eval/doctor.sh
set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "doctor: cannot enter '$ROOT'"; exit 2; }

# Nothing here needs input, and everything here spawns subprocesses that INHERIT this script's stdin. A hook
# reads its payload with `cat`, so one invocation without a pipe would sit waiting for a terminal that is never
# going to type — which is exactly what a "ran 120s and produced nothing" report looks like. Detaching stdin once
# makes that class of hang impossible instead of relying on every call site remembering to redirect.
exec </dev/null

FAIL=0
ok(){  echo "  ✅ $1"; }
bad(){ echo "  ❌ $1"; echo "     ↳ fix: $2"; FAIL=$((FAIL+1)); }
warn(){ echo "  ⚠️  $1"; }
# `skip` lives up here with the other reporters, not down in the readiness block where it used to be
# defined: the health checks call it too, and a helper defined after its first caller is a silent
# no-op — the line never prints and the run shows `skip: command not found` on stderr, where nobody
# looks. Found by RUNNING doctor against a fixture install; grepping for the call sites said wired.
skip(){ echo "  ·  $1"; }

echo "== Claude Starter Kit — install doctor =="

# 0) Is the kit even here?
[ -d .claude ] || { echo "  ❌ no .claude/ in '$PWD' — is the kit installed here?"; echo "     ↳ fix: npx @byerlikaya/claude-starter-kit adopt"; exit 1; }

# 1) VERSION (marks a full install; also what /update-crew compares)
if [ -f .claude/VERSION ]; then ok "VERSION present ($(head -1 .claude/VERSION | tr -cd '0-9A-Za-z.-'))"
else bad "VERSION missing" "reinstall or update the kit (npx @byerlikaya/claude-starter-kit update)"; fi

# 1b) Is that version the current one? Read-only, from the cache session-update-check.sh maintains — doctor makes
#     no network call of its own, so this stays honest offline (no cache -> nothing said) and instant everywhere.
#     The session notice fires once per release; this is the surface that still answers when it was missed.
if [ -f .claude/VERSION ] && [ -f .claude/.state/update-check ]; then
  read -r DLATEST _ < .claude/.state/update-check 2>/dev/null || DLATEST=""
  DLATEST="$(printf '%s' "${DLATEST:-}" | tr -cd '0-9A-Za-z.-')"
  DCUR="$(head -1 .claude/VERSION 2>/dev/null | tr -cd '0-9A-Za-z.-')"
  if [ -n "$DLATEST" ] && awk -v a="$DLATEST" -v b="$DCUR" 'BEGIN{split(a,x,".");split(b,y,".");
       for(i=1;i<=3;i++){if(x[i]+0>y[i]+0)exit 0; if(x[i]+0<y[i]+0)exit 1} exit 1}'; then
    warn "kit v$DCUR installed, v$DLATEST published — update with /update-crew"
  fi
fi

# 2) Hooks present + executable. The .sh set is a glob (extras ok); pre-commit + commit-msg are REQUIRED — they
#    ARE the §4.1/§4.2 trace/secret gate, so a MISSING one is a failure, not a silent skip.
NX=""; GONE=""
for h in .claude/hooks/*.sh; do [ -e "$h" ] || continue; [ -x "$h" ] || NX="$NX $(basename "$h")"; done
for h in .claude/hooks/pre-commit .claude/hooks/commit-msg; do
  if [ ! -e "$h" ]; then GONE="$GONE $(basename "$h")"; elif [ ! -x "$h" ]; then NX="$NX $(basename "$h")"; fi
done
[ -z "$GONE" ] && ok "required git hooks present (pre-commit, commit-msg)" \
              || bad "MISSING git hook(s):$GONE — the commit trace/secret scan is absent" "reinstall or update the kit"
[ -z "$NX" ] && ok "all hooks are executable" \
             || bad "not executable:$NX" "chmod +x .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg"

# 2b) Behaviour probe — a hook that is present + executable can still be NEUTERED (its body replaced with `exit 0`).
#     Drive guard-bash with a command it MUST block; if it does not exit 2, the §4.5 gate is disarmed.
if [ -x .claude/hooks/guard-bash.sh ]; then
  # CSK_GATE_LOG=/dev/null: this probe drives the real gate, so without it every `/doctor-crew` writes a
  # synthetic "git push --force blocked" line into the evidence log — and the gate report would then be
  # counting the diagnostics instead of what the model reached for. A measurement tool that contaminates the
  # thing it measures is worse than none.
  if printf '%s' '{"tool_name":"Bash","permission_mode":"auto","tool_input":{"command":"git push --force"}}' | CSK_GATE_LOG=/dev/null bash .claude/hooks/guard-bash.sh >/dev/null 2>&1; then
    bad "guard-bash.sh did NOT block a force-push — the §4.5 gate is neutered/disarmed" "restore guard-bash.sh from the kit"
  else ok "guard-bash.sh blocks a force-push (gate live, not neutered)"; fi

  # 2c) The §4.6 review gate, probed the same way — and probed on the ONE case whose verdict cannot depend on
  #     this project's state. "git commit" alone is no probe: with a matching review-pass.json it legitimately
  #     passes §4.6, and under a mode that cannot prompt §4.4 blocks it anyway, so exit 2 would prove nothing
  #     about §4.6. A commit pointed at another worktree is refused by §4.6 whatever else is true here, and the
  #     verdict is read from the MESSAGE rather than the exit code for the same reason. Mode `default` so that a
  #     disarmed gate answers "ask" and exits 0 instead of colliding with §4.4's fail-closed branch. Nothing
  #     runs: this is a PreToolUse payload, not a command.
  PROBE46="$(printf '%s' '{"tool_name":"Bash","permission_mode":"default","tool_input":{"command":"git -C /nonexistent-crew-probe commit -m probe"}}' \
             | CSK_GATE_LOG=/dev/null bash .claude/hooks/guard-bash.sh 2>&1 >/dev/null)"
  case "$PROBE46" in
    *"4.6"*) ok "guard-bash.sh enforces the §4.6 review gate (gate live, not neutered)" ;;
    *)       bad "guard-bash.sh did NOT enforce §4.6 — a commit can land with no review of its diff" \
                 "restore guard-bash.sh from the kit (and check review-agent-crew still writes .claude/review-pass.json)" ;;
  esac
fi

# 3) core.hooksPath — without it the §4.1/§4.2 commit trace + secret/bloat scan never runs
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HP="$(git config --get core.hooksPath 2>/dev/null || true)"
  case "$HP" in
    */.claude/hooks|.claude/hooks) ok "core.hooksPath -> $HP (commit-time gates active)" ;;
    "") bad "core.hooksPath is unset — commit trace/secret/bloat gates are INACTIVE" "git config core.hooksPath .claude/hooks" ;;
    *)  bad "core.hooksPath -> $HP (not the kit's hooks)" "git config core.hooksPath .claude/hooks" ;;
  esac
else
  warn "not a git repo — commit gates need: git init && git config core.hooksPath .claude/hooks"
fi

# 4) settings.json wires the tool-level gates, and each event maps to a NON-EMPTY hook array (an empty [] wires
#    nothing). PreToolUse/UserPromptSubmit/Stop are required; SessionStart (rehydration) is a warn if absent.
S=.claude/settings.json
if [ -f "$S" ]; then
  # ONE READER on every machine: the kit's own awk JSON reader, the same file adopt.sh merges with. There were two
  # branches here — jq where jq ran, a name-and-bracket shape check where it did not — and the second could not
  # tell valid JSON from invalid at all, so a stock Windows box got a weaker doctor than a Mac. Now both get the
  # parse: validity, then each event's array length.
  SJ=.claude/eval/lib/settings-json.awk
  if [ ! -f "$SJ" ]; then
    bad "the kit's JSON reader is missing ($SJ) — settings.json cannot be checked" "update the kit"
  elif awk -v op=validate -f "$SJ" "$S" 2>/dev/null; then
    ok "settings.json is valid JSON"
    EMPTY=""
    for ev in PreToolUse UserPromptSubmit Stop; do
      n="$(awk -v op=len -v path="hooks.$ev" -f "$SJ" "$S" 2>/dev/null)"
      case "$n" in ''|0) EMPTY="$EMPTY $ev" ;; esac
    done
    [ -z "$EMPTY" ] && ok "settings.json wires PreToolUse / UserPromptSubmit / Stop (non-empty)" \
                    || bad "settings.json hook events empty or missing:$EMPTY — those gates won't fire" "restore settings.json from the kit"
    sn="$(awk -v op=len -v path=hooks.SessionStart -f "$SJ" "$S" 2>/dev/null)"
    case "$sn" in ''|0) warn "SessionStart not wired — session rehydration after /compact or /clear is inactive (update the kit)" ;; *) ok "SessionStart wired (session rehydration active)" ;; esac
  else bad "settings.json is invalid JSON" "fix the syntax by hand — restoring the kit's file would drop any hooks you added"; fi
  # `${CLAUDE_PROJECT_DIR}` inside a hook command is the shape that breaks on Windows, and it breaks invisibly.
  # Claude Code substitutes that placeholder into the command STRING before any shell sees it; on Windows the
  # value is `C:\Repos\app` and the separators are gone by the time bash reads it. The reported path was
  # `C:ReposApp/.claude/hooks/...` — every hook failed to launch and every gate was absent, while settings.json
  # looked perfectly correct on inspection. The kit now uses a RELATIVE path (hooks run in the project
  # directory), with a `cd` off the bare `$CLAUDE_PROJECT_DIR` as a belt for a session started in a subdirectory.
  # Bare `$VAR` is not the placeholder syntax, so Claude Code leaves it for the shell to expand.
  #
  # Reported on every platform, not only Windows: a repo is shared across machines, and the wiring is wrong on
  # all of them the moment one teammate is on Windows.
  if grep -q '\${CLAUDE_PROJECT_DIR' "$S" 2>/dev/null; then
    bad "settings.json wires hooks through the \${CLAUDE_PROJECT_DIR} placeholder — on Windows its separators are stripped before bash runs, so NO hook launches and every gate is silently absent" \
        "update the kit (npx @byerlikaya/claude-starter-kit adopt) — hook commands become: cd \"\$CLAUDE_PROJECT_DIR\" 2>/dev/null; bash .claude/hooks/<name>.sh"
  else
    ok "hook wiring carries no path placeholder (nothing for Windows to mangle)"
  fi
else
  bad "settings.json missing — the tool-level gates (commit approval, guards, context) are INACTIVE" "reinstall the kit"
fi

# 4a) Skill listing budget. Claude Code loads a listing of every skill's name + description into context each
#     session; the budget is 1% of the context window, and over it descriptions get truncated or dropped
#     "which can strip the keywords Claude needs to match your request" (skills docs). The failure is invisible:
#     the skills are all still installed and still listed BY NAME, they just stop matching. Reported, never
#     enforced — a project is free to ship many skills, it just needs to know the trade and the two documented
#     ways out (raise skillListingBudgetFraction, or set low-priority skills to "name-only" in skillOverrides).
if [ -d .claude/skills ]; then
  LISTING=$(for f in .claude/skills/*/SKILL.md; do
      [ -e "$f" ] || continue
      awk '/^---$/{c++; next} c==1' "$f" | awk '/^(name|description):/,0'
    done | wc -c | tr -d ' ')
  CW="${CONTEXT_WINDOW:-1000000}"; BUDGET=$((CW/100))
  if [ "$LISTING" -le "$BUDGET" ]; then
    ok "skill listing fits the budget (${LISTING} <= ${BUDGET} chars at 1% of a ${CW}-token window)"
  else
    warn "skill listing ${LISTING} chars EXCEEDS the ~${BUDGET} budget for a ${CW}-token window — Claude Code will"
    warn "  truncate or drop descriptions, and a skill whose description is gone stops matching requests."
    warn "  Fixes: raise \"skillListingBudgetFraction\" in settings, or set rarely-used skills to \"name-only\""
    warn "  in \"skillOverrides\". Re-check with a smaller CONTEXT_WINDOW=200000 to see your real model's budget."
    warn "  Which skills? bash .claude/eval/utilization.sh — it reports the ones nothing in this project reached."
  fi
fi

# 4b) Is delegation itself switched off? The documented way to stop Claude using ANY subagent is to deny the `Agent`
#     tool in permissions.deny. A project that does that keeps twelve agents on disk that can never run, and the only
#     symptom is that every task quietly happens on the main thread — which reads as "the kit does nothing" rather
#     than as a setting. Checked at every scope the CLI merges, because one line in ~/.claude/settings.json disables
#     delegation for every project on the machine. Denying it may be deliberate; this names it, it does not judge.
DENYSRC=""
for f in .claude/settings.json .claude/settings.local.json "$HOME/.claude/settings.json"; do
  [ -f "$f" ] || continue
  # A deny entry for the delegation tool, in any of its spellings, with or without an argument pattern. Read
  # with the kit's JSON reader, so "is Agent/Task in permissions.deny" is answered from the parse on every OS.
  # It used to need python3: on Windows — a Store stub, or nothing — the check degraded to "both words appear in
  # the file", a prompt instead of a verdict. An unreadable file is still NOT a silent pass (NOPY below).
  if [ ! -f "${SJ:-.claude/eval/lib/settings-json.awk}" ] || ! awk -v op=validate -f "${SJ:-.claude/eval/lib/settings-json.awk}" "$f" 2>/dev/null; then
    NOPY=1; MAYBEDENY="${MAYBEDENY:-} $f"; continue
  fi
  awk -v op=strings -v path=permissions.deny -f "${SJ:-.claude/eval/lib/settings-json.awk}" "$f" 2>/dev/null \
    | grep -qE '^(Agent|Task)([^A-Za-z0-9_]|$)' && DENYSRC="$DENYSRC $f"
done
if [ "${NOPY:-0}" = 1 ]; then
  warn "delegation check could not read:${MAYBEDENY} — not valid JSON (or the kit's reader is missing)."
  warn "  open it and check that Agent/Task is not under permissions.deny. If it is, no subagent can ever run."
fi
# `A && B && ok … || bad …` cannot express three outcomes. With no usable python3 the && chain is false, so the
# || arm fired and reported `the Agent tool is DENIED in:` — an empty list, a failure that had not been found,
# and a verdict of ❌ on a healthy install. It stayed invisible while `command -v python3` was the test, because
# on Windows the Store stub answered yes and NOPY was never set. Three states, three branches.
if [ -n "$DENYSRC" ]; then
  bad "the Agent tool is DENIED in:$DENYSRC — no subagent can ever run, so every agent on disk is dead weight" \
      "remove the Agent/Task entry from permissions.deny, or accept that this project runs main-thread-only"
elif [ "${NOPY:-0}" != 1 ]; then
  ok "delegation is enabled (the Agent tool is not denied)"
fi

# 5) Agent-name references resolve to an installed agent — checked across CLAUDE.md AND every local doc it points to
#    (its @imports and docs/*.md references). A brownfield takeover renames the project's agents to `-crew` ids, but
#    CLAUDE.md — or an orchestration doc it delegates to, e.g. "detail: docs/AGENTS.md" — may still name the OLD bare
#    agent. That name matches no installed agent, so delegation to it silently fails. Following CLAUDE.md's reference
#    chain catches the pointed-to docs too, while unreferenced prose (design/audit docs, code comments) is ignored —
#    so it stays complete without the false positives a blanket repo scan would raise.
if [ -f CLAUDE.md ] && ls .claude/agents/*.md >/dev/null 2>&1; then
  # Two pull-only agents are invoked explicitly (a commit needs approval; session health is emitted by a hook),
  # NOT auto-delegated — so a bare reference to them does not break delegation; it is only a naming inconsistency.
  PULL_AGENTS=" commit-agent-crew session-manager-crew "
  # Scan set = CLAUDE.md + the local .md files it references (one level: its @imports and any `docs/…md` path).
  SCAN="CLAUDE.md"
  for r in $(grep -oE '@?[A-Za-z0-9_./-]+\.md' CLAUDE.md 2>/dev/null | sed 's/^@//' | sort -u); do
    [ -f "$r" ] && [ "$r" != "CLAUDE.md" ] && SCAN="$SCAN $r"
  done
  # TWO awk passes, not a nested shell loop. This check used to run `sed|head|tr` per agent and then a
  # `grep|cut|tr|sed` for every (agent × scanned file) pair — 12 agents against a handful of docs is already
  # ~250 process spawns. On Linux/macOS that is invisible; on Windows, where Git Bash pays 62-135 ms per spawn
  # instead of ~1.7ms, doctor stopped dead right here and looked hung to the user who ran it. Same disease the
  # route-hint hook had, same cure: let awk do the looping. Two spawns, whatever the component count.
  CSK_AGENT_BASES="$(awk '
    FNR==1 { files[++nf]=FILENAME }
    !got[FILENAME] && /^name:[[:space:]]*/ {
      n=$0; sub(/^name:[[:space:]]*/,"",n); gsub(/[^a-zA-Z0-9-]/,"",n)       # same charset tr -cd kept
      if (n != "") { nm[FILENAME]=n; got[FILENAME]=1 }
    }
    END {
      for (i=1;i<=nf;i++) {
        f=files[i]; n=(f in nm) ? nm[f] : ""
        if (n=="") { n=f; sub(/\.md$/,"",n); sub(/.*\//,"",n) }              # fallback: the file name
        if (n ~ /-crew$/) { b=n; sub(/-crew$/,"",b); print b "\t" n }
      }
    }' .claude/agents/*.md)"
  export CSK_AGENT_BASES
  STALE=""; STALE_PULL=""
  while IFS="$(printf '\t')" read -r base name f lines; do
    [ -n "$base" ] || continue
    entry="
     ↳ \"$base\" → \"$name\"   ($f line(s): $lines)"
    case "$PULL_AGENTS" in *" $name "*) STALE_PULL="$STALE_PULL$entry" ;; *) STALE="$STALE$entry" ;; esac
  done <<EOF
$(awk '
  BEGIN {
    n = split(ENVIRON["CSK_AGENT_BASES"], rows, "\n"); k=0
    for (i=1;i<=n;i++) { if (rows[i]=="") continue; split(rows[i], a, "\t"); k++; base[k]=a[1]; full[k]=a[2] }
    nb=k
  }
  FNR==1 { order[++nf]=FILENAME }
  {
    # bare `base` NOT followed by `-` (so not base-crew) and not glued into a longer word — the identical
    # boundary the grep used. Agent ids are [a-z-] only, so nothing here needs regex escaping.
    for (i=1;i<=nb;i++)
      if ($0 ~ ("(^|[^a-zA-Z-])" base[i] "([^a-zA-Z-]|$)"))
        hit[i, FILENAME] = (hit[i, FILENAME]=="" ? FNR : hit[i, FILENAME] "," FNR)
  }
  # Emitted in agent order, then scanned-file order, so the report reads the same as it always did rather
  # than in awk hash order.
  END {
    for (i=1;i<=nb;i++)
      for (j=1;j<=nf;j++)
        if ((i, order[j]) in hit) print base[i] "\t" full[i] "\t" order[j] "\t" hit[i, order[j]]
  }' $SCAN)
EOF
  if [ -n "$STALE" ]; then
    bad "CLAUDE.md (or a doc it references) names auto-delegated agent(s) that no installed agent matches — delegation to them silently fails" \
        "rename each bare reference to its \`-crew\` id:$STALE"
  fi
  [ -n "$STALE_PULL" ] && warn "CLAUDE.md (or a referenced doc) names pull-only agent(s) by their old bare id — invoked explicitly, so delegation still works; rename for consistency:$STALE_PULL"
  [ -z "$STALE$STALE_PULL" ] && ok "agent references resolve to installed agents (CLAUDE.md + referenced docs)"
fi

# 6) Does the discipline actually REACH the model? `.claude/DISCIPLINE.md` sitting on disk is inert unless
#    `./CLAUDE.md` pulls it in — Claude Code reads CLAUDE.md, not the kit's own files. This is the one failure
#    every check above is blind to: the hooks fire, the gates are live, and yet §1–§3 (routing, DoD, session
#    management) never enter the context, so the model works without any of the discipline it is measured on.
#    Two shapes load it: the `@import` line, or the pre-1.1 layout that pasted the discipline inline (stale,
#    but loaded). Neither present -> absent, and that is a failure, not a style note.
if [ -f .claude/DISCIPLINE.md ]; then
  if [ ! -f CLAUDE.md ]; then
    bad "CLAUDE.md missing — .claude/DISCIPLINE.md is never loaded (routing / DoD / session rules absent)" \
        "create CLAUDE.md with this as its own line: @.claude/DISCIPLINE.md"
  elif grep -qE '^[[:space:]]*@\.claude/DISCIPLINE\.md[[:space:]]*$' CLAUDE.md; then
    ok "CLAUDE.md imports .claude/DISCIPLINE.md (the discipline reaches the model)"
  elif grep -q '^## Four working principles' CLAUDE.md && grep -qE '^### 4\.[45] ' CLAUDE.md; then
    warn "CLAUDE.md carries the discipline INLINE (pre-1.1 layout) — it loads, but kit updates never reach it; migrate to the '@.claude/DISCIPLINE.md' import line"
  else
    bad "CLAUDE.md does not import .claude/DISCIPLINE.md — the discipline is on disk but never loaded" \
        "add this as its own line at the top of CLAUDE.md: @.claude/DISCIPLINE.md"
  fi
fi

echo "---"
# The verdict is the line people read, and some read only it. The preflight block
# below reports a missing node, but it prints AFTER this — so on a machine that
# cannot start the panel the last word a reader takes away was "healthy". The
# verdict is not wrong (every gate is wired and holds without node) so it keeps
# its tick, and carries what it costs beside it.
# Resolved here rather than beside the preflight report below, because the verdict
# needs to ask it a question and the verdict prints first.
PREFLIGHT=".claude/eval/preflight.sh"
[ -f "$PREFLIGHT" ] || PREFLIGHT="$(dirname "$0")/preflight.sh"
PANEL_NOTE=""
if [ -d .claude/studio ] && ! bash "$PREFLIGHT" --has node 2>/dev/null; then
  PANEL_NOTE=" · panel needs Node 18+ — .claude/studio/ensure-node.sh --plan fetches one"
fi
if [ "$FAIL" -eq 0 ]; then echo "DOCTOR: healthy ✅$PANEL_NOTE"
  # Healthy verdict: the star line, once per kit version — the marker is shared with the installers, so the
  # doctor run that /update-crew makes right after an update stays quiet. Text/URL/silence: lib/star.sh.
  [ -f "$(dirname "$0")/lib/star.sh" ] && bash "$(dirname "$0")/lib/star.sh" --once .
else echo "DOCTOR: $FAIL issue(s) ❌ — apply the fixes above$PANEL_NOTE"; fi

# 8b) The shell matcher. Claude Code's hooks reference is explicit: inspect shell commands with
#     `Bash|PowerShell`, because wherever the PowerShell tool is enabled it IS the shell — and it is on by
#     default for claude.ai and Console accounts on Windows. An install from before 2.5.0 watches only `Bash`,
#     so every PowerShell command walks past the §4.5 rules with nothing firing. Nothing about the session
#     looks wrong, which is why this is a check and not a release note.
if [ -f .claude/settings.json ]; then
  if grep -q '"matcher"[[:space:]]*:[[:space:]]*"[^"]*PowerShell' .claude/settings.json; then
    ok "shell gates watch both Bash and PowerShell"
  elif grep -q '"matcher"[[:space:]]*:[[:space:]]*"Bash"' .claude/settings.json; then
    bad "shell gates watch only Bash — PowerShell commands bypass every §4.5 rule" \
        "update the kit (npx @byerlikaya/claude-starter-kit update), or set the PreToolUse matcher to \"Bash|PowerShell\""
  fi
fi
# 9) The auto-mode classifier. Since 2026-08-14 auto mode is the default permission mode on Pro/Max/Team, so a
#     classifier answers permission prompts the user used to answer. Two things can be wrong and neither shows
#     up in a session. Only ONE of them is a real gate finding: a custom autoMode block that dropped the
#     built-ins by omitting "$defaults" — 66 soft blocks gone, silently. Whether the kit's own rules are present
#     is reported but NOT treated as a failure: they were measured on 2026-08-24 not to enforce (see the skill).
if [ -x .claude/skills/automode-policy/scripts/check.sh ] || [ -f .claude/skills/automode-policy/scripts/check.sh ]; then
  AMOUT="$(bash .claude/skills/automode-policy/scripts/check.sh 2>&1)"; AMRC=$?
  case "$AMRC" in
    0) ok "auto-mode classifier config: built-ins intact, kit rules present (config, not a gate)" ;;
    2) bad "auto-mode classifier BUILT-INS DROPPED — an autoMode array lacks \"\$defaults\"" \
           "restore it in ~/.claude/settings.json; see .claude/skills/automode-policy/SKILL.md" ;;
    3) skip "auto-mode classifier config: kit rules absent (measured not to enforce — see the skill)" ;;
    # Same vocabulary as the other three branches on purpose. It used to read "auto-mode policy check
    # skipped", and the suite's assertion — written on a machine that HAS the claude CLI — never saw this
    # branch. CI has no CLI, so every run took it and the case failed on a wording difference, not a defect.
    *) skip "auto-mode classifier config: not checked (no claude CLI, or auto mode unavailable here)" ;;
  esac
  [ "$AMRC" = 2 ] && printf '%s\n' "$AMOUT" | grep 'auto-mode config' 
else
  warn "auto-mode policy check skipped (install predates the automode-policy skill; run the updater)"
fi
# 10) Gate activity. The suite proves the gates CAN fire; this reports whether anything actually tripped them.
#     Recording is on by default (rule names only, never the command), so "no log" here means no gate has
#     fired yet — a measured zero, not a gap. Never a failure either way.
if [ -f .claude/eval/gate-report.sh ]; then
  GOUT="$(bash .claude/eval/gate-report.sh 2>/dev/null)"; GRC=$?
  case "$GRC" in
    0) GL="$(printf '%s' "$GOUT" | grep -E 'decision\(s\)|no gate has fired' | head -1 | sed 's/^ *//')"
       [ -n "$GL" ] && ok "gate activity: $GL" || ok "gate activity recorded (see /gates-crew)" ;;
    3) skip "gate activity NOT MEASURED — nowhere to record (see /gates-crew)" ;;
    *) skip "gate activity unreadable (see /gates-crew)" ;;
  esac
fi
# --- Agentic readiness (ADVISORY) -------------------------------------------------------------------------
# Everything above answers "are the kit's gates live?". This answers a different question the gates cannot see:
# "is this PROJECT set up so an agent can actually work well in it?" A flawless install still starves its
# agents when the CLAUDE.md project section is left as the template, there is no sandbox to run in, and no
# project-specific skill carries the domain. These are project maturity, not install health, so they NEVER
# change the exit code — doctor's verdict stays a statement about the install.
echo
# The toolchain the install actually landed on. It runs here as well as in the installers because the machine
# changes after install day — a wiped PATH, a new laptop, a corporate image that removed jq — and the kit's
# fallbacks mean none of that announces itself. Advisory: it never changes the verdict above.
# doctor has already cd'd into the project, so the installed copy is the one to run; fall back to the copy
# sitting beside this script for the case where doctor is run straight out of the kit source.
[ -f "$PREFLIGHT" ] && bash "$PREFLIGHT"

echo "Readiness (advisory — does not affect the verdict above):"
RDY=0; RTOT=0
rdy(){ RTOT=$((RTOT+1)); RDY=$((RDY+1)); echo "  ✅ $1"; }
gap(){ RTOT=$((RTOT+1)); echo "  ➖ $1"; echo "     ↳ $2"; }

# R1) Is the CLAUDE.md project section filled in, or still the shipped template? An unfilled section means every
#     agent works stack-blind — it is the single most common way a correct install still underperforms.
if [ -f CLAUDE.md ]; then
  if grep -qE '<PROJECT NAME>|<One sentence:|<Fill in per the project' CLAUDE.md; then
    gap "CLAUDE.md project section is still the template (placeholders left in)" \
        "fill in Project / Stack / Project skills — agents read the stack from there"
  else rdy "CLAUDE.md project section is filled in"; fi
fi

# R2) A project-specific skill — the kit ships the generic 'how's; the domain ones (payment-contract,
#     notification-rules, a backend-pattern skill) are the project's to add. Needs the install manifest to tell
#     kit-shipped from project-owned; without it (pre-1.8 install) the signal is unknowable, so it is skipped
#     rather than guessed — a wrong "you have no project skills" is worse than no line at all.
MAN=.claude/kit-manifest.txt
if [ -f "$MAN" ]; then
  OWN=0
  # The CR strip is the whole reason this reads through `tr` rather than grepping the file directly, and it is
  # not defensive: MEASURED on a CRLF manifest with one project skill installed, this counted TWO. `grep -qxF`
  # wants a whole-line match, `skills/handoff\r` is not `skills/handoff`, so every KIT skill read as
  # project-owned. A Windows checkout with core.autocrlf produces exactly that manifest. `skill-trust.sh`
  # already strips it for the same reason and the same file — this was the copy that did not, which is why the
  # two answers disagreed on the same install.
  MANTXT="$(tr -d '\r' < "$MAN")"
  for d in .claude/skills/*/; do
    [ -d "$d" ] || continue
    printf '%s\n' "$MANTXT" | grep -qxF "skills/$(basename "$d")" || OWN=$((OWN+1))
  done
  [ "$OWN" -gt 0 ] && rdy "$OWN project-specific skill(s) alongside the kit's" \
                   || gap "no project-specific skill — only the kit's generic ones are installed" \
                          "put the domain 'how's in .claude/skills/ (format: .claude/AGENT_TEMPLATE.md)"
else
  skip "project-skill signal skipped (no .claude/kit-manifest.txt — install predates it; run the updater)"
fi

# R3) A sandbox to run in. Agentic work executes commands; a devcontainer is what makes that bounded rather
#     than trusting every command against the host.
if [ -f .devcontainer/devcontainer.json ]; then rdy "devcontainer present (agentic execution is sandboxed)"
else gap "no .devcontainer/devcontainer.json — agent commands run directly against your machine" \
         "add a devcontainer, or keep approval-mode gates on for anything destructive (§4.5)"; fi

# R4) MCP servers — the project's own tools/data reaching the model. Either the project-level .mcp.json or an
#     mcpServers block in the kit's settings counts.
if [ -f .mcp.json ] || grep -q '"mcpServers"' .claude/settings.json 2>/dev/null; then
  rdy "MCP servers configured (project tools/data reach the model)"
else gap "no MCP server configured — the model has no project-specific tool access" \
         "add .mcp.json when a tool/data source would help (the mcp-builder skill covers writing one)"; fi

# R5) Context freshness. CLAUDE.md is read once per session and is the only project-wide instruction the model
#     gets; if the code moved a long way since it was last touched, it is describing a project that no longer
#     exists. Counted as commits (not days) that changed something OUTSIDE .claude since CLAUDE.md's mtime —
#     mtime, not git history, because a default install gitignores CLAUDE.md and it has no history to read.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -f CLAUDE.md ]; then
  MT="$(stat -c %Y CLAUDE.md 2>/dev/null || stat -f %m CLAUDE.md 2>/dev/null)"
  MT="$(printf '%s' "${MT:-}" | tr -cd '0-9')"
  MAXC="${CSK_FRESHNESS_MAX:-40}"
  if [ -n "$MT" ]; then
    CH="$(git rev-list --count HEAD --since="@$MT" -- . ':(exclude).claude' 2>/dev/null | tr -cd '0-9')"
    CH="${CH:-0}"
    [ "$CH" -le "$MAXC" ] && rdy "CLAUDE.md is current ($CH commit(s) of drift since it was last touched)" \
                          || gap "CLAUDE.md is stale — $CH commits changed the project since it was last touched (limit $MAXC)" \
                                 "re-read it against the code and update Stack / Project skills (the claude-md-improver flow)"
  else skip "freshness signal skipped (cannot read CLAUDE.md mtime on this platform)"; fi
fi

[ "$RTOT" -gt 0 ] && echo "  → readiness $RDY/$RTOT"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
