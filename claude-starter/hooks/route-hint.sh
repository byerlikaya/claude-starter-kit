#!/usr/bin/env bash
# Route hint — name the owning agent next to the request itself.
#
# WHY THIS EXISTS, measured rather than assumed. The kit's premise is that specialist agents run the work. On a
# focused, single-domain request that does not happen: 42 measured sessions across the eval suite, two A/B pairs
# and a twelve-agent domain sweep produced ZERO spontaneous delegations. Two things were tried first and both
# came back zero — rewriting the agents' `description` into ownership language, and telling the discipline to
# call the Agent tool concretely. What DOES work is naming the agent explicitly: a command body that @-mentions
# its agents delegated 3 of 3, and a single request carrying twelve different jobs fanned out to all twelve
# owners correctly. So the mechanism is sound; the trigger is the shape of the request.
#
# The subagents docs list three inputs to the delegation decision: "the task description in your request, the
# `description` field in subagent configurations, and current context". The kit had touched the second and the
# third. This hook is the first: `UserPromptSubmit` can return `additionalContext`, and for that event the docs
# place it "alongside the submitted prompt" — the one position we had never used.
#
# It states an owner. It never decides FOR the model, never blocks, and stays silent unless a match is clear:
# a wrong route is worse than none, because it looks like the kit worked.
set -uo pipefail
IN="$(cat)"
case "$IN" in *'"hook_event_name"'*UserPromptSubmit*) ;; *) exit 0 ;; esac

# Two editions, two layouts: a full install puts the components under .claude/, the plugin ships them beside the
# hook itself. Resolve both or the plugin channel silently loses routing — the same one-channel-weaker failure
# the commit content gate had before 1.9.0.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/agents" ]; then
  AGENTS="${CLAUDE_PLUGIN_ROOT}/agents"; SKILLS="${CLAUDE_PLUGIN_ROOT}/skills"
else
  AGENTS="${CLAUDE_PROJECT_DIR:-.}/.claude/agents"; SKILLS="${CLAUDE_PROJECT_DIR:-.}/.claude/skills"
fi
[ -d "$AGENTS" ] || [ -d "$SKILLS" ] || exit 0

# The prompt text, taken as a raw slice: no jq dependency, and a partial read is fine because matching is by
# substring anyway. Everything after `"prompt":"` up to the closing quote that is not escaped.
PROMPT="$(printf '%s' "$IN" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)/\1/p' | sed 's/","[a-z_]*":.*$//' | head -c 4000)"
[ -n "$PROMPT" ] || exit 0

# Same normalisation the routing eval uses: Turkish diacritics folded, lowercased, every run of non-alphanumerics
# collapsed to one space, and the whole string space-padded so a match is word-bounded. Without the padding a
# short trigger hides inside a longer word — `UI` inside `build` once sent CI failures to the frontend expert.
norm() {
  printf '%s' "$1" | sed \
    -e 's/Ç/c/g' -e 's/ç/c/g' -e 's/Ğ/g/g' -e 's/ğ/g/g' -e 's/İ/i/g' -e 's/ı/i/g' \
    -e 's/Ö/o/g' -e 's/ö/o/g' -e 's/Ş/s/g' -e 's/ş/s/g' -e 's/Ü/u/g' -e 's/ü/u/g' \
    | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/ /g' -e 's/^/ /' -e 's/$/ /'
}
NP="$(norm "$PROMPT")"

# Score every installed agent by how many of its trigger phrases appear. Longest phrase wins ties: "state
# management" is a stronger signal than "state", and a two-word hit beats a one-word hit from another agent.
# Agents AND skills are scored. The agent answers "who owns this"; the skill answers "how is it done", and the
# skill is the cheaper, more useful nudge: a subagent re-pays its whole context (measured at 10-16k tokens for a
# no-op), while a skill just loads its method into the turn already in progress. Measured on a focused request,
# neither fired on its own — 12 domain tasks produced zero delegations and a skill in only 2 of 12 — so the
# method the kit exists to carry was simply absent from the work.
BEST=""; BESTSCORE=0; BESTKIND=""
for f in "$AGENTS"/*.md "$SKILLS"/*/SKILL.md; do
  [ -e "$f" ] || continue
  case "$f" in */SKILL.md) name="$(basename "$(dirname "$f")")"; kind=skill ;; *) name="$(basename "$f" .md)"; kind=agent ;; esac
  score=0
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    np2="$(norm "$ph")"
    # Suffix-tolerant, prefix-anchored: the trigger must START at a word boundary, but may carry up to three
    # trailing letters. Word-bounded matching alone silently lost every inflection — `component` did not match
    # "components", `test` did not match "tests" — which is how a hook that looked correct stayed quiet on two
    # thirds of real prompts. The boundary that matters is the LEADING one: it is what keeps `ui` out of `build`.
    if printf '%s' "$NP" | grep -qE "(^| )$(printf '%s' "$np2" | sed -e 's/^ //' -e 's/ $//' -e 's/[][\.*^$(){}?+|/]/\\&/g')[a-z]{0,3}( |$)"; then
      w=${#ph}; score=$((score + w))
    fi
  done <<EOF
$(grep -i "Trigger phrases:" "$f" | head -1 | grep -oE '"[^"]+"' | sed 's/"//g')
EOF
  # An AGENT outranks a SKILL whenever both match, regardless of score. The architecture is agent = who,
  # skill = how, and the agent applies its own skills anyway — so naming the agent delivers the method PLUS the
  # isolation and the audit path, while naming the skill delivers only the method. A skill is named only when no
  # agent owns the domain at all (iterate, reflect, worktree, eval-grader — the orchestrator's own work).
  if [ "$score" -gt 0 ]; then
    if [ "$kind" = agent ] && [ "$BESTKIND" != agent ]; then
      BESTSCORE=$score; BEST="$name"; BESTKIND=agent
    elif [ "$kind" = "$BESTKIND" ] || [ -z "$BESTKIND" ]; then
      [ "$score" -gt "$BESTSCORE" ] && { BESTSCORE=$score; BEST="$name"; BESTKIND="$kind"; }
    fi
  fi
done

# Silence is the default. No match, or a match too weak to be sure, means the main thread decides as before.
[ -n "$BEST" ] && [ "$BESTSCORE" -ge 6 ] || exit 0

# The wording is an INSTRUCTION, not a suggestion, and that distinction is the whole experiment. The first
# version hedged — "unless it is a one-line edit", "if it is genuinely not that agent's work, say so" — which
# handed the model two explicit ways to decline, and it took them: 4 of 12. The docs give the phrasing that
# works verbatim ("Use the test-runner subagent to fix failing tests"), so that is what goes in. A user typing
# "use frontend-expert-csk for this" gets obeyed without argument; there is no reason to write it more weakly
# just because a hook is doing the typing.
if [ "$BESTKIND" = skill ]; then
  MSG="Use the \`$BEST\` skill for this task."
else
  MSG="Use the $BEST subagent for this task."
fi
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$MSG"
