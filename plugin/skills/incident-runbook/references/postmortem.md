# After the incident — postmortem & runbook

Both of these happen **after** the live response is over, not during it. Get the impact stopped first (SKILL.md);
come here once the incident is resolved.

## Postmortem (blameless)
Once the incident is resolved, within 24-72 hours:
- **Timeline**: detection → response → resolution (actual times).
- **Impact**: who, for how long, what was lost.
- **Root cause**: "5 whys"; the system/process is questioned, not the person (**blameless**).
- **Actions**: concrete, owned, dated items that prevent a recurrence (no deferral).
- If a lasting decision came out of it → `adr`.

## Produce a runbook
For repeatable incidents, a step-by-step runbook: symptom → diagnostic commands → mitigation → verification → escalation.
The runbook must be **project-specific** and **executable** (not generic); coordinate with `docs-writer`.
