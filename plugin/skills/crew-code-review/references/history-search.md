# Searching the history by code — the exact git forms

Read this when a confirmed finding needs its history checked. The rule is in SKILL.md: search by **code**, not by
commit message. This file is the mechanics.

Bounded at the branch point and scoped to the diff's paths, so it stays cheap per finding:

```bash
git log -S'<exact token from the changed line>' "$(git merge-base HEAD <target-branch>)" -- <paths in the diff>
```

`-S` lists the commits where the NUMBER OF OCCURRENCES of that string changed — added or deleted. A commit that
removes it in one place and adds it back in another leaves the count unchanged and does not appear, which is
exactly the "was the guard moved?" case: reach for `-G'<regex>'` there, which matches added or removed lines
against a regular expression regardless of count. `--follow` continues across renames but works on a single
path only, so it does not combine with the multi-path form above.

**`--grep` does not answer this.** A commit message states intent, not content: it misses fixes worded differently
and matches commits that changed nothing relevant. Use it only to read a commit you already found by content.
