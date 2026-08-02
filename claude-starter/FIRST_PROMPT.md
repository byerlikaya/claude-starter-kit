# Claude Code — First Prompt

After running `start.sh`, open Claude Code at the repo root and paste this:

```
New project. First load the context: ./CLAUDE.md (behavior + project + stack in one file)
+ read any spec/plan under docs/ if present.

Code review carries its own sources and licences in the code-review-csk skill. The backend pattern comes from the install —
generic: the existing repo pattern; .NET/DevArch: the project's declared pattern skill.

The specialists run the work; the main thread routes it. If an agent ever stays silent on work it owns, you can
force the choice: `@agent-<name>` guarantees that agent runs for one task.

Initial setup (DO NOT WRITE CODE, in order):
1) With /agents, show that every installed agent is recognized.
2) Skills come FULLY POPULATED (e.g. code-review · security-scan · observability · performance).
   Fine-tune to the project's stack ONLY if needed; the source/template NAME must NOT LEAK into any
   artifact that goes to the repo (code, namespace, comment, config) (§4.2). Domain-specific "how"s (if any)
   are written SEPARATELY under .claude/skills/.
3) If anything is missing/incompatible, STOP and report.

Working rules:
- Four principles: think-then-write · simplicity first · surgical change · goal-oriented.
- NO deferral. Ask me about important decisions WITH EXPLICIT OPTIONS (recommendation + rationale for each option).
- Every task closes with DoD: /simplify + tests green + sonarqube-check (0/0/0/0).
- Commits follow Conventional Commits; commit-agent-csk proposes and waits for my approval.
- §4 Prohibitions are absolute: no AI trace · no vendor name leaks · commit/push only with explicit approval.
- At the END of every reply, add session-manager-csk's session-health line (based on the /context percentage).

When done: let's plan this project's first sprint together WITH EXPLICIT OPTIONS (planner-csk).
End every reply with a single high-value next step.
```
