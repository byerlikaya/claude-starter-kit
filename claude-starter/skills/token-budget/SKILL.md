---
name: token-budget
description: |
  Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills.
  Trigger phrases: "token", "context", "context management", "context is full", "clear context"
---

# Token & Context Discipline

A subagent exists for context management: it runs in its own window and returns **only its summary**
to the main thread — intermediate noise (file reads, searches, logs) never enters the main context.
**Warning:** a subagent-heavy flow uses roughly 7x the tokens of a single thread; delegate for isolation, not for everything.

## Rules
1. **Output = summary.** The agent returns a short, structured summary to the main thread; it does **not** return raw logs / file dumps / long code.
2. **Move to a file.** Heavy output (a plan, scan report, inventory) is written to `docs/*.md`; a **summary + pointer** comes back. (local, in gitignore)
3. **Delegation threshold.** Noisy/heavy work (reading many files, scanning, research) → subagent. A single tool-call / small work → **main thread**.
4. **Least tooling.** An agent holds only the tools it needs; extras accidentally pollute the context + burn the limit.
5. **Lean SKILL.md.** Skills load into the main context; heavy reference goes to a separate file, only when needed.
6. **Targeted reading.** Instead of reading a whole file, pinpoint with Grep/Glob.
7. **Manage with /context.** session-manager-csk recommends continue/handoff+clear based on the real percentage; at a phase boundary, `/clear`.
