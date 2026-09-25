# Agents and skills

**12 specialist agents** across five stages, so quality escalates before anything is committed.

<div align="center">
  <img src="../../../assets/orchestration-en.svg" alt="The five stages: Understand, Produce, Audit, Close, Hand off" width="820">
</div>

| Agent | Stage | Fires when |
|:--|:--|:--|
| `crew-planner` | Understand | scope is ambiguous |
| `crew-backend-expert` | Produce | server / API / business logic |
| `crew-database-expert` | Produce | schema, migration, index, cache |
| `crew-frontend-expert` | Produce | UI, component, client work |
| `crew-devops-expert` | Produce | deployment, CI pipeline, incident |
| `crew-security-expert` | Audit | auth / IDOR / injection / secret · **mandatory if security-critical** |
| `crew-privacy-agent` | Audit | personal data — KVKK/GDPR, plus any regime the project declares |
| `crew-test-expert` | Audit | tests, coverage, regression |
| `crew-performance-expert` | Audit | hot path, query/loop, render, payload |
| `crew-review-agent` | Close | pre-commit code-health review |
| `crew-commit-agent` | Close | proposes the commit, waits for approval |
| `crew-session-manager` | Hand off | context fills / phase boundary |

**Models are not pinned.** Every agent runs on the model you chose for the session, so a review that clears a change is never weaker than whatever wrote it. Two exceptions earn their keep: `crew-security-expert` buys extra rigour with `effort: high`, and `crew-commit-agent` runs on `haiku` because turning a staged diff into a Conventional Commit is mechanical. Change any of it in the agent's frontmatter if your project wants something else.

## All 40 skills

<div align="center">
  <img src="../../../assets/network-en.svg" alt="12 agents and 40 skills, connected by their real applies relationships" width="820">
  <br><sub>Every agent, every skill, and the real <code>applies</code> relationships — grouped by stage, each agent its own hue; the centre is the main thread that orchestrates them.</sub>
</div>

The catalogue below is generated from each skill by `packaging/build-readme-catalog.sh`; do not edit it by hand.

<!-- SKILLS:START -->

| Skill | What it does |
|:--|:--|
| `a11y` | Frontend accessibility audit (WCAG): semantic HTML, keyboard access, focus management, contrast, ARIA, screen readers. |
| `adr` | Architecture Decision Record: context-decision-consequences, for decisions that are expensive to reverse. |
| `api-design` | API contract design: resource naming, error model, versioning, pagination, backward compatibility, OpenAPI. |
| `automode-policy` | Auto-mode classifier config: inspect what the classifier that answers permission prompts is configured with, and catch the silent case… |
| `backend-architecture` | Decide, record and apply the backend stack and architecture pattern. |
| `brainstorm` | Divergent discovery BEFORE planning: turn a fuzzy ask into 2–4 scoped options + named unknowns, pick a direction, hand to spec-planning. |
| `ci-pipeline` | CI pipeline discipline: lint→build→test→quality→security, fail-fast, deterministic build, secret handling, PR gates. |
| `commit-message` | Conventional Commits: reads the staged diff and proposes `type(scope): summary`, with body/footer when needed. |
| `confidence-check` | Readiness gate BEFORE writing implementation code: does this already exist, does it fit the project's architecture, is the API claim… |
| `crew-code-review` | Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall code health. |
| `db-migration` | Apply schema migrations safely: detect the tool, classify the change by risk, gate destructive ones behind approval, back up in prod,… |
| `dependency-audit` | Dependency risk assessment, read-only: known CVEs, deprecated packages, licence compliance, maintenance status, lockfile integrity, and a… |
| `dependency-upgrade` | Bring dependencies current without breaking the build: find what is vulnerable, deprecated or behind, classify each target version by… |
| `deploy` | Ship a build reversibly — to a host you manage or a platform that manages it. |
| `docs-writer` | Keeps documentation in sync with the code: README, usage and related docs when a public API or behavior changes. |
| `eval-grader` | Measure output quality, don't vibe it: score a generative task with a two-layer grader — deterministic code metrics + per-dimension… |
| `frontend-design` | Visual and UX design quality for interfaces: hierarchy, spacing rhythm, typographic scale, a restrained color system, layout composition,… |
| `frontend-rn-expo` | OPTIONAL, stack-specific: React Native + Expo (prebuild). |
| `frontend` | Stack-agnostic frontend discipline (web · mobile · desktop): component structure, state, data fetching, loading/empty/error states,… |
| `handoff` | Session handover: when context fills, a phase closes, or the topic changes, write an action-oriented handover to docs/SESSION_STATE.md,… |
| `i18n-integrity` | Translation integrity: every key present in every language, no hardcoded strings, consistent placeholders and plurals. |
| `incident-runbook` | Production incident response: diagnose → mitigate → resolve, then a blameless postmortem and a repeatable runbook. |
| `iterate` | Refine-to-Done loop: repeat until tests green + review clean + nothing deferred; bounded. |
| `mcp-builder` | Build a Model Context Protocol (MCP) server so an AI client can call your tools/resources: design tool schemas, pick a transport, handle… |
| `observability` | Stack-agnostic observability: structured logs, correlation ids, metrics and traces; no PII or secrets in logs. |
| `performance` | Stack-agnostic performance: measure first, find the bottleneck, then optimise. |
| `privacy-compliance` | KVKK/GDPR audit method: data inventory, purpose/basis/retention, minimisation, consent, transparency, data-subject rights, cross-border… |
| `red-team` | Attacker's-eye test of LLM/agent defenses: instruction hijacking, data exfiltration and tool abuse through untrusted content; verifies… |
| `reflect` | Retrospective self-audit after nontrivial work: unverified assumptions, skipped items, is-this-the-right- approach — findings, not code. |
| `release` | Versioning and CHANGELOG: SemVer mapped from Conventional Commits, Keep a Changelog format, tagging, pre-release gates. |
| `security-scan` | Stack-agnostic security audit: map the attack surface, trace untrusted input to dangerous calls, surface dependency and configuration flaws. |
| `sonarqube-check` | SonarQube quality gate, any language, no company server needed: run SonarQube Community Build locally (Docker), read the real gate +… |
| `spec-planning` | Spec-first planning: task breakdown, measurable acceptance criteria, dependency order, risk priority. |
| `systematic-debugging` | Root-cause a bug before touching a fix: reproduce, isolate, form and test a hypothesis, confirm the cause, then fix and verify. |
| `teamboard` | Shared team board: claim a work item before starting, hand it over, finish it. |
| `testing` | The how of testing: pyramid, AAA, isolation, risk coverage, determinism. |
| `threat-model` | Scope a security audit BEFORE scanning, to cut false positives: map assets, entry points, trust boundaries and 5-8 domain-specific attack… |
| `token-budget` | Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills. |
| `trace-scan` | Trace scan (§4.1/§4.2): before a commit, scans the staged changes and the message for AI traces (co-author trailers, footers, robot… |
| `worktree` | Isolate risky or parallel file-mutating work in a git worktree so the main tree's uncommitted changes are never clobbered. |

<!-- SKILLS:END -->
