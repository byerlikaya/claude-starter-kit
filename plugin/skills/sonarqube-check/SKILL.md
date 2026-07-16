---
name: sonarqube-check
description: |
  SonarQube quality gate (language-agnostic, local-first): 0 Bugs/Vulns/Hotspots/Code Smells, 0 build warnings.
  If no analyzer exists, install the language's local server-less Sonar analyzer and run it — never a remote server.
  Trigger phrases: "sonarqube", "quality gate", "code smell", "sonar scan"
---

# SonarQube Quality Gate (language-agnostic, local-first)

Zero-tolerance gate: a job does not close until the metrics below are clean. The analysis runs **locally** — it never
depends on a shared or remote SonarQube server. If the project has no analyzer wired, this gate **installs the
language's local, server-less analyzer and runs it itself** (no host URL, no token, nothing to reach).

## Gate (all mandatory)
- **0 Bugs · 0 Vulnerabilities · 0 Security Hotspots · 0 Code Smells**
- Build **0 warnings / 0 errors**
- Coverage above the threshold the project defines (especially on new code)

## The rule: bootstrap a local analyzer when absent
Detect the stack, then — if no analyzer is configured — install the local one and analyze in place:

| Stack | Local, server-less analyzer (install if missing) | Runs on |
|---|---|---|
| **.NET / C#** | `SonarAnalyzer.CSharp` NuGet (SonarSource Roslyn rules, build-time) + `<TreatWarningsAsErrors>` | every `dotnet build` |
| **JS / TS** | `eslint-plugin-sonarjs` (SonarSource's JS/TS rules inside ESLint) | `eslint .` |
| **Python** | `bandit` (security) + `pylint`/`ruff` (Sonar-equivalent local rules) | run in CI/pre-commit |
| **Java / Kotlin** | SpotBugs + PMD (local rulesets), or the SonarLint CLI | build task |
| **Go / PHP / other** | the language's Sonar-rule linter, run locally | its own runner |

For **.NET** — the case here — wire the analyzer once so every build enforces the rules, then the build itself is the
gate:
```xml
<!-- Directory.Build.props (repo root) — applies to every project -->
<Project>
  <ItemGroup>
    <PackageReference Include="SonarAnalyzer.CSharp" Version="*" PrivateAssets="all" />
  </ItemGroup>
  <PropertyGroup>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest-all</AnalysisLevel>
  </PropertyGroup>
</Project>
```
```bash
dotnet build --no-incremental   # any Sonar rule (Sxxxx) now fails the build → the 0/0/0/0 gate
```
This is exactly "install the analyzer and let it analyze itself" — no server, no token, offline-capable.

## Optional: a full SonarQube dashboard
Only when the project **already runs its own** SonarQube (self-hosted, or a local Docker Community instance it set up)
do you also push results for the dashboard — via `dotnet sonarscanner begin/end` or `sonar-scanner`. Never bind to an
external/shared server the project did not set up. The local analyzer above is the gate; the dashboard is extra.

## Principles
- **Clean as You Code:** the gate is zero on new/changed code; legacy debt is handled separately, but no new debt is added.
- **Security Hotspots are not ignored:** each one is reviewed and either marked "safe" with a rationale or fixed.
- Finding → the relevant expert fixes it; **no deferral**, no "we'll look at it later".

## DoD
- Local analyzer installed (if it was missing) and PASSED: 0/0/0/0, build 0 warnings / 0 errors; green before PR/merge.
