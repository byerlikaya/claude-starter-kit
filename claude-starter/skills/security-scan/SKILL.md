---
name: security-scan
description: |
  Stack-agnostic security audit: map the attack surface, trace untrusted input to dangerous calls, surface
  dependency and configuration flaws. Severity-ranked report with fixes.
  Trigger phrases: "security scan", "run a security scan", "OWASP check", "scan for vulnerabilities", "find security vulnerabilities", "security audit"
---

# Security Scan

The core of a security vulnerability fits in a single sentence: **an untrusted input reaches a
dangerous operation without being adequately checked.** This skill chases exactly that sentence — it first
looks for where the input comes from, then where it flows, and what gate should sit in between.
It is stack-agnostic: whatever the language/framework, the same logic applies; when current tooling and
patterns are needed, it runs a web search.

> **Kit adaptation (local, .claude/):** `security-expert-csk` applies this; findings are carried to
> **review-agent-csk** in severity order. It also holds for the default stack (.NET/PostgreSQL). Automatic
> fixes only with explicit approval (§4.4); `.claude` does not go to the repo (§4.3). §4 Prohibitions apply.

## What it does, what it doesn't
- **Does:** surfaces common vulnerability classes, known vulnerable dependencies, and risky configuration; ties each finding to a concrete fix.
- **Doesn't:** does not replace a professional pentest / SAST / DAST. The report **guides**, it does not give full assurance — state this at the end of the report.
- **Boundary:** analysis is local; code/data is not sent to an external service, and the project directory is not left.

## Mental model — source → gate → sink
Reduce every check to three questions:
1. **Source** — where does the input enter? (route, API endpoint, form, CLI argument, file upload, WebSocket, queue message, external API response)
2. **Sink** — which dangerous operation does this input reach? (SQL execution, shell, file path, HTML render, deserialization, template)
3. **Gate** — is there validation / parameterization / escaping / authorization in between? If not, that's the finding.

The scan applies this model on four fronts: **dependency · code · configuration · authorization**. The result is ranked by severity, and the fix is presented for the user to choose.

## Checklist
- [ ] Stack and package ecosystem(s) detected, attack surface mapped
- [ ] Dependency audit run for each ecosystem
- [ ] Source→sink paths traced across the four vulnerability classes
- [ ] Configuration and secret leakage scanned
- [ ] Authorization matrix produced, unprotected sensitive endpoints searched for
- [ ] Findings reported in severity order, no secret disclosed
- [ ] Fix options presented to the user

---

## Fronts

Five review fronts — Discovery · Dependencies · Code (source→sink) · Configuration · Authorization: **`references/fronts.md`** (read the fronts you're scanning).

---

## Report

The severity scale, finding format, summary line, and the fix-presentation format live in **`references/reporting.md`**.

## Invariant rules
1. **Guides, does not assure** — it does not replace a professional audit; say so in the report.
2. **Mask secrets** — only the first 4 + last 4 characters (`sk-p…i789`); never write the full secret.
3. **No automatic fix without approval** — even if "Fix everything" is chosen, first show what will change.
4. **Do not install tools without asking.**
5. **Preserve behavior** — a fix must not change functionality beyond closing the vulnerability.
6. **Stay local** — do not send code/data to an external service, do not cross the project boundary.
