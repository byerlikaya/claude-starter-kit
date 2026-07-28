---
name: confidence-check
description: |
  Readiness gate BEFORE writing implementation code: does this already exist, does it fit the project's
  architecture, is the API claim actually checked, is there a working reference, is the root cause known.
  Trigger phrases: "confidence check", "ready to implement", "before I start", "am I sure enough", "readiness"
---

# Confidence Check — earn the right to start

## When
Right before implementation code gets written for anything beyond a one-line change, and *after* the scope is
clear ([[spec-planning]] / planner). Every other gate in this kit fires at the end — review, DoD, the commit
approval. Those catch bad code. None of them catch **good code that should never have been written**: the
duplicate of a helper that already exists, the pattern that fights the project's architecture, the call built
against an API that behaves differently than remembered. That waste is invisible to a reviewer, because what
they see is a clean diff.

## The five checks
Each is answered with **evidence**, not with a feeling. Name what you ran or read.

| # | Check | How it is actually answered |
|---|---|---|
| 1 | **Does it already exist?** | Grep/Glob the codebase for the behaviour *and* its likely other names. A near-duplicate counts. |
| 2 | **Does it fit this project?** | Read `CLAUDE.md` + the relevant project skill. Same stack, same pattern, no new dependency smuggled in. |
| 3 | **Is the external claim verified?** | The API / library / config behaviour you are relying on: read the real docs or the installed source. Recalled API shapes are the single most common wrong assumption. |
| 4 | **Is there a working reference?** | An existing call site in this repo, or a known-good implementation. "It should work like this" is not one. |
| 5 | **Is the root cause known?** | For a fix: the *cause*, not the symptom. Unknown → this is a [[systematic-debugging]] task, not an implementation task. |

## The verdict is not a score
The tempting form is a weighted score with a threshold. It is theatre: with five checks and any sane bar, a
single failure sinks it anyway, so the weights only decorate a decision that was already binary. So: **any "no"
is a stop.** Say which check failed and do the one thing that answers it — search, read the doc, find the
reference, debug the cause — then start. If the user wants to proceed with a known gap, that is their call to
make explicitly, and it gets written down as an assumption, not swallowed.

Checks 3–5 do not apply to every task (a pure refactor has no external claim and no bug). Mark those **n/a**
with a reason — n/a is a judgement you are stating, not a check you are skipping.

## Output
Five lines, one per check: `✅ <what was run/read>` or `❌ <what is missing>` or `n/a — <why>`. Then either
"starting" or the single action that unblocks it. Keep it to the main thread; it is a handful of lines, not a
document.

## DoD (this skill's contribution)
- Every check is answered with a named command, file, or document — never with a recollection.
- Any "no" was resolved before implementation started, or is recorded as a user-accepted assumption.
- Check 1 was answered by an actual search, not by "I don't think we have one".
- A fix with an unknown cause went to [[systematic-debugging]] instead of being implemented on a guess.
