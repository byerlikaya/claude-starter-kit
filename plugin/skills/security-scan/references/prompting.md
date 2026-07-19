# Prompting the review sub-agents (defensive security)

When the scan fans out a sub-agent per front, *how* you prompt it decides recall. Field-tested rules — these also
apply to `red-team` and any agent you point at a codebase to find bugs:

1. **Give the model room.** A high-level task beats prescriptive scaffolding. Long instructions, staged checklists,
   and piles of reference material tend to backfire — the model pattern-matches your scaffold instead of reasoning
   about the code.
2. **Describe vulnerability *shapes*, not a checklist.** Enumerating bug types ("find SQLi, XSS, and CSRF")
   **worsens** recall — the model stops at your list. Describe the structural property instead: *"attacker input
   that alters the syntactic structure of an interpreted string — SQL, shell, HTML, a template — or crosses a trust
   boundary without a gate."*
3. **Scope each agent.** Tell it precisely which slice of the surface to search **and which classes you don't care
   about**, so parallel agents don't all converge on the same easy findings. (A `threat-model` gives you this scope.)
4. **Frame verification adversarially.** "Actively look for reasons this finding is *wrong*" beats "check for
   protections" — the whole disprove pass lives in `references/verify.md`.
5. **State that vulnerabilities exist.** "Act like a pentester" is weak. Strong: *"Produce a findings report with a
   PoC for each Critical/High; assume there ARE vulnerabilities here; keep going until you've covered the surface."*
6. **Share mitigations the code doesn't show** (a WAF rule, a gateway auth check, a platform default) up front — it
   saves the reviewer from re-finding a path that is already closed one layer up (a common false positive).
7. **Prompt-level guardrails are defense-in-depth only.** Real safety is human approval + the tool-level gates
   (§4.4/§4.5), never a sentence in a prompt. Don't rely on "please don't exploit this" — rely on the gate.
8. **Assume the user can't see your tool calls or reasoning** — give periodic, plain-language progress updates.
