# Claude Starter Kit

**Not one assistant — an engineering team that actually runs.** 12 specialist agents, 39 skills, and a process that plans, builds, audits and reviews a change before it closes. On a shared repo, taking a work item is an atomic git claim, so two people cannot start the same one.

[![npm](https://img.shields.io/npm/v/@byerlikaya/claude-starter-kit?style=flat-square)](https://www.npmjs.com/package/@byerlikaya/claude-starter-kit)
[![License](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)](https://github.com/byerlikaya/claude-starter-kit/blob/main/LICENSE)

## Install

```bash
npx @byerlikaya/claude-starter-kit          # new project — setup wizard
npx @byerlikaya/claude-starter-kit adopt    # existing project — handover on a branch
npx @byerlikaya/claude-starter-kit update   # refresh an installed kit
```

Then paste `.claude/FIRST_PROMPT.md` as your first Claude Code message.

Requires **bash** and **git**. On Windows, run it in Git Bash.

## What you get

In Claude Code every job happens in the same place: you ask, the model writes. Claude Starter Kit puts a team and an order in between.

- **12 specialist agents** across five stages — plan, build, audit, close, hand off. An ambiguous request goes to planning first; a security review is mandatory before a risk-critical change can close.
- **39 skills** holding the method — testing, migrations, API contracts, observability, accessibility, deployment — written once, applied by whoever needs it. You stop re-explaining your standards every session.
- **8 slash commands** — `/plan-csk`, `/review-csk`, `/ship-csk`, `/handoff-csk`, `/brainstorm-csk`, `/update-csk`, `/doctor-csk`, `/board-csk`.
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

MIT © Barış Yerlikaya. The `code-review-csk` skill aligns with NIST SP 800-218 (SSDF) PW.7 and the OpenSSF Scorecard `Code-Review` check, writes comments in the [Conventional Comments](https://conventionalcomments.org/) vocabulary (CC BY 3.0), and its review priority order is distilled and restated from [google/eng-practices](https://github.com/google/eng-practices) (CC-BY 3.0).
