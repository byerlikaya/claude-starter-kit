---
name: dependency-audit
description: |
  Dependency audit: known vulnerabilities (CVE), license compliance, abandoned/outdated packages, lockfile
  integrity, justification for new dependencies. Runs when a package is added/updated or a lockfile changes.
  Trigger phrases: "dependency", "dependency audit", "npm audit", "package security", "CVE", "license"
---

# Dependency Audit

## Audit axes
1. **Known vulnerabilities (CVE):** audit appropriate to the ecosystem
   ```bash
   npm audit --production           # Node
   dotnet list package --vulnerable # .NET
   pip-audit                        # Python
   ```
2. **License compliance:** flag licenses incompatible with the project such as copyleft/GPL (a risk in commercial closed source).
3. **Maintenance status:** note abandoned / long-unmaintained / single-maintainer packages.
4. **Transitive dependencies:** also scan vulnerabilities in indirect dependencies.
5. **Lockfile integrity:** lockfile committed and consistent with the manifest; versions pinned.
6. **Justification for new dependencies:** is it actually needed? Don't add a heavy package for a single small function (supply-chain surface).

## Output
Severity-sorted list: `package · version · issue (CVE/license/maintenance) · upgrade path`.

## DoD
- 0 known HIGH/CRITICAL vulnerabilities; licenses compliant; lockfile consistent; every new package justified.
