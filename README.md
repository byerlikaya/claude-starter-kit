# Agentic Working Kit — Claude Code

🇬🇧 English · [🇹🇷 Türkçe](README.tr.md)

A reusable Claude Code scaffold that drives any project — at any stage — with the same engineering discipline. It **installs** into a fresh project, and it **hands over** into a project already in motion without breaking it. Either way the flow is the same: **plan → build → review → commit** — and at every step, quality and safety rest on gates at the tool level, not on the model remembering.

**Version 1.0.0** · **MIT License** · [Changelog](CHANGELOG.md)

## Why this kit?

Most "agent setups" are a pile of suggestions: the rules live in a file, and whether they are followed is left to the model. This kit makes a different promise — **a critical rule is a gate, not a reminder.**

- An AI-authorship trace **cannot** slip into a commit message, because a git hook rejects it.
- An unapproved `commit`/`push` **cannot** run, because a PreToolUse hook stops it — even in auto/bypass mode.
- Session fill is **not guessed**, because the real token count is measured from the transcript.
- An install **does not overwrite** an existing project, because the handover happens on a separate git branch; if you don't like it, one command removes it.

## Three principles

1. **Agent = thin trigger.** An agent only says "who, when"; it stays short and leaves the "how" to a skill.
2. **Skill = single source of truth.** The actual method and rule live in the skill; they are not copied into the agent.
3. **Rule → gate.** The rule that matters is enforced at the tool level (hook · permission · eval). The model is not expected to remember it.

## Two ways to adopt

### Fresh project — `start.sh`

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic]
```

`start.sh` is an install wizard. With no flags it walks each step (profile → backend stack → summary and approval); the flags are for silent/CI use. Every choice shows what it will install **before** installing it: how many agents, how many skills, which safety gates.

| Profile | Expert agents | Highlighted skills |
|---|---|---|
| `--backend` | backend · database | db-migration · api-design · observability |
| `--frontend` | frontend | frontend · a11y · i18n-integrity |
| `--mobile` | frontend (+ React Native/Expo layer) | frontend-rn-expo · a11y |
| `--fullstack` | all of them | all skills |

The backend stack is asked only for `--backend`/`--fullstack`:

- **`--dotnet`** — .NET / DevArchitecture pattern (MediatR CQRS · IResult · AOP). Brings the `devarch-module` and `sonarqube-check` skills; the DevArchitecture base is added through an explicit **approval gate**.
- **`--generic`** — a stack-agnostic backend expert that adapts to the existing repo pattern; no .NET-specific skills are installed. Suitable for Node, Go, Python, and the like.

When the install finishes you have `./.claude/` (agents · skills · commands · hooks · eval · settings.json) and a root `./CLAUDE.md`, the git hooks are armed, and the install leftovers are cleaned up.

### Existing project — `update.sh`

```bash
bash update.sh          # at the root of the target project
```

Applies the kit to a project already in motion, like **one team handing a project over to another**. It sets out to preserve three things at once: the project is not broken, decisions already made are not lost, and the kit does not stay passive. In order, it:

1. **Detects** — reads existing agents, rules, the husky/lefthook chain, and tracked files; it changes nothing.
2. **Proposes** — a project-specific smart proposal for seven handover decisions; in interactive mode you review and can override every one.
3. **Opens a handover branch** — all changes happen on a separate git branch. `main` is untouched; you review the result as a diff and accept or discard it with `git`.
4. **Coexists** — kit agents install with a `-cck` suffix and never collide with the project's own agents. The project's agents are left untouched.
5. **Binds the discipline** — the kit's rules are written to `DISCIPLINE.md` and added to the project's `CLAUDE.md` with a single `@import`; the project's content is unchanged.
6. **Merges settings** — `settings.json` is merged schema-aware; the project's own hooks and permissions are preserved and the kit's are added.
7. **Proves the gates** — after install it tests that the gates actually work (proof, not a claim). If a husky chain exists, the kit's hooks run alongside it via a shim.
8. **Documents the handover** — it leaves a durable `docs/HANDOVER.md` and a decision record under `docs/adr/`, so decisions live in version control, not in a chat.

## What's inside

- **11 agents** — planner · backend · database · security · privacy · test · frontend · devops · review · commit · session-manager. Agent names carry a `-cck` suffix (Claude Code Kit) so they never collide with the host project's own agents.
- **27 skills** — code review, security scan, migration, deployment, observability, performance, accessibility, translation integrity, versioning, incident response, and more.
- **5 slash commands** — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hooks** — `guard-bash.sh` (tool-level gate), `pre-commit` + `commit-msg` (trace scan), `context-usage.sh` and `session-guard.sh` (session measurement), `trace-blocklist.txt`.
- **CLAUDE.md** — behavior, the three principles, workflow, Definition of Done, token discipline, and prohibitions.

## Session and token management

An assistant cannot run `/context` itself, so most setups **guess** the session fill. This kit measures it. `context-usage.sh` reads the real token count from the last turn's API usage in the transcript — the same figure `/context` shows. The `UserPromptSubmit` hook injects it into context every turn; the `Stop` hook (`session-guard.sh`) forces the handover recommendation to the surface once fill exceeds **75%**. So the session-health line rests on a measurement, not a guess.

## Rule → gate

| Rule | Enforcing mechanism |
|---|---|
| Commit/push only with approval — even in auto/bypass mode | `guard-bash.sh` (PreToolUse); opened with `CLAUDE_GIT_OK` |
| Destructive operation (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (blocked at the tool level) |
| No AI-authorship trace or external template/vendor name in a commit | `pre-commit` + `commit-msg` git hook (trace scan) |
| Session threshold | `context-usage.sh` (measurement) + `session-guard.sh` (Stop hook) |
| Quality gate (SonarQube projects — language-agnostic: JS/TS · Python · Go · Java · C# …) | `sonarqube-check` + `/ship` |

The gates are armed via `settings.json` and git `core.hooksPath`; `smoke-test.sh` verifies they are ready after every change.

## Verification

```bash
bash .claude/eval/smoke-test.sh      # structure, frontmatter, gate integrity
bash .claude/eval/routing-eval.sh    # does an example prompt route to the right agent/skill
```

`smoke-test` checks agent/skill frontmatter, orphan skill references, that hooks are +x and armed, and the context-measurement thresholds. `routing-eval` verifies that a golden set of prompts routes to the expected target and that no two agents share a trigger; it normalizes Turkish diacritics and does not run Claude Code.

## Workflow

`/plan` (ambiguous scope) → expert agents build → `/review` (security · quality · test) → `/ship` (DoD gate; proposes the commit, waits for approval) → when context fills up, `/handoff` → `/clear`.

## Extending

When you add an agent or skill, follow the `AGENT_TEMPLATE.md` contract: frontmatter (name · description + Trigger phrases · least-privilege tools · model tier) and body (When → Expertise stance → How/skill → Coordination → DoD → Output & context → Errors/escalation → Example → Constraints).

## License and attribution

MIT — see [LICENSE](LICENSE). Part of the discipline layer is adapted from upstream sources: the `code-review` skill from `google/eng-practices` (CC-BY 3.0), and the `devarch-module` skill from the DevArchitecture pattern (with the author's explicit permission). Details in [ATTRIBUTION.md](ATTRIBUTION.md).
