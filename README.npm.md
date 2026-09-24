<p align="center"><img src="https://raw.githubusercontent.com/byerlikaya/claude-starter-kit/main/assets/logo.svg" alt="Crewforth" width="420"></p>

**Your engineering crew for Claude Code.** 12 specialists plan, build, review and ship your change — in any stack — and the rules that matter are enforced, not remembered.

```bash
npx crewforth          # new project
npx crewforth adopt    # existing repo — handed over on a branch, your main untouched
```

[![npm](https://img.shields.io/npm/v/@byerlikaya/claude-starter-kit?style=flat-square)](https://www.npmjs.com/package/@byerlikaya/claude-starter-kit)
[![License](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)](https://github.com/byerlikaya/claude-starter-kit/blob/main/LICENSE)

## Install

```bash
npx crewforth              # new project — setup wizard
npx crewforth adopt        # existing project — handover on a branch
npx crewforth update       # refresh an installed kit
npx crewforth --version    # print the kit version
```

The previous command, `npx @byerlikaya/claude-starter-kit`, still works and installs the same kit.

Then open Claude Code and run `/doctor-crew` to confirm the install is wired.

Requires **bash** and **git**. On Windows, run it in Git Bash.

## What you get

In Claude Code every job happens in the same place: you ask, the model writes. Claude Starter Kit puts a team and an order in between.

- **12 specialist agents** across five stages — plan, build, audit, close, hand off. An ambiguous request goes to planning first; a security review is mandatory before a risk-critical change can close.
- **40 skills** holding the method — testing, migrations, API contracts, observability, accessibility, deployment — written once, applied by whoever needs it. You stop re-explaining your standards every session.
- **11 slash commands** — `/plan-crew`, `/review-crew`, `/ship-crew`, `/handoff-crew`, `/brainstorm-crew`, `/update-crew`, `/doctor-crew`, `/board-crew`, `/gates-crew`, `/skill-crew`, `/studio-crew`.
- **A team board, when more than one of you shares the repo.** Taking an item is a push to a git ref, and pushing is fast-forward-only — so of two simultaneous claims exactly one lands and the other is refused in under a second, before any code is written. Decisions and handover notes travel with it, so what one session settled reaches the next person's. Off until you ask for it; solo work never sees it.
- **Guardrails that hold on their own.** Destructive commands are refused before they run, commits wait for your approval, secrets and AI-authorship traces never reach history — enforced at the tool level, not left to the model.
- **Safe adoption.** `adopt` lands everything on a branch, staged and uncommitted, so you review the whole change before keeping it. `main` is never touched.

## Measured, not asserted

The same prompt is run in a Claude Starter Kit project and a bare one, graded on what each left on disk. Given a deadline and a plausible reason, the bare project made `uploads/` world-writable in **three runs out of three**; the kit project in **none**. On unhurried work the two are indistinguishable, and those measurements are published with their reasoning too — a harness that only reports its wins measures nothing.

The gates stop accidents, not determined attempts. For a real boundary, run Claude Code in a devcontainer or a VM.

## Other channels

Homebrew, a release tarball, and a Claude Code plugin edition are documented in the repository.

**[Full documentation →](https://github.com/byerlikaya/claude-starter-kit)** · [Türkçe](https://github.com/byerlikaya/claude-starter-kit/blob/main/README.tr.md)

## Licence

MIT © Barış Yerlikaya. The `code-review-crew` skill aligns with NIST SP 800-218 (SSDF) PW.7 and the OpenSSF Scorecard `Code-Review` check, writes comments in the [Conventional Comments](https://conventionalcomments.org/) vocabulary (CC BY 3.0), and its review priority order is distilled and restated from [google/eng-practices](https://github.com/google/eng-practices) (CC-BY 3.0).
