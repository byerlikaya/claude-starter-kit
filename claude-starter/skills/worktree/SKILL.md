---
name: worktree
description: |
  Isolate risky or parallel file-mutating work in a git worktree so the main tree's uncommitted changes are never
  clobbered. For fan-out agents that edit files, throwaway experiments, or any change you may want to discard cleanly.
  Trigger phrases: "worktree", "git worktree", "isolate the changes", "sandbox this work", "parallel file edits"
---

# Worktree Isolation

One rule: **never let risky or parallel work run on top of uncommitted changes in the shared tree.** A git worktree
gives a second working copy of the same repo on its own branch — you experiment or fan out agents there, and the main
tree (with your in-progress edits) is physically untouched. Throw the worktree away and nothing you cared about is lost.

> **Kit adaptation (local, .claude/):** this exists because verification/fan-out subagents have discarded a session's
> **uncommitted** work by running a destructive git command over the shared tree. Those commands (`reset --hard`,
> `clean -f`, `checkout -- .`, `restore`) are §4.5-gated — but the real fix is to not put them near unsaved work.
> The Agent tool's `isolation: "worktree"` does this automatically for parallel mutating agents; reach for it there.

## When to isolate
- **Fan-out that writes files** — two+ agents editing the same repo in parallel would collide; give each its own worktree.
- **A throwaway experiment** — you might keep it or bin it; a worktree makes "bin it" a one-liner, not a `reset --hard`.
- **A dirty tree you can't commit yet** — you have unsaved work but need to try something risky; isolate rather than stash-and-pray.
- Skip it for a single, in-place edit on a clean tree — a worktree is overhead there.

## How
1. **Detect** — are you already in a worktree? `[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]` is true inside one; don't nest.
2. **Create** — `git worktree add ../wt-<name> -b <branch>` (new branch) or `git worktree add ../wt-<name> <existing>`. It shares the object store, so it's cheap.
3. **Work there** — cd into it; edits, builds, and agent runs stay local to that copy.
4. **Fold back or discard** — keep: commit on its branch, then merge. Discard: `git worktree remove ../wt-<name>` (add `--force` only if you mean to drop its changes).
5. **Clean up** — `git worktree prune` removes stale entries. Never leave orphaned worktrees around.

## Invariant rules
1. **Isolate before risk, don't revert after** — a worktree replaces "run `checkout -- .` to undo"; the undo is `worktree remove`.
2. **One worktree per parallel writer** — never two agents mutating the same tree at once.
3. **Don't nest** — creating a worktree from inside a worktree; detect first.
4. **Commit or isolate before delegating file-mutating work** — a subagent must never be able to discard the main tree's unsaved changes.
5. **Remove what you add** — no orphaned worktrees; `remove` + `prune` when done.
