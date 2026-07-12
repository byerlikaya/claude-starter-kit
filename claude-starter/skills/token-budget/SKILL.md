---
name: token-budget
description: |
  Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills.
  Trigger phrases: "token", "context", "context management", "context is full", "clear context"
---

# Token & Context Discipline

A subagent exists for context management: it runs in its own window and returns **only its summary**
to the main thread — intermediate noise (file reads, searches, logs) never enters the main context.

**Warning — measured, not guessed.** Each subagent re-pays its **full context from scratch**: in a real
transcript the first turn was `cache_read=0`, every token `cache_creation` — nothing is shared with the main
thread's cache. A **no-op** subagent (task = "reply DONE") already cost **~10k tokens with restricted tools and
~16k with full tool access**; that floor is base system prompt + tool schemas, paid fresh every time. Of the
always-on material only the **skill listing (~2.5–3k tokens) is inherited** by a subagent — the discipline
(`DISCIPLINE.md`/CLAUDE.md) and the agent descriptions are **not** injected into it. So a delegation is worth it
for **isolation / parallelism / a clean window**, or when the isolated work would otherwise cost the main thread
**more than that ~10–16k floor** — never by default.

## Rules
1. **Output = summary.** The agent returns a short, structured summary to the main thread; it does **not** return raw logs / file dumps / long code.
2. **Move to a file.** Heavy output (a plan, scan report, inventory) is written to `docs/*.md`; a **summary + pointer** comes back. (local, in gitignore)
3. **Delegation threshold.** Noisy/heavy work (reading many files, scanning, research) → subagent. A single tool-call / small work → **main thread**. Concretely: if the isolated work won't save the main thread more than the **~10–16k fresh-context floor** a subagent costs, keep it on the main thread — delegate for isolation, not to shave a few reads.
4. **Least tooling.** An agent holds only the tools it needs; extras accidentally pollute the context + burn the limit.
5. **Lean SKILL.md.** Skills load into the main context; heavy reference goes to a separate file, only when needed.
6. **Targeted reading.** Instead of reading a whole file, pinpoint with Grep/Glob.
7. **Manage with /context.** session-manager-csk recommends continue/handoff+clear based on the real percentage; at a phase boundary, `/clear`.
