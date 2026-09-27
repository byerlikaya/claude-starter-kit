# Co-authoring a longer doc

Loaded on demand. For a substantial doc (a guide, tutorial, concept explainer, README rewrite) — not a mechanical
sync of a changed signature. Here the content lives in the author's head; your job is to draw it out and shape it,
not to invent it.

## Why not just write it

A generated long-form doc that no one steered reads as generic, states things the maintainer wouldn't, and quietly
guesses at intent — then it has to be rewritten anyway. Co-authoring front-loads the cheap questions so the expensive
draft is right the first time.

## The workflow

1. **Interview first (before drafting).** Ask, don't assume:
   - **Audience** — who reads this? (new user, integrator, contributor, ops) Their assumed knowledge sets the level.
   - **Intent** — what should the reader be able to *do* after? One doc, one job.
   - **Scope** — what's explicitly out of scope? (prevents the doc sprawling)
   - **Voice/constraints** — house style, terminology, things that must/mustn't be said.
   Keep it to the few questions whose answers actually change the draft — offer options where useful, don't interrogate.

2. **Outline, get sign-off.** Propose the section structure (headings + one line each) and confirm it *before* writing prose. Re-structuring an outline is cheap; re-structuring 800 words is not.

3. **Draft in passes, not one wall.** Write section by section (or a first full pass explicitly marked as a draft). Surface the open questions inline (`> TODO: confirm default value`) rather than silently guessing — the maintainer fills the gaps you can't.

4. **Revision loop.** Invite specific feedback ("is the auth section at the right level?"), apply it, and keep the diff reviewable. Don't rewrite wholesale on each round — converge.

5. **Then apply the base discipline.** Once the content is agreed, the SKILL.md rules take over: examples must actually run, no stale/dead wording, no real secrets, single-source (explain the code, don't copy it), and coordinate `i18n-integrity` if it's multilingual.

## Keep it honest

- Don't state capabilities, defaults, or roadmap you haven't verified — ask or mark as TODO.
- Don't pad to look thorough; the maintainer maintains every sentence you add.
- The author's voice wins over yours — you're drafting *their* doc, not authoring your own.
