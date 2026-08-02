# Claude Starter Kit

**A complete engineering setup for Claude Code.** 12 namespaced agents, 38 skills, and tool-level gates that enforce the rules a `CLAUDE.md` can only ask for.

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

A `CLAUDE.md` is a request — the model honours it when it remembers to. Claude Starter Kit moves the rules that matter into the tools.

- **Gates, not reminders.** A `PreToolUse` hook refuses destructive commands before the shell sees them. Commits stop for your approval even under `bypassPermissions`. Git hooks catch secrets and AI-authorship traces.
- **12 specialist agents** across five stages — plan, build, audit, close, hand off. A security review is mandatory before a risk-critical change can close.
- **38 skills** holding the method, written once and applied by whoever needs it.
- **7 slash commands** — `/plan-csk`, `/review-csk`, `/ship-csk`, `/handoff-csk`, `/brainstorm-csk`, `/update-csk`, `/doctor-csk`.
- **Safe adoption.** `adopt` lands everything on a branch, staged and uncommitted, so you review the whole change before keeping it. `main` is never touched.

Every component carries a `-csk` suffix, so nothing collides with your project's own agents or shadows a Claude Code built-in.

## Measured, not asserted

Installing agents does not make them run. On a focused, single-domain prompt — every agent installed, the delegation tool available — Claude Code keeps the work on the main thread and delegates **0 times in 24 sessions**. With Claude Starter Kit's routing hook, the same measurement returns **39 of 48** across four rounds.

An A/B harness runs the same prompt in a kit project and a bare one and grades what is left on disk. Seven cases so far, **six came back level** — all published with the reasoning, including the ones showing no advantage.

The gates are defence-in-depth, not a sandbox. For a hard boundary, run Claude Code in a devcontainer or a VM.

## Other channels

Homebrew, a release tarball, and a Claude Code plugin edition are documented in the repository.

**[Full documentation →](https://github.com/byerlikaya/claude-starter-kit)** · [Türkçe](https://github.com/byerlikaya/claude-starter-kit/blob/main/README.tr.md)

## Licence

MIT © Barış Yerlikaya. The `code-review-csk` skill aligns with NIST SP 800-218 (SSDF) PW.7 and the OpenSSF Scorecard `Code-Review` check, writes comments in the [Conventional Comments](https://conventionalcomments.org/) vocabulary (CC BY 3.0), and its review priority order is distilled and restated from [google/eng-practices](https://github.com/google/eng-practices) (CC-BY 3.0).
