---
name: sonarqube-check
description: |
  SonarQube quality gate (language-agnostic): 0 Bugs · 0 Vulnerabilities · 0 Security Hotspots · 0 Code Smells,
  build 0 warnings/0 errors. Runs after tests/security in projects using SonarQube (Java · JS/TS · Python · Go · C# · PHP …).
  Trigger phrases: "sonarqube", "quality gate", "quality gate", "code smell", "sonar scan"
---

# SonarQube Quality Gate (language-agnostic)

Zero-tolerance gate: a job does not close until the metrics below are clean. SonarQube analyzes more than 30
languages; the gate is the same whatever the language — only the **scanner** that runs it changes with the stack.

## Gate (all mandatory)
- **0 Bugs · 0 Vulnerabilities · 0 Security Hotspots · 0 Code Smells**
- Build **0 warnings / 0 errors**
- Coverage above the threshold the project defines (especially on new code)

## Running (scanner per stack)
First detect the project's build system, then pick the right scanner:

- **Generic (JS/TS · Python · Go · PHP …)** — SonarScanner CLI + `sonar-project.properties`:
  ```bash
  sonar-scanner -Dsonar.host.url="<url>" -Dsonar.token="$SONAR_TOKEN"
  ```
- **.NET** — a dedicated scanner, since MSBuild integration is required:
  ```bash
  dotnet sonarscanner begin /k:"<project>" /d:sonar.host.url="<url>" /d:sonar.cs.opencover.reportsPaths="**/coverage.opencover.xml"
  dotnet build --no-incremental
  dotnet test --collect:"XPlat Code Coverage"
  dotnet sonarscanner end
  ```
- **Maven** — `mvn verify sonar:sonar` · **Gradle** — `gradle sonar` (SonarQube plugin).

Generate the coverage report per language (JS: lcov · Python: coverage.xml · Go: coverage.out · .NET: opencover) and
wire it in with the corresponding `sonar.*.reportPaths` key.

## Principles
- **Clean as You Code:** the gate is zero on new/changed code; legacy debt is handled separately, but no new debt is added.
- **Security Hotspots are not ignored:** each one is reviewed and either marked "safe" with a rationale or fixed.
- Finding → the relevant expert fixes it; **no deferral**, no "we'll look at it later".

## DoD
- Quality Gate PASSED; green before PR/merge.
