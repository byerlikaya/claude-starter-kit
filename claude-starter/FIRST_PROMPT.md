# Claude Code — First Prompt

After running `start.sh`, open Claude Code at the repo root and paste this:

```
New project. First load the context: ./CLAUDE.md (behavior + project + stack in one file)
+ read any spec/plan under docs/ if present.

The discipline layer derives from these sources; keep decisions ALIGNED with them:
- Working principles:  multica-ai/andrej-karpathy-skills
- Code review:         google/eng-practices
- Backend pattern:     <by profile — generic: existing repo pattern; .NET/DevArch profile: DevArchitecture/DevArchitecture>

Initial setup (DO NOT WRITE CODE, in order):
1) With /agents, show that the installed agents (count varies by profile) are recognized.
2) Skills come FULLY POPULATED (the installed set varies by profile; e.g. code-review · security-scan · observability · performance).
   Fine-tune to the project's stack ONLY if needed; the source/template NAME must NOT LEAK into any
   artifact that goes to the repo (code, namespace, comment, config) (§4.2). Domain-specific "how"s (if any)
   are written SEPARATELY under .claude/skills/.
3) If anything is missing/incompatible, STOP and report.

Working rules:
- Four principles: think-then-write · simplicity first · surgical change · goal-oriented.
- NO deferral. Ask me about important decisions WITH EXPLICIT OPTIONS (recommendation + rationale for each option).
- Every task closes with DoD: /simplify + tests green + sonarqube-check (0/0/0/0).
- Commits follow Conventional Commits; commit-agent-cck proposes and waits for my approval.
- §4 Prohibitions are absolute: no AI trace · no vendor name leaks · commit/push only with explicit approval.
- At the END of every reply, add session-manager-cck's session-health line (based on the /context percentage).

When done: let's plan this project's first sprint together WITH EXPLICIT OPTIONS (planner-cck).
End every reply with a single high-value next step.
```
