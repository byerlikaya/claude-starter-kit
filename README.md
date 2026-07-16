<div align="center">

<img src="assets/logo.svg" alt="Claude Starter Kit" width="460">

**An agentic working kit for Claude Code** — a reusable scaffold that drives any project, at any stage, with the same engineering discipline.

*plan → build → review → commit, where every critical rule is a **gate**, not a reminder.*

![Version](https://img.shields.io/badge/version-1.6.2-2563eb?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)
![Agents](https://img.shields.io/badge/agents-11-f59e0b?style=flat-square)
![Skills](https://img.shields.io/badge/skills-34-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

🇬🇧 English · [🇹🇷 Türkçe](README.tr.md)

</div>

---

## Why this kit?

Most "agent setups" are a pile of suggestions — the rules sit in a file, and whether they're honored is left to the model. This kit is different: it drops a **disciplined engineering team** into Claude Code, where **the rules that matter are gates, not reminders** — it doesn't just tell the agent the rules, it makes breaking the critical ones impossible, and it installs safely onto the repo you already have.

| | |
|---|---|
| 👥 | **A team, not a prompt** — 11 specialist agents auto-chain across plan → build → audit → ship; you don't wire them, the main thread does. |
| 🛡️ | **Security & privacy are gates, not options** — risk-critical changes must clear the security/privacy audit before they can close. |
| 🚦 | **Every commit is yours to approve** — no `commit`/`push` runs without your explicit OK, enforced at the tool level even in auto/bypass mode. |
| 🌿 | **Safe on an existing repo** — `adopt` hands the kit over on a branch; `main` is never touched, and you review before you keep it. |

---

## 🚀 Quick start

```bash
npx @byerlikaya/claude-starter-kit          # fresh project — setup wizard
npx @byerlikaya/claude-starter-kit adopt    # existing project — safe handover on a branch
```

Then paste **`.claude/FIRST_PROMPT.md`** as your first Claude Code message. Homebrew, a release tarball, and the plugin edition are covered in **Install & run** below.

---

## 🧠 The agents — the heart of the kit

**11 agents**, each a **thin trigger** — it says only *who* and *when*, and delegates the *how* to a skill. The main thread selects and chains them across **five stages**, escalating quality before anything is committed:

<div align="center">
  <img src="assets/orchestration-en.svg" alt="Agent orchestration across five stages" width="740">

  🧭 **Understand** &nbsp;→&nbsp; 🔨 **Produce** &nbsp;→&nbsp; 🔍 **Audit** &nbsp;→&nbsp; ✅ **Close** &nbsp;→&nbsp; 🤝 **Hand off**

</div>

<details>
<summary><b>The 11 agents & when each fires</b></summary>

| Agent | Stage | Fires when | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Understand | scope is ambiguous | `inherit` |
| **backend-expert-csk** | 🔨 Produce | server / API / business logic | `inherit` |
| **database-expert-csk** | 🔨 Produce | schema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Produce | UI, component, client work | `inherit` |
| **devops-expert-csk** | 🔨 Produce | deployment, CI pipeline, incident | `inherit` |
| **security-expert-csk** | 🔍 Audit | auth / IDOR / injection / secret · **mandatory if security-critical** | `sonnet` |
| **privacy-agent-csk** | 🔍 Audit | personal data (KVKK / GDPR) | `sonnet` |
| **test-expert-csk** | 🔍 Audit | tests, coverage, regression | `inherit` |
| **review-agent-csk** | ✅ Close | pre-commit code-health review | `inherit` |
| **commit-agent-csk** | ✅ Close | proposes the commit, waits for approval | `haiku` |
| **session-manager-csk** | 🤝 Hand off | context fills / phase boundary | `haiku` |

</details>

> Agent names carry a `-csk` suffix (Claude Starter Kit) so they never collide with the host project's own agents. Each agent is thin; the real method lives in a **skill** — the single source of truth.

---

## Three principles

1. **Agent = thin trigger.** An agent only says "who, when"; it stays short and leaves the "how" to a skill.
2. **Skill = single source of truth.** The actual method and rule live in the skill; they are not copied into the agent.
3. **Rule → gate.** The rule that matters is enforced at the tool level (hook · permission · eval). The model is not expected to remember it.

---

## How this kit is different

Most "agent setups" for Claude Code fall into two buckets: a **big prompt file** with rules, or a **collection of agents/skills** you wire together yourself. Both leave the hard part — *actually enforcing discipline* — to the model's goodwill. This kit doesn't.

| What matters | Typical agent kit / prompt collection | Claude Starter Kit |
|---|---|---|
| **Critical rules** | Live in a `.md` file; honored only if the model remembers | **Enforced as gates** at the tool level — git hook (`trace-scan`), `settings.json` permissions, `guard-bash.sh` PreToolUse. Breaking them is *impossible*, not *discouraged* |
| **Structure** | A single dev prompt, or a loose list of agents you orchestrate | **A team of 11 specialist agents** that auto-chain across 5 stages (Understand → Produce → Audit → Close → Hand off) — the main thread wires them, not you |
| **Security & privacy** | Optional advice, easy to skip | **Mandatory audit gate** — risk-critical changes can't close before the security/privacy review clears |
| **Commits** | Model may commit on its own | **Every commit is yours to approve** — enforced at the tool level even in auto/bypass mode |
| **Adopting an existing repo** | "Start fresh" assumption; manual porting | **`adopt` hands the kit over on a branch** — `main` is never touched; you review before you keep it |
| **Where the "how" lives** | Rules + method copied into each agent prompt → drift & duplication | **Agent = thin trigger** (who/when); the method lives once in a **skill** (single source of truth), reused across 34 skills |

**In one line:** similar projects hand you *a pile of suggestions*; this kit drops a *disciplined engineering team* into Claude Code — where the rules that matter are **gates, not reminders**.

---

## Install & run

**Two entry points:** `start.sh` sets up a **fresh** project; **`adopt`** (`adopt.sh`) hands the kit over to an **existing** one. Pick any channel — each runs the same two commands.

**npx** — nothing to install:
```bash
npx @byerlikaya/claude-starter-kit          # fresh project
npx @byerlikaya/claude-starter-kit adopt    # existing project
npx @byerlikaya/claude-starter-kit@latest update   # refresh a project that already has the kit
```

**Homebrew:**
```bash
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit          # fresh project
claude-starter-kit adopt    # existing project
brew upgrade byerlikaya/tap/claude-starter-kit && claude-starter-kit update   # refresh a project that already has the kit
```

**Release tarball** — no package manager:
```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # fresh project
bash adopt.sh               # existing project — re-run it to refresh a project that already has the kit (update)
```

> Just want the agents & skills inside your existing Claude Code (no scaffolding)? `/plugin marketplace add byerlikaya/claude-starter-kit` then `/plugin install claude-starter-kit@byerlikaya`.

> **Windows:** the kit is bash-based — run it inside **Git Bash** (from [git-scm.com](https://git-scm.com)) for the smoothest experience; WSL works as a fallback.

### 🌱 Fresh project — `start.sh`

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic] [-h]
```

An install wizard. With no flags it walks each step (profile → backend stack → summary and approval); the flags are for silent/CI use, and `-h` / `--help` prints usage. Every choice shows what it will install **before** installing it.

> After install, paste **`.claude/FIRST_PROMPT.md`** as your first Claude Code message — an optional kickoff that verifies the agents/skills and plans the first sprint. (`CLAUDE.md` loads the discipline every session regardless, so this is a one-time convenience, not a requirement.)

| Profile | Expert agents | Highlighted skills |
|---|---|---|
| `--backend` | backend · database | db-migration · api-design · observability |
| `--frontend` | frontend | frontend · a11y · i18n-integrity |
| `--mobile` | frontend (+ React Native/Expo layer) | frontend-rn-expo · a11y |
| `--fullstack` | all of them | all skills — backend **and** web **and** mobile (RN/Expo) |

There is no separate mobile agent: `frontend-expert-csk` covers web, mobile and desktop, and the mobile *how* lives in the `frontend-rn-expo` skill. `--fullstack` installs it too, so a fullstack project is ready for mobile without picking `--mobile`.

The backend stack is asked only for `--backend`/`--fullstack`: **`--dotnet`** brings the .NET / DevArchitecture pattern (MediatR CQRS · IResult · AOP) behind an approval gate; **`--generic`** installs the same expert without it — for Node, Go, Python, or a .NET project on a different pattern.

> **.NET — start proven, not from scratch.** `--dotnet` clones the production-ready **[DevArchitecture](https://github.com/DevArchitecture/DevArchitecture)** foundation (CQRS · IResult · AOP · auth) *and* installs agents that already know it — so you **skip the tokens an agent would burn regenerating a standard architecture**; they go to your business logic, not boilerplate. Opinionated by *default*, not by force: the backend expert applies your project's **pattern skill** — DevArchitecture out of the box, or your own (Clean Architecture, Vertical Slice, Minimal API, plain layered) dropped into `.claude/skills/`. `--generic` stays stack-agnostic.

> On **`--fullstack` + `--dotnet`** the DevArchitecture backend is placed in `./backend`, `./frontend` is reserved for your frontend, and the solution file is renamed to your project's name — so the project root stays clean instead of looking like a bare backend.

### 🔄 Existing project — `adopt.sh`

```bash
bash adopt.sh          # at the root of the target project
```

Applies the kit to a project already in motion, like **one team handing a project over to another** — the project is not broken, decisions already made are not lost, and the kit does not stay passive.

<div align="center">
  <img src="assets/handover-en.svg" alt="adopt.sh handover flow" width="900">
</div>

All changes land on a separate git branch **staged, not committed** — so every added and changed file shows up in your editor's Source Control / Changes panel; you review it there, then `git commit` to accept (or reset to discard). `main` stays untouched. Kit agents install side-by-side (never colliding), the discipline is bound via a single `@import`, `settings.json` is merged schema-aware, and existing husky/lefthook chains run alongside the kit via a shim. It closes with a durable `docs/HANDOVER.md` and an ADR, so decisions live in version control, not in a chat.

### 🔁 Update an installed project

Run it at the project root — same command on every channel; `update` is an alias of `adopt`.

```bash
npx @byerlikaya/claude-starter-kit@latest update                              # npx
brew upgrade byerlikaya/tap/claude-starter-kit && claude-starter-kit update   # Homebrew
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz && bash adopt.sh   # tarball
```

At install time the kit stamps `.claude/kit.conf` with the profile, the backend stack and which installer ran, plus `.claude/VERSION`. The updater reads that stamp and refreshes the project **in the shape it was installed in**: a `--backend` project does not get frontend agents grafted back on, and a `--dotnet` project keeps its `devarch-module` pattern skill. Where the stamp is absent, the updater derives the shape from the installed files and writes it. Compare `cat .claude/VERSION` against `npm view @byerlikaya/claude-starter-kit version` to see whether an update is waiting.

Inside a running Claude Code session you can also run **`/update-csk`** — it does the version check, runs the updater if a newer version exists, verifies the result with `/doctor-csk`, and then prompts `/compact` to reload the refreshed discipline in the same session. To check a live install's health at any time, run **`/doctor-csk`** (hooks executable · `core.hooksPath` set · gates wired).

| | On update |
|---|---|
| `.claude/` agents · skills · commands · hooks · eval | refreshed from the new version |
| `.claude/DISCIPLINE.md` | **overwritten** — it is kit-owned, so keep nothing of your own in it |
| `./CLAUDE.md` | never touched — your project rules stay exactly as you wrote them |
| `.claude/settings.json` | merged schema-aware; your own hooks and permissions survive |
| your own agents and skills (no `-csk` suffix) | untouched |

Like `adopt`, an update needs a git repo. Where the change lands is now a choice: a first adopt opens a `kit-adopt-<timestamp>` review branch (keeps your main line clean); a routine update whose `.claude/` is gitignored applies on your **current** branch (a separate branch would just be empty); an update with a **tracked** `.claude/` asks. Force where it lands with `--here` or `--new-branch`, and run it without prompts — as the in-session `/update-csk` and CI do — with `--yes`. Either way the change is staged and uncommitted — review the diff, then commit to accept or reset to discard.

> If a project's `CLAUDE.md` carries the discipline **inline** instead of importing it, discipline updates cannot reach that project. The updater detects this, shows which lines hold the inline block, and offers to replace them with the single `@.claude/DISCIPLINE.md` import — writing a backup first, on a branch you review. Decline and nothing is touched; your project section and your own rules survive either way.

---

## What's inside

- **11 agents** — see the table above.
- **34 skills** — the single source of "how", one per area (full catalogue below).
- **8 slash commands** — `/brainstorm` · `/plan` · `/review` · `/ship` · `/handoff` · `/simplify` · `/update-csk` (update the installed kit) · `/doctor-csk` (health-check the install).
- **Hooks** — `guard-bash.sh` + `guard-write.sh` (tool-level command/write gates), `pre-commit` + `commit-msg` (trace + secret + bloat scan), `context-usage.sh` and `session-guard.sh` (session measurement), `session-rehydrate.sh` (re-surface the handover after /compact or /clear). The plugin edition ships these gate hooks too.
- **CLAUDE.md** — behavior, the three principles, workflow, Definition of Done, token discipline, and prohibitions.

<details>
<summary><b>Full skill catalogue</b> — all 34, generated from each skill</summary>

<!-- SKILLS:START -->

| Skill | What it does |
|:--|:--|
| `a11y` | Frontend accessibility audit (WCAG): semantic HTML, keyboard access, focus management, contrast, ARIA, screen readers. |
| `adr` | Architecture Decision Record: context-decision-consequences, for decisions that are expensive to reverse. |
| `api-design` | API contract design: resource naming, error model, versioning, pagination, backward compatibility, OpenAPI. |
| `brainstorm` | Divergent discovery BEFORE planning: turn a fuzzy ask into 2–4 scoped options + named unknowns, pick a direction, hand to spec-planning. |
| `ci-pipeline` | CI pipeline discipline: lint→build→test→quality→security, fail-fast, deterministic build, secret handling, PR gates. |
| `code-review` | Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall code health. |
| `commit-message` | Conventional Commits: reads the staged diff and proposes `type(scope): summary`, with body/footer when needed. |
| `db-migration` | Apply schema migrations safely: detect the tool, classify the change by risk, gate destructive ones behind approval, back up in prod,… |
| `dependency-audit` | Dependency audit: known CVEs, licence compliance, abandoned/outdated packages, lockfile integrity, and a justification for every new… |
| `devarch-module` | DevArchitecture backend pattern: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP chain, FluentValidation, i18n. |
| `docs-writer` | Keeps documentation in sync with the code: README, usage and related docs when a public API or behavior changes. |
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
| `sonarqube-check` | SonarQube quality gate (language-agnostic, local-first): 0 Bugs/Vulns/Hotspots/Code Smells, 0 build warnings. |
| `spec-planning` | Spec-first planning: task breakdown, measurable acceptance criteria, dependency order, risk priority. |
| `systematic-debugging` | Root-cause a bug before touching a fix: reproduce, isolate, form and test a hypothesis, confirm the cause, then fix and verify. |
| `testing` | The how of testing: pyramid, AAA, isolation, risk coverage, determinism. |
| `token-budget` | Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills. |
| `trace-scan` | Trace scan (§4.1/§4.2): before a commit, scans the staged changes and the message for AI traces (co-author trailers, footers, robot… |
| `vps-deploy` | Deploy to a VPS safely: runtime detection, reverse proxy + SSL, atomic swap, keep the previous version, post-deploy health gate,… |
| `worktree` | Isolate risky or parallel file-mutating work in a git worktree so the main tree's uncommitted changes are never clobbered. |

<!-- SKILLS:END -->

</details>

---

## Session & token management

An assistant cannot run `/context` itself, so most setups **guess** the session fill. This kit measures it. `context-usage.sh` reads the real token count from the last turn's API usage in the transcript — the same figure `/context` shows. The `UserPromptSubmit` hook injects it every turn; the `Stop` hook (`session-guard.sh`) warns you the first time fill crosses **75%**, and once more at **90%** — one warning per threshold, and it never blocks your turn. The session-health line rests on a measurement, not a guess.

### Token cost

`DISCIPLINE.md` and the agent/skill descriptions load into every session's context. That always-on material is **~26 KB** today (`DISCIPLINE.md` + 11 agent + 34 skill descriptions) — on the order of **10k tokens** on a real turn. Every skill added is a permanent ~100-token tax on all sessions, which is why the byte budget below is a gate, not a guideline.

`smoke-test.sh` enforces a byte budget per component (discipline · agent descriptions · skill descriptions), so the cost cannot drift upward unnoticed. A budget can be raised, but only by editing `smoke-test.sh` explicitly.

> **Profile pruning does not save tokens.** A `--backend` install (10 agents, 30 skills) costs only a few hundred tokens less than `--fullstack` (11 agents, 34 skills). Pick a profile to narrow the scope of the work.

---

## Rule → gate

| Rule | Enforcing mechanism |
|---|---|
| Commit/push only with approval — in every permission mode | `guard-bash.sh` (PreToolUse) raises an approval prompt only you can answer; approve once and Claude runs the commit. Fails closed under `bypassPermissions`; `CLAUDE_GIT_OK=1` pre-authorises headless runs |
| Destructive op (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (blocked at the tool level) |
| Remote-code-exec / permission-nuke (`curl…\|bash` · `chmod 777` · `dd of=`) | `guard-bash.sh` (hard-blocked in every mode) |
| Disarming the gates (redirect `core.hooksPath`, or edit/delete a hook script) | `guard-bash.sh` (shell side) + `guard-write.sh` (Write/Edit side) — a gate you can silently remove is not a gate |
| Committing straight onto the default branch | `guard-bash.sh` surfaces it in the approval prompt (a warning, not a block — a fresh project legitimately lives on `main`) |
| Build/vendored artifact or oversized blob staged | `pre-commit` repo-bloat scan (`node_modules/`, `dist/`, `>5 MiB`, …; override via `CSK_MAX_FILE_BYTES`) |
| Secret **file** staged (whole-file secret the content scan can miss) | `pre-commit` secret-file gate (`.env`, `id_rsa`, `*.pem/.key/.p12`, `.npmrc`, …; `.env.example`/`.sample`/`.template` stay committable) |
| Force-add past `.gitignore` (`git add -f`) · deleting a lockfile | `guard-bash.sh` (blocked at the tool level) |
| No AI-authorship trace or external vendor name in a commit | `pre-commit` + `commit-msg` git hook — scans your project's files; the kit's own `.claude/` tree is exempt (it names the tool it configures), secrets never are |
| No API key / token / private key committed | `pre-commit` secret scan (`secret-blocklist.txt` + `.secret-allowlist.txt`) |
| Session threshold | `context-usage.sh` + `session-guard.sh` (Stop hook) |
| Always-on context stays lean | `smoke-test.sh` byte budgets per component (discipline · agent descriptions · skill descriptions) |
| A running session never follows stale rules | `context-usage.sh` compares `.claude/VERSION` against the version the session started with, and says so |
| Quality gate (SonarQube projects — language-agnostic) | `sonarqube-check` + `/ship` |

The gates are armed via `settings.json` and git `core.hooksPath`; `smoke-test.sh` verifies they are ready after every change.

---

## Verification

```bash
bash .claude/eval/smoke-test.sh      # structure, frontmatter, gate integrity
bash .claude/eval/routing-eval.sh    # does an example prompt route to the right agent/skill
```

## Workflow

`/plan` (ambiguous scope) → expert agents build → `/review` (security · quality · test) → `/ship` (DoD gate; proposes the commit, waits for approval) → when context fills up, `/handoff` → `/clear`.

## Extending

When you add an agent or skill, follow the `AGENT_TEMPLATE.md` contract: frontmatter (name · description + Trigger phrases · least-privilege tools · model tier) and body (When → Expertise stance → How/skill → Coordination → DoD → Output & context → Errors/escalation → Example → Constraints).

## License & attribution

MIT — see [LICENSE](LICENSE). The discipline layer builds on these upstream sources:

- **[DevArchitecture](https://github.com/DevArchitecture/DevArchitecture)** — the backend pattern (MediatR CQRS / IResult / AOP), referenced as a pattern only.
- **[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)** — the four working principles at the core of the discipline.
- **[google/eng-practices](https://github.com/google/eng-practices)** — the `code-review` skill, distilled and restated (CC-BY 3.0).
