# Review fronts

The scan applies the **source → gate → sink** model on these fronts. Read the fronts you're scanning.

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
