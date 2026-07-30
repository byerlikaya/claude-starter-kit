---
name: dependency-audit
description: |
  Dependency risk assessment, read-only: known CVEs, deprecated packages, licence compliance, maintenance
  status, lockfile integrity, and a justification for every new dependency. Acting on it is dependency-upgrade.
---

# Dependency Audit

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "dependency audit", "npm audit", "package security", "CVE", "license", "deprecated package"

**This skill only reports.** It changes no manifest and no lockfile — bringing dependencies current is
[[dependency-upgrade]], which classifies each move by risk and verifies the build. Keeping the two apart keeps
this one safe to run any time, on any branch, including one you are only inspecting.

## Audit axes
1. **Known vulnerabilities (CVE):** audit appropriate to the ecosystem
   ```bash
   npm audit --production           # Node
   dotnet list package --vulnerable # .NET  (cannot be combined with --deprecated/--outdated)
   pip-audit                        # Python
   ```
2. **License compliance:** flag licenses incompatible with the project such as copyleft/GPL (a risk in commercial closed source).
3. **Maintenance status:** abandoned / long-unmaintained / single-maintainer packages, and packages the registry
   itself marks **deprecated** — `dotnet list package --deprecated`, `npm view <pkg> deprecated`. A deprecated
   package is not a version problem: no bump fixes it, it needs a replacement.
4. **Transitive dependencies:** also scan vulnerabilities in indirect dependencies.
5. **Lockfile integrity:** lockfile committed and consistent with the manifest; versions pinned.
6. **Justification for new dependencies:** is it actually needed? Don't add a heavy package for a single small function (supply-chain surface).

## Output
Severity-sorted list: `package · version · issue (CVE/license/maintenance) · upgrade path`.

## DoD
- 0 known HIGH/CRITICAL vulnerabilities; licenses compliant; lockfile consistent; every new package justified.
