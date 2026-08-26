---
name: skill-csk
description: Author or change a kit component (skill / agent / command) against the template and its gates.
---
# /skill-csk

`AGENT_TEMPLATE.md` states the contract for a component. It ships with a `start.sh` install — `adopt.sh` and the
plugin edition do not carry it. The discipline names it in passing, but no gate checks that anyone reaches it:
§3b iterates skills and agents only, so this doc can go stale unread. This command is the deliberate route, and
it ends in the gates rather than in a claim.

**A component is not finished when it is written. It is finished when the suite says so.**

## 1. Decide the shape before writing anything
Read `.claude/AGENT_TEMPLATE.md`. Then answer, in one line each:

- **What is the smallest form that works?** A rule in an existing skill's body beats a new skill; a new skill beats
  a new agent. Every new skill costs its NAME in every session, forever, for every user — and its description too,
  until the listing overflows its budget, at which point descriptions start being dropped from the skills you
  invoke least. Say what that buys.
- **Who reaches it?** An agent, a command, or the discipline's trigger map. If the answer is "the model will notice
  the description", stop — that is the dark component §3b exists to catch.
- **Read or write?** A component that reports and a component that changes files do not belong together: different
  risk, different done-criterion. Split them.
- **Is it stack-neutral?** Anything shipped to every profile names no language, framework or vendor as *the* case.
  The example you have in mind is not the scope.

## 2. Write it
- Skill: `.claude/skills/<name>/SKILL.md` — the directory name and the `name:` field must match. Keep the body
  lean; depth goes to `references/*.md` and is loaded on demand.
- Agent: a thin trigger — *who and when*. The *how* lives in the skill it applies; do not copy the method in.
- The `description` says **when to reach for this**, not what its author knows.

## 3. Register it — the cascade, in this order
Skipping one of these is how a component ships half-installed:
1. **Route it.** Name it in an agent body, a command, or the trigger map. §3b checks exactly this.
2. **Golden case.** Add a positive line to `.claude/eval/golden-routing.txt` — and a **negative** one
   (`prompt|!target`) for a neighbour it must NOT steal.
3. **Catalog + counts** *(kit repository only — `packaging/` is not installed anywhere)*.
   `bash packaging/build-readme-catalog.sh` (both READMEs), and the network diagram if the component set changed:
   `python3 packaging/gen-network.py assets` — **the target directory is an argument**; without it the SVGs land in
   the current directory and `assets/` silently stays stale.
4. **Plugin edition** *(kit repository only)*. `bash packaging/build-plugin.sh` — in the same commit, or the
   release stops at the sync gate.
5. **Budget.** A new skill moves `BUDGET_SKILLS`; raise it in the same commit with the justification comment the
   file's convention requires. Never raise it to make a red gate green without saying why.

## 4. Prove it — run all four, in this order
```
bash .claude/eval/scan-skill.sh .claude/skills/<name>    # supply-chain: SAFE, and rc=3 means NOT scanned
bash .claude/eval/routing-eval.sh                        # the golden case, positive and negative
bash .claude/eval/smoke-test.sh                          # structure, budget, §3b routed, cross-links
bash .claude/eval/doctor.sh                              # the live install still healthy
```

In the plugin edition none of the four commands above exist — it ships no `eval/` at all — so there the proof is
the kit repository's own suite, not a local run.

**Do not finish while §3b is red.** "It works when I invoke it by name" is not the claim being tested — the claim
is that something reaches it without being told to. If the suite skips a case, that is not a pass: chase why.
