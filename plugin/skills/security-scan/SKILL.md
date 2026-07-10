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

## Front 0 — Discovery (map the surface)

The rest of the audit rests on the map produced here.

1. Scan for manifest/build files at the root and in subdirectories: `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`, `build.gradle`, `composer.json`, `*.csproj`, `*.sln`, `mix.exs`. In a monorepo, note each ecosystem separately.
2. Derive the framework and runtime from the manifest.
3. **List the attack surface:** all the points where user input enters the system (the "Source" list above). These are the starting points for the following fronts.
4. Run a **web search** for the detected framework — tooling and patterns change often: `"[framework] security best practices"`, `"[framework] common vulnerabilities"`, the current `"OWASP Top 10"` list.

---

## Front 1 — Dependencies

Known vulnerabilities in third-party packages are the cheapest path to most breaches.

1. Run the audit command that suits the ecosystem (if it is not installed, suggest installing it, do not install it yourself):

   | Ecosystem | Command |
   |---|---|
   | Node | `npm audit` · `pnpm audit` · `yarn npm audit` |
   | Python | `pip-audit` |
   | .NET | `dotnet list package --vulnerable --include-transitive` |
   | Rust | `cargo audit` |
   | Go | `govulncheck ./...` |
   | Ruby | `bundle audit` |
   | Java | OWASP Dependency-Check |

2. If you are unsure of the correct/current command, verify it on the web; where possible, get machine-readable output with `--json`.
3. Extract from each finding: package · installed version · vulnerability id (CVE/GHSA) · severity · fixed version.
4. In a monorepo, audit each sub-project separately. The results go into the report (below).

---

## Front 2 — Code (source→sink tracing)

Start from every entry point on the attack surface, trace the input to where it is used, and check whether there is a gate in between. The table below is the **minimum** coverage — if you see another sink during the scan, add it.

| Sink class | Vulnerability | What the "gate" should be |
|---|---|---|
| **Query** | SQL / NoSQL / LDAP / ORM raw query injection | Parameterized query; no string concatenation |
| **Command** | Shell/OS command injection | Argument array; no passing a string to the shell |
| **Render** | XSS (input in HTML without escaping), SSTI (input as template code) | Context-appropriate escaping; input as data, not code |
| **Path** | Path traversal, unrestricted file upload | Path allowlist/normalization; type-size-content validation |
| **Object** | Insecure deserialization, mass assignment | Safe format; field allowlist |
| **Expression** | Expression/eval injection, `eval`/`exec` | Never evaluate input as code |

**On state-changing + browser-originating endpoints, additionally:**
- **CSRF** — does the state-changing endpoint have token protection?
- **CORS** — is there a wildcard origin with credentials, or an origin reflected without validation?

**Secret leakage — hardcoded credentials in the source:** search for these patterns, excluding `.env.example` and test fixtures:
```
(password|api[_-]?key|secret|token)\s*[:=]\s*["'][^"']+["']
-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----
```
Also: unmasked password/token/PII in logs; a stack trace or internal path leaked to the user.

**Tracing method:** read the route/controller files (input enters here) → grep for dangerous calls (`eval`, `exec`, string-SQL) → check whether the middleware/interceptor has auth·CSRF·rate-limit → check whether the data model has mass-assignment protection. Run a web search for language-specific dangerous functions.

**Record for each finding:** file:line · vulnerability · what an attacker could do (impact) · fix specific to this code.

---

## Front 3 — Configuration

**Is a secret in the repo:**
```bash
git ls-files --error-unmatch .env 2>/dev/null && echo "WARNING: .env is tracked"
```
If it's a finding, CRITICAL: `git rm --cached .env` → add to `.gitignore` → **rotate the exposed secrets**.

**Debug on in prod:** search for the framework-specific flag with `"[framework] debug mode production"`. Signs: an open debug flag, an error page showing a stack trace, a published source map, accessible development endpoints.

**Insecure transport:** hardcoded `http://` addresses (API, webhook, OAuth redirect, CDN) that should be `https`, and cookies without `Secure`. Exclude `localhost`/`127.0.0.1`/`0.0.0.0`.

**Missing security headers:** CSP, HSTS, X-Frame-Options, X-Content-Type-Options.

---

## Front 4 — Authorization (auth-z)

Access-control flaws are the class most often missed in a scan, because the code appears to "work." Mandatory if the project includes admin/dashboard or role-based access:

1. Enumerate all roles/levels (admin, moderator, user, guest…).
2. Write all routes/endpoints and the **required** permission level into a matrix.
3. Verify that each protected route actually checks — "being logged in" is not authorization.
4. Look for endpoints that should be protected but aren't; try whether there is an admin endpoint reachable by guessing the URL.
5. Verify that authorization is enforced both at the controller **and** at the data-access layer (IDOR: object reference without ownership validation).
6. Privilege escalation: can a user change their own role/permission? Does a sensitive admin action require extra protection (re-auth/2FA)?
7. **JWT:** `alg: none` / algorithm confusion, secret embedded in code, missing expiration.

---

## Report

**Severity scale:**

| Level | Meaning |
|---|---|
| CRITICAL | Directly exploitable — urgent (SQL injection, hardcoded secret in prod) |
| HIGH | Serious — close before deploy (XSS, command injection, known CVE) |
| MEDIUM | Defense gap — soon (missing CSRF, loose CORS) |
| LOW | Best-practice violation — when convenient (debug mode, missing header) |
| INFO | Observation — no immediate risk |

**Finding format** (ranked by severity):
```
[CRITICAL] SQL Injection — src/api/users.ts:42
  Vuln  : Input concatenated directly into the SQL query
  Impact: DB can be read / modified / deleted
  Fix   : Use a parameterized query
```

**Summary line:**
```
=== Security Scan Summary ===
  CRITICAL: X · HIGH: X · MEDIUM: X · LOW: X · INFO: X · Total: X
```

## Fix presentation
```
How shall we proceed?
  1. Fix everything        2. CRITICAL+HIGH only
  3. Approve one by one    4. Manual (no changes)
```
For each fix: preview the diff → wait for approval → (if a dependency) upgrade command + breaking-change note → re-run the relevant check.

## Invariant rules
1. **Guides, does not assure** — it does not replace a professional audit; say so in the report.
2. **Mask secrets** — only the first 4 + last 4 characters (`sk-p…i789`); never write the full secret.
3. **No automatic fix without approval** — even if "Fix everything" is chosen, first show what will change.
4. **Do not install tools without asking.**
5. **Preserve behavior** — a fix must not change functionality beyond closing the vulnerability.
6. **Stay local** — do not send code/data to an external service, do not cross the project boundary.
