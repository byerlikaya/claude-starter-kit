# Running Sonar rules locally with no server at all

Read this only on branch (c) of step 1 — no server is possible (no Docker, no Java, no permission to run one), or
as a pre-check before anything is scanned.

This is worth more than it sounds: several languages have SonarSource's **own** rule engine as a normal dependency,
so you can find and fix most rule violations offline, before anything is ever scanned. What no local engine can
produce is the **verdict** — ratings (A/B/C), gate pass/fail, coverage, duplication, hotspot review state and the
project's quality profile are computed by the server, from an analysis. Findings yes; a rating no.

**The rule, for every language:** find whether SonarSource publishes its own rule engine for the project's
language and wire *that* into the build or the editor. Where only a third-party look-alike exists, use it and say
that the rule ids will not match the report. Ask which languages the repo actually contains — most repos have
more than one, and each needs its own engine.

| Stack (alphabetical — no language is the default) | Local engine | How close to Sonar's own rules |
|---|---|---|
| Go | `golangci-lint` and friends | Third-party; overlaps in intent, not in rule ids |
| Java / Kotlin | SonarQube for IDE (SonarLint) in the editor; SpotBugs + PMD in the build | Editor-side runs Sonar analyzers; the build-side pair is a different rule set |
| JS / TS | `eslint-plugin-sonarjs` | SonarSource's own JS/TS rules, delivered through ESLint |
| .NET (C# · VB.NET) | `SonarAnalyzer.CSharp` / `.VisualBasic` (Roslyn, at build time) | SonarSource's own analyzer, 480+ C# rules; rule-set parity with the server is not documented either way — close, not proven identical |
| PHP / Ruby / other | that language's linter | Varies; check whether it is SonarSource's or a look-alike |
| Python | `ruff` / `pylint` + `bandit` | **Not Sonar rules** — an approximation |

**Injection / taint rules are not in any of these** — they run only on SonarQube Server/Cloud, in the commercial
editions. So even a spotless local run says nothing about SQLi/XSS/command injection; that gap is covered by
`security-scan` + `threat-model` + a `crew-security-expert` review, and is reported as its own line, never folded
into a "clean" claim.

Pin versions so builds stay reproducible (with Central Package Management, declare it there). Turning warnings into
errors is the project's call — propose it, don't impose it. And whatever the local run says, the honest wording
stays: *findings fixed; rating and gate not produced — no analysis ran.*
