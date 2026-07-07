---
name: incident-runbook
description: |
  Production incident response and runbook discipline: stay calm-diagnose-mitigate-resolve, then a blameless postmortem
  and a repeatable runbook. Stop the impact first, then the root cause; make the lesson learned permanent.
  Trigger phrases: "incident", "incident response", "runbook", "postmortem", "root cause", "outage", "production incident", "post-incident"
---

# Incident Response & Runbook

Two modes: **live incident** (what to do right now) and **aftermath** (postmortem + runbook). Priority: stopping
user impact > finding the root cause. No panic, one ordered step at a time.

## Live incident — sequence
1. **Acknowledge & classify** — what is the impact (who, how much), severity (SEV1 full outage … SEV3 minor).
2. **Mitigate the impact FIRST** — rollback, turn off a feature flag, shift traffic, scale up. Without waiting on the root cause.
3. **Single coordinator** — it is clear who decides; communication goes through one channel.
4. **Diagnose** — last change? (deploy/migration/config) narrow it down with logs+metrics+traces (observability).
5. **Resolve** — the smallest safe fix; then verify (health check).
6. **Close** — confirm the impact is over; note the timeline (a postmortem input).

## Mitigation reflexes
- Last deploy suspect → **rollback** (vps-deploy revert).
- Suspect feature → turn off the **feature flag**.
- After a destructive migration → restore from backup (db-migration).
- Dependency/service down → circuit breaker / graceful degradation.

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

## Invariant rules
1. **Stop the impact, then understand** — the root cause does not hold up the resolution.
2. **Blameless culture** — the postmortem questions the system, not the person.
3. **Actions are owned + dated** — no "we'll look at it later".
4. **The runbook is executable** — real commands/steps, not wishes.
5. **Make learning permanent** — the lesson goes into an adr/runbook/monitoring, it does not get lost.
