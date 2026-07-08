# Agent Template Contract (Claude Code)

All expert agents conform to this skeleton. Canonical reference: **`backend-expert-csk`**.
Principle: **agent = thin trigger** ("who / when"), **skill = "how"**. Knowledge lives in the skill, the trigger in the agent.

## Frontmatter (required fields)
- `name`: kebab-case, exactly matching the file name.
- `description`: Claude Code makes its delegation decision **by looking at this**. It must contain three things:
  (1) what it does, (2) **WHEN** it kicks in, (3) a `Trigger phrases:` line (English key phrases).
- `tools`: least-privilege principle. Read-only auditor → `Read, Grep, Glob (+Bash)`; writing expert → `+ Edit, Write`.
- `model`: cost routing (table below). If the field is absent, the main session model is inherited (inherit).

## Body sections (fixed order)
1. **When** — triggering context.
2. **Expertise stance — recommended.** 3-5 **role-specific** concrete behaviors that the best in that role does differently (not a generic "be an expert"). It raises the decision/stance; the mechanical "how" stays in the skill.
3. **How (follow its skill)** — which skill + that skill's exit points specific to this agent. The skill is the **single source of truth**; do not copy the "how" into the agent — at most a quick reminder, and on conflict the skill wins (§2 "no repetition").
4. **Coordination (cross-agent) — recommended for writing experts.** Whom this work is delegated to: security→security-expert-csk, schema→database-expert-csk, tests→test-expert-csk, messages→i18n, personal data→privacy-agent-csk, findings at closure→review-agent-csk. It turns the agent into an orchestrator; usually unnecessary for read-only auditors.
5. **DoD** — closure responsibility: `/simplify` + tests green + `sonarqube-check` (0/0/0/0, build 0/0).
6. **Output & context (token)** — what returns to the main thread: a **short summary**, not raw logs/dumps; heavy output goes to `docs/*.md` (token-budget skill).
7. **Errors/escalation** — when stuck/unsure, **stop and report** or hand off to the relevant expert; do not proceed on a guess.
8. **Example delegation** — 1 ✅ triggers / 1 ❌ does-not-trigger line (delegation accuracy).
9. **Constraints** — read-only or not, what it does not do, platform/policy limits.

## Model routing (cost calibration)
**Use a tier ALIAS, not a dated model ID** (`haiku`/`sonnet`/`opus`/`inherit`). An alias resolves automatically to the current tier; when a model is renamed/deprecated, agents do not silently break. Use a full ID (`claude-sonnet-…`) only if pinning to a specific version is required.

| Agent | Role | model | Why |
|---|---|---|---|
| session-manager-csk | assessment | `haiku` | lightweight, writes no code |
| security-expert-csk | audit | `sonnet` | decision-heavy (auth/IDOR) |
| review-agent-csk | audit | `haiku` | read-only findings |
| commit-agent-csk | message generation | `haiku` | lightweight, writes no code |
| privacy-agent-csk | audit | `sonnet` | decision-heavy (KVKK/GDPR) |
| planner-csk | planning | `inherit` | wants stable reasoning |
| backend-expert-csk | writing | `inherit` | complex code, main model |
| database-expert-csk | writing | `inherit` | migration/schema risk |
| test-expert-csk | writing | `inherit` | behavioral correctness |
| frontend-expert-csk | writing | `inherit` | UI + native bridge |

Pulling the read-only trio down to Haiku lowers token/cost; the writing experts stay at full power.
(Aliases are valid in Claude Code frontmatter; if the field is empty, `inherit` is assumed.)

## Placement
- Project-local (10): `./.claude/agents/` — session-manager-csk, backend/database/security/test/frontend-expert-csk, review-agent-csk, commit-agent-csk, planner-csk, privacy-agent-csk. Everything stays inside the repo; no dependency on home (`~/.claude`) (handover §3).
- No extra agent is needed; stack-specific "hows" live under `./.claude/skills/` (the frontend's "how" is in the project's frontend skill / CLAUDE.md).

## Reference example
`backend-expert-csk.md` is this contract applied verbatim; when creating a new agent, copy it and fill it in.
