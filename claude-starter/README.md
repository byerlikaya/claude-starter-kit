# Agentic Working Kit — installed kit

This project has been equipped with a Claude Code working kit. The kit runs the work with the same discipline at every stage:
**plan → generate → audit → commit** — and the quality and security at each step rely not on the model remembering,
but on gates at the tool level. All of the kit's behavior rules live in the root `CLAUDE.md`; this file
summarizes what lives under `.claude/` and how it works.

## Three principles

1. **Agent = thin trigger.** An agent only states "who, when"; it stays short and leaves the how of the work to the skill.
2. **Skill = single source of truth.** The actual method and rules live in the skill; they are not copied into the agent.
3. **Rule → gate.** An important rule is enforced at the tool level (hook · permission · eval); it is not expected to be remembered.

## What's inside `.claude/`

- **Agents** (`agents/`) — one thin trigger per role: planning, backend, database, security,
  privacy, testing, frontend, devops, review, commit, and session management. Names carry a `-csk`
  suffix so that this kit's agents do not clash with the project's own agents.
- **Skills** (`skills/`) — the single source of the "how" knowledge: code review, security scan,
  migration, deployment, observability, performance, accessibility, translation integrity, versioning,
  incident response, and more. (The installed set may be pruned according to the chosen profile.)
- **Commands** (`commands/`) — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hooks** (`hooks/`) — `guard-bash.sh` (tool-level gate), `pre-commit` + `commit-msg`
  (trace scan), `context-usage.sh` and `session-guard.sh` (session measurement), `trace-blocklist.txt`.
- **settings.json** — permissions and the hook chain (PreToolUse · UserPromptSubmit · Stop).
- **`DISCIPLINE.md`** — behavior, four principles, workflow, definition of done, token discipline, and prohibitions.
  Kit-owned: an update **overwrites** it, so keep nothing of your own here. Your `./CLAUDE.md` pulls it in with a
  single `@.claude/DISCIPLINE.md` line and holds your project rules, which win on conflict.
- **`kit.conf`** — the profile and backend stack this project was installed with. The updater reads it so a refresh
  reshapes the project the way it was installed, instead of re-adding what the profile pruned.
- **AGENT_TEMPLATE.md** — the contract for opening a new agent/skill.

## Workflow

`/plan` (ambiguous scope) → expert agents generate → `/review` (security · quality · testing) →
`/ship` (DoD gate; proposes the commit, waits for approval) → when context fills up, `/handoff` → `/clear`.

## Session and token management

An assistant cannot run the `/context` command itself; that is why most setups guess the context fill.
This kit measures it. `context-usage.sh` reads the real token count of the last turn in the transcript;
the `UserPromptSubmit` hook injects this into the context every turn; the `Stop` hook (`session-guard.sh`) surfaces
the handover suggestion to you the first time the fill **crosses 75%**, and again at **90%** — one warning per
threshold, and it warns rather than blocks, so it costs no extra model turn. This way the session-health line rests
on a measurement, not on a guess.

## Token cost

`DISCIPLINE.md` plus the agent and skill descriptions load into every session's context — **9,198 tokens** measured on
a real turn. `smoke-test.sh` fails when a component exceeds its byte budget, so keep them lean. Trigger phrases are the
routing signal and must never be trimmed away; the prose around them can be. The per-turn `🔋` line is compact for the
same reason — `--verbose` gives the long form on demand.

## Updating

Run `npx @byerlikaya/claude-starter-kit@latest update` at the project root. `.claude/` is refreshed (including
`DISCIPLINE.md`), `./CLAUDE.md` and your own agents/skills are left alone, and everything lands staged on a
`kit-adopt-<timestamp>` branch for review. `cat .claude/VERSION` tells you which version you are on.

## Rule → gate

| Rule | Enforcing mechanism |
|---|---|
| Commit/push only with approval — in every permission mode | `guard-bash.sh` (PreToolUse) raises an approval prompt only you can answer; approve once and Claude runs the commit. Fails closed under `bypassPermissions`; `CLAUDE_GIT_OK=1` pre-authorises headless runs |
| Destructive operation (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (block at the tool level) |
| No AI trace and no external template/vendor name in a commit | `pre-commit` + `commit-msg` git hook (project files; `.claude/` exempt from the trace scan, never from the secret scan) |
| Session threshold (75% · 90%) | `context-usage.sh` (measurement) + `session-guard.sh` (Stop hook, warns once per threshold) |
| Always-on context stays lean | `smoke-test.sh` byte budgets: discipline · agent descriptions · skill descriptions |
| A running session never follows stale rules | `context-usage.sh` compares `.claude/VERSION` with the session's starting version |
| Quality gate (projects using SonarQube — language-agnostic) | `sonarqube-check` + `/ship` |

## Verification

```bash
bash .claude/eval/smoke-test.sh      # structure, frontmatter, gate integrity
bash .claude/eval/routing-eval.sh    # does a sample prompt reach the right agent/skill
```

`smoke-test` checks the structure, that the hooks are +x and armed, and the context measurement thresholds;
`routing-eval` verifies that the golden prompt set routes to the right target and that there is no trigger collision.
Neither one runs Claude Code.

## Extending

When adding a new agent or skill, follow the `AGENT_TEMPLATE.md` contract: frontmatter (name ·
description + Trigger phrases · least-privilege tools · model tier) and body (When → Expertise
stance → How/skill → Coordination → DoD → Output & context → Errors/escalation → Example → Constraints).

## Note

Everything is project-local (`./.claude`); there is no dependency on the home directory (`~/.claude`). Whether `.claude/` and
`CLAUDE.md` are kept local or shared with the team depends on the decision given at install time.
