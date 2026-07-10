---
name: commit-message
description: |
  Conventional Commits: reads the staged diff and proposes `type(scope): summary`, with body/footer when needed.
  One logical change = one commit. commit-agent-csk applies it.
  Trigger phrases: "commit message", "make a commit", "conventional commit", "write a commit", "git commit"
---

# Commit Message (Conventional Commits v1.0.0)

Format: `type(scope): summary` + (optional blank line + body) + (optional footer).

## Type (required)
- `feat` — new feature             · `fix` — bug fix
- `docs` — docs only               · `refactor` — restructure with no behavior change
- `perf` — performance             · `test` — add/fix tests
- `build` — build/dependency       · `ci` — CI configuration
- `chore` — maintenance/automated  · `revert` — revert a previous commit
- `style` — formatting (no logic)

### Which type? (deciding when ambiguous)
- A new capability for the user? → `feat`. Fixing an existing wrong behavior? → `fix`.
- Behavior the same, only the structure changed? → `refactor` (if behavior changed it's `feat`/`fix`, not refactor).
- Touched only tests/docs/formatting? → `test`/`docs`/`style` (don't touch code logic).

## Scope (optional, preferred)
The affected area/module: `auth`, `api`, `backend`, `db`, `frontend`, `session`, `agent`, etc.
One word, consistent with the project's module name.

## Summary line
- **In the project's established language** (English by default for open source), imperative/summary mood, start lowercase, NO period at the end, ≤ ~72 characters.
- Say **what it does**, not how; avoid vague words ("fix", "update", "wip").
  ✅ `feat(auth): one-time code TTL + brute-force limit`
  ❌ `fix: bug` · ❌ `update` · ❌ `changes`

## Body (optional — recommended for meaningful changes)
After a blank line: the **WHY** (motivation) + notable consequences/tradeoffs. Wrap at ~72 characters.
Leave context for the future reader who opens git-blame — the diff already shows the "what"; you write the "why".

## Footer (optional)
- `BREAKING CHANGE: <description>` — a backward-incompatible breaking change (triggers SemVer MAJOR, `release` skill).
- `Refs: #<issue>` / `Closes #<issue>`.

## Atomic commit — splitting a mixed diff
If a diff contains several logical changes, **split it**; don't cram it into one commit:
```bash
git add -p            # pick hunk by hunk; stage related changes separately
git add <specific/file>
```
Each commit focused on a single topic; "feat + fix + refactor" doesn't belong in one commit.

## Good / bad
| ✅ Good | ❌ Bad |
|---|---|
| `fix(db): return 404 instead of 403 on IDOR (prevent entity leak)` | `fix: db issue` |
| `refactor(api): consolidate query handlers into one contract` | `refactor stuff` |
| `feat(session): session-health line + threshold rule` | `feat: added new stuff` |
| `revert: "feat(auth): code TTL"` (sha) | `reverted it` |

## Rules
- **Atomic:** one logical change = one commit.
- **No commit without DoD:** don't propose a message until `/simplify` + tests green + (if SonarQube is used) `sonarqube-check` 0/0/0/0 pass.
- If there is no staged diff, warn; ask the user about the `git add` scope with explicit options.
- Don't run `git commit` silently; propose the message, **wait for approval**.

## Prohibitions (absolute — see CLAUDE.md §4)
- **No AI trace:** no co-author trailer, auto-generation footer, or robot emoji in the subject/body;
  words naming an AI assistant, model, or coding tool, and the `.claude` name, do not appear in the message.
- **No vendor name:** the third-party template/skeleton name and any "vendor copy / cleanup" disclosure are not written in the message (§4.2).
- **Human, natural language:** the message is natural, technical, and in the project's established language (English by default for open source).
- **Approval:** commit only when the user says "commit"; "done" is not approval (§4.4).
- **Destructive:** amend / reset / force / `--no-verify` only on an explicit request; the hook is not skipped (§4.5).
