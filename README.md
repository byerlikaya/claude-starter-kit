<div align="center">

<img src="assets/logo.svg" alt="Claude Starter Kit" width="460">

**Not one assistant. An engineering team that actually runs.**

12 specialist agents plan the work, build it, put it through security and test review, then close it

![Version](https://img.shields.io/badge/version-1.10.1-2563eb?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)
![Agents](https://img.shields.io/badge/agents-12-f59e0b?style=flat-square)
![Skills](https://img.shields.io/badge/skills-38-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

🇬🇧 English · [🇹🇷 Türkçe](README.tr.md)

</div>

---

## What Claude Starter Kit does

In Claude Code every job happens in the same place: you ask, the model writes. Claude Starter Kit puts a team and an order in between.

**The work gets a process.** 12 agents own one domain each and run across five stages — plan, build, audit, close, hand off. An ambiguous request goes to planning before anything is written; server work goes to the backend owner, schema work to the database owner. A security review is **mandatory** before a risk-critical change can close, and a code-health review runs before anything is proposed for commit. A routing hook names the owning agent beside your request, which is what turns that from a diagram into what actually happens.

**The method is written once.** 38 skills hold the *how* — testing, migrations, API contracts, observability, accessibility, translation integrity, dependency upgrades, incident response, deployment. Agents stay thin: they say *who* and *when*, and apply the skill that holds the rest. You are not re-explaining your standards every session.

**Critical rules are enforced, not remembered.** A destructive command is refused before it runs, a commit waits for your approval, a leaked key or an AI-authorship trace never reaches history. These are guardrails around the work above — they are not the point of the kit, they are what lets you leave it running.

**It goes on the repo you already have.** `adopt` hands Claude Starter Kit over on a branch, staged and uncommitted, so the whole change sits in your editor's diff before any of it is yours to keep. Your `main` is never touched.

## Quick start

```bash
npx @byerlikaya/claude-starter-kit          # new project — setup wizard
npx @byerlikaya/claude-starter-kit adopt    # existing project — handover on a branch
```

Then paste `.claude/FIRST_PROMPT.md` as your first Claude Code message. Homebrew, a release tarball and a plugin edition are in [Install](#install).

## Contents

- [The agents](#the-agents)
- [What's inside](#whats-inside)
- [How it works](#how-it-works)
- [Rule → gate](#rule--gate)
- [Install](#install)
- [Session and token cost](#session-and-token-cost)
- [Verification](#verification)
- [Extending](#extending)
- [Licence and attribution](#licence-and-attribution)

---

---

## The agents

**12 specialist agents** across five stages, so quality escalates before anything is committed.

<div align="center">
  <img src="assets/orchestration-en.svg" alt="The five stages: Understand, Produce, Audit, Close, Hand off" width="820">
</div>

<details open>
<summary>🧭&nbsp; <b>All 12 agents — what each one owns, and when it fires</b></summary>

| Agent | Stage | Fires when | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Understand | scope is ambiguous | `inherit` |
| **backend-expert-csk** | 🔨 Produce | server / API / business logic | `inherit` |
| **database-expert-csk** | 🔨 Produce | schema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Produce | UI, component, client work | `inherit` |
| **devops-expert-csk** | 🔨 Produce | deployment, CI pipeline, incident | `inherit` |
| **security-expert-csk** | 🔍 Audit | auth / IDOR / injection / secret · **mandatory if security-critical** | `inherit` · `effort: high` |
| **privacy-agent-csk** | 🔍 Audit | personal data (KVKK / GDPR) | `inherit` |
| **test-expert-csk** | 🔍 Audit | tests, coverage, regression | `inherit` |
| **performance-expert-csk** | 🔍 Audit | hot path, query/loop, render, payload | `inherit` |
| **review-agent-csk** | ✅ Close | pre-commit code-health review | `inherit` |
| **commit-agent-csk** | ✅ Close | proposes the commit, waits for approval | `haiku` |
| **session-manager-csk** | 🤝 Hand off | context fills / phase boundary | `inherit` |

</details>

**Why almost every agent says `inherit`.** A subagent with no model pin runs on the model you chose for the session. That is deliberate: a pin can only make an agent run on a *different* tier from the work around it, and a review that clears a change must never be weaker than whatever wrote it. `security-expert-csk` buys extra rigour with `effort: high` — more thinking on *your* model, not a different one. `commit-agent-csk` keeps `haiku` because turning a staged diff into a Conventional Commit is mechanical, and the commit rules are gated anyway.

## What's inside

<div align="center">
  <img src="assets/network-en.svg" alt="12 agents and 38 skills, connected by their real applies relationships" width="820">
  <br><sub>Every agent, every skill, and the real <code>applies</code> relationships — grouped by stage, each agent its own hue; the centre is the main thread that orchestrates them.</sub>
</div>

| Component | Count | What it is |
|:--|:--:|:--|
| **Agents** | 12 | Thin triggers — *who* owns a domain and *when* they fire |
| **Skills** | 38 | The method, written once, applied by whoever needs it |
| **Slash commands** | 7 | `/brainstorm-csk` · `/plan-csk` · `/review-csk` · `/ship-csk` · `/handoff-csk` · `/update-csk` · `/doctor-csk` |
| **Hooks** | 8 | The gates, plus session measurement and routing |
| **Discipline** | 1 | Principles, workflow, Definition of Done, prohibitions — imported by your `CLAUDE.md` |

<details>
<summary>🪝&nbsp; <b>All 8 hooks — which gate holds what</b></summary>

| Hook | Role |
|:--|:--|
| `route-hint.sh` | Names the owning agent alongside every prompt, so specialists run without you asking |
| `guard-bash.sh` | Tool-level command gate: commit/push approval, destructive ops, remote-code-exec, hook tampering |
| `guard-write.sh` | The same protection on the Write/Edit side — a gate you can silently delete is not a gate |
| `guard-commit-scan.sh` | Runs the real trace and secret scanners from `PreToolUse`, so the commit gate works where `core.hooksPath` cannot be set |
| `context-usage.sh` | Reads the real token count from the transcript and injects it every turn |
| `session-guard.sh` | Warns once at 75% context fill and once at 90% — never blocks a turn |
| `session-rehydrate.sh` | Re-surfaces the handover after `/compact` or `/clear` |
| `skill-trust.sh` | Names any skill or agent Claude Starter Kit never shipped and you never accepted |

Two git hooks — `pre-commit` and `commit-msg` — run the trace, secret and repo-bloat scans. The plugin edition ships the gate hooks too.

</details>

<details>
<summary>📚&nbsp; <b>All 38 skills — the full catalogue, generated from each skill</b></summary>

<!-- SKILLS:START -->

| Skill | What it does |
|:--|:--|
| `a11y` | Frontend accessibility audit (WCAG): semantic HTML, keyboard access, focus management, contrast, ARIA, screen readers. |
| `adr` | Architecture Decision Record: context-decision-consequences, for decisions that are expensive to reverse. |
| `api-design` | API contract design: resource naming, error model, versioning, pagination, backward compatibility, OpenAPI. |
| `brainstorm` | Divergent discovery BEFORE planning: turn a fuzzy ask into 2–4 scoped options + named unknowns, pick a direction, hand to spec-planning. |
| `ci-pipeline` | CI pipeline discipline: lint→build→test→quality→security, fail-fast, deterministic build, secret handling, PR gates. |
| `code-review-csk` | Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall code health. |
| `commit-message` | Conventional Commits: reads the staged diff and proposes `type(scope): summary`, with body/footer when needed. |
| `confidence-check` | Readiness gate BEFORE writing implementation code: does this already exist, does it fit the project's architecture, is the API claim… |
| `db-migration` | Apply schema migrations safely: detect the tool, classify the change by risk, gate destructive ones behind approval, back up in prod,… |
| `dependency-audit` | Dependency risk assessment, read-only: known CVEs, deprecated packages, licence compliance, maintenance status, lockfile integrity, and a… |
| `dependency-upgrade` | Bring dependencies current without breaking the build: find what is vulnerable, deprecated or behind, classify each target version by… |
| `devarch-module` | DevArchitecture backend pattern: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP chain, FluentValidation, i18n. |
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
| `sonarqube-check` | SonarQube quality gate (language-agnostic, local-first): 0 Bugs/Vulns/Hotspots/Code Smells, 0 build warnings. |
| `spec-planning` | Spec-first planning: task breakdown, measurable acceptance criteria, dependency order, risk priority. |
| `systematic-debugging` | Root-cause a bug before touching a fix: reproduce, isolate, form and test a hypothesis, confirm the cause, then fix and verify. |
| `testing` | The how of testing: pyramid, AAA, isolation, risk coverage, determinism. |
| `threat-model` | Scope a security audit BEFORE scanning, to cut false positives: map assets, entry points, trust boundaries and 5-8 domain-specific attack… |
| `token-budget` | Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills. |
| `trace-scan` | Trace scan (§4.1/§4.2): before a commit, scans the staged changes and the message for AI traces (co-author trailers, footers, robot… |
| `vps-deploy` | Deploy to a VPS safely: runtime detection, reverse proxy + SSL, atomic swap, keep the previous version, post-deploy health gate,… |
| `worktree` | Isolate risky or parallel file-mutating work in a git worktree so the main tree's uncommitted changes are never clobbered. |

<!-- SKILLS:END -->

</details>

---

## How it works

Three rules hold the design together.

1. **An agent is a thin trigger.** It says *who* and *when*, nothing more. It stays short, because its description is loaded into every session.
2. **A skill is the single source of truth.** The actual method lives there once, and is never copied into an agent.
3. **A rule that matters becomes a gate.** Enforcement sits at the tool level — a hook, a permission, a test case. The model is not asked to remember it.

The everyday shape of it:

<div align="center">
  <img src="assets/workflow-en.svg" alt="Command flow: /plan-csk, expert agents, /review-csk, /ship-csk, /handoff-csk" width="820">
</div>

## Rule → gate

Left is the rule; right is the thing that refuses to let it slide.

| Rule | Enforced by |
|:--|:--|
| Commit and push need your approval, in every permission mode | `guard-bash.sh` raises a prompt only you can answer. Fails closed under `bypassPermissions` |
| Destructive ops: `reset --hard`, `checkout -- .`, force push, `rm -rf`, `clean -f`, `--no-verify`, amend | `guard-bash.sh`, blocked at the tool level |
| Remote code execution and permission nukes: `curl…\|bash`, world-writable `chmod`, `dd of=` | `guard-bash.sh`, hard-blocked in every mode |
| Disarming a gate — redirecting `core.hooksPath`, editing or deleting a hook | `guard-bash.sh` (shell) + `guard-write.sh` (file edits) |
| No API key, token or private key reaches a commit | `pre-commit` secret scan; every pattern carries its own test case |
| No credential is *read* into the context — `~/.ssh/id_rsa`, `~/.aws/credentials`, `*.pem`, kubeconfig | `settings.json` read-deny + `guard-bash.sh` |
| No AI-authorship trace or vendor template name in a commit | `pre-commit` + `commit-msg` git hooks |
| No build artifact, vendored tree or oversized blob gets staged | `pre-commit` repo-bloat scan |
| An unvetted skill or agent appearing in `.claude/` is named, with a scanner verdict | `skill-trust.sh` at session start |
| Always-on context stays lean | `smoke-test.sh` byte budget per component |
| A running session never follows stale rules after an update | `context-usage.sh` version comparison |

Every rule carries cases for **both** halves: that it blocks what it must, and that it does not block its neighbours — `chmod 755`, `rm -rf build`, `git checkout -- src/app.js`. A gate nobody proved is not a gate, and a gate that fires on routine work gets worked around.

Does it actually change anything? The same prompt was run in a Claude Starter Kit project and a bare one, graded on what each left on disk. Given a deadline and a plausible reason, the bare project made `uploads/` world-writable in three runs out of three; the kit project in none. The interesting part is that the gate never fired: the kit arm never reached for the command, it declined on its own and cited the rule. On unhurried work the two are indistinguishable, and those measurements are published with their reasoning in [`evals/README.md`](evals/README.md).

The gates stop accidents, not determined attempts. On a command line there is always a way around a pattern; if you need a real boundary, run Claude Code in a devcontainer or a VM. `/doctor-csk` tells you whether you have one.

**Watching a gate fire.** Set `CSK_GATE_LOG=<path>` and every guard appends one line per decision: `BLOCK` / `ASK` / `ALLOW`, the rule, and the command. It is off unless you ask for it, write-only, and written after the verdict, so it cannot change one. Useful when you need to know whether a gate stopped something or the model simply never went there — those two leave identical traces.

---

## Install

Two entry points: **`start.sh`** for a new project, **`adopt.sh`** for one already in motion. Every channel runs the same two commands.

```bash
# npx — nothing to install
npx @byerlikaya/claude-starter-kit                  # new project
npx @byerlikaya/claude-starter-kit adopt            # existing project
npx @byerlikaya/claude-starter-kit@latest update    # refresh an installed kit

# Homebrew
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit          # new project
claude-starter-kit adopt    # existing project

# Release tarball — no package manager
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # new project
bash adopt.sh               # existing project (re-run it to update)
```

**Windows:** Claude Starter Kit is bash-based. Run it in **Git Bash** ([git-scm.com](https://git-scm.com)); WSL works as a fallback.

**Plugin edition** — just the agents, skills and gate hooks inside your existing Claude Code, no scaffolding:

```bash
/plugin marketplace add byerlikaya/claude-starter-kit
/plugin install claude-starter-kit@byerlikaya
```

An installed plugin stays on the version you installed until you ask for a newer one, so run `claude plugin marketplace update byerlikaya` then `claude plugin update claude-starter-kit`, and restart to apply.

### New project

```bash
bash start.sh [--dotnet|--generic] [-h]
```

Two steps: backend pattern, then a summary you approve before anything is written.

**Every install is the same install** — all 12 agents and all 38 skills, backend and web and mobile (React Native/Expo) together. A project that starts as an API and grows a web client is already equipped for both.

| Asked at install | Options | What it changes |
|:--|:--|:--|
| Backend pattern | `--dotnet` · `--generic` | the `devarch-module` skill and the DevArchitecture base |
| DevArch base — only on `--dotnet` | approve · skip | whether `./backend` is scaffolded |

**`--dotnet`** clones the production-ready [DevArchitecture](https://github.com/DevArchitecture/DevArchitecture) foundation (CQRS · IResult · AOP · auth) behind an approval gate, and installs agents that already know it — so tokens go to your business logic instead of regenerating a standard architecture. The backend goes in `./backend`, `./frontend` is reserved next to it, and the solution file is renamed to your project.

**`--generic`** installs the same expert without that pattern — for Node, Go, Python, or a .NET project on a different pattern. Nothing forces DevArchitecture: the backend expert applies whichever pattern skill your project declares.

### Existing project

```bash
bash adopt.sh    # at the root of the target project
```

<div align="center">
  <img src="assets/handover-en.svg" alt="How adopt.sh hands the kit over" width="900">
</div>

Claude Starter Kit arrives the way one team hands a project to another: nothing is broken, decisions already made are not lost, and it does not sit there passively.

Every change lands on a separate branch, **staged and not committed** — so each added and changed file appears in your editor's Source Control panel. You review it there, then `git commit` to accept or `reset` to discard. `main` stays untouched. Its agents install side by side without colliding, the discipline binds through one `@import`, `settings.json` is merged schema-aware, and existing husky or lefthook chains keep running through a shim. It closes with a durable `docs/HANDOVER.md` and an ADR, so the decisions live in version control rather than in a chat log.

### Updating

```bash
npx @byerlikaya/claude-starter-kit@latest update    # or /update-csk inside a session
```

<details open>
<summary>🔁&nbsp; <b>Update mechanics — what is refreshed, and where the change lands</b></summary>

At install time Claude Starter Kit stamps `.claude/kit.conf` with the backend pattern and which installer ran, plus `.claude/VERSION`. A refresh **keeps the pattern**: a `--dotnet` project keeps `devarch-module`, and a Node repo is never handed one. Where the stamp is missing, the updater reads the pattern back from the installed files. Any missing component is restored, and every one it adds is **named in the output** rather than appearing silently.

| | On update |
|:--|:--|
| `.claude/` agents · skills · commands · hooks · eval | refreshed from the new version |
| `.claude/DISCIPLINE.md` | **overwritten** — it is kit-owned, so keep nothing of your own in it |
| `./CLAUDE.md` | never touched — your project rules stay exactly as written |
| `.claude/settings.json` | merged schema-aware; your own hooks and permissions survive |
| your own agents and skills (no `-csk` suffix) | untouched |

Where the change lands is a choice. A first adopt opens a `kit-adopt-<timestamp>` review branch. A routine update whose `.claude/` is gitignored applies on your current branch. An update with a **tracked** `.claude/` asks. Force it with `--here` or `--new-branch`, and skip the prompts with `--yes`. Either way the change is staged and uncommitted.

Inside a session, **`/update-csk`** does the version check, runs the updater, verifies with `/doctor-csk`, then prompts `/compact` so the refreshed discipline loads in the same session. **`/doctor-csk`** checks a live install at any time — hooks executable, `core.hooksPath` set, gates wired, the discipline actually imported — and prints an advisory readiness score for the project itself.

If a project's `CLAUDE.md` carries the discipline **inline** instead of importing it, updates cannot reach it. The updater detects this, shows the affected lines, and offers to replace them with the single `@.claude/DISCIPLINE.md` import — writing a backup first, on a branch you review. Decline and nothing is touched.

</details>

---

## Session and token cost

How full a session is gets **measured, not estimated** — the real token count, read every turn, the same figure `/context` reports. One warning at **75%**, one more at **90%**, and neither interrupts your turn.

The standing cost is published, not hidden. The discipline plus every agent and skill description load into each session: **~24 KB**, on the order of **~10k tokens** on a real turn — calibrated against an actual run, never estimated. Each skill you add is a permanent **~100-token** tax on every session, so a byte budget per component is enforced as a gate. Raising it takes an explicit edit to the test.

**Why not install fewer components?** Because it buys almost nothing. The whole set costs **~3.3k tokens** of description; leaving out the four UI skills and the frontend agent saves **~400 tokens** — about **0.2%** of a 200k window. That is worth controlling per component, which the byte budget does, rather than per project.

## Verification

```bash
bash .claude/eval/smoke-test.sh      # structure, frontmatter, gate integrity
bash .claude/eval/routing-eval.sh    # does an example prompt reach the right agent or skill
bash .claude/eval/doctor.sh          # is this install healthy, and is the project ready
```

## Extending

When you add an agent or a skill, follow the `AGENT_TEMPLATE.md` contract: frontmatter (name · description with trigger phrases · least-privilege tools · model tier) and body (When → Expertise stance → How → Coordination → Definition of Done → Output → Escalation → Example → Constraints). `smoke-test.sh` refuses a component that nothing routes to, so nothing ships asleep.

## Licence and attribution

MIT — see [LICENSE](LICENSE).

- **[NIST SP 800-218 (SSDF)](https://csrc.nist.gov/pubs/sp/800/218/final)** PW.7 and the **[OpenSSF Scorecard](https://github.com/ossf/scorecard)** `Code-Review` check — the governance layer of `code-review-csk`: that review happens, and that findings are recorded and triaged.
- **[Conventional Comments](https://conventionalcomments.org/)** — the comment label vocabulary `code-review-csk` writes in (CC BY 3.0).
- **[google/eng-practices](https://github.com/google/eng-practices)** — the review priority order and the "code health" bar in `code-review-csk`, distilled and restated (CC-BY 3.0).
