---
name: sonarqube-check
description: |
  SonarQube quality gate, any language, no company server needed: run SonarQube Community Build locally (Docker),
  read the real gate + issues, fix by rule id, re-scan and diff. A linter's green build is a pre-check, never the gate.
---

# SonarQube quality gate — produce the real report, locally

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "sonarqube", "quality gate", "code smell", "sonar scan", "sonar rapor", "A rating"

**Only a SonarQube analysis can say "rating A, 0 findings".** A clean `build` says the compiler was happy — a
different claim, about a different rule set. Passing one off as the other is how a team is told the code is clean
and then opens a report full of findings.

You do **not** need a company server or someone else's token to get the real thing: **SonarQube Community Build is
free, needs no licence key, and runs in one Docker container on this machine.** That is the default path here — the
gate is produced locally, offline, and it is a genuine SonarQube verdict, not a proxy for one.

Language-agnostic on purpose: SonarQube covers 20+ languages plus IaC (Terraform, Kubernetes, Dockerfile). Detect
what the project actually uses; never assume a stack.

## Step 1 — get a real analysis (pick the first that applies)

**a) The project already has a SonarQube** → use it, and skip to step 2.

**b) It does not → stand one up locally.** Docker one-liner, the Docker-free server zip, the first login and the
token: **`references/stand-up-server.md`**. No licence, no external account, nothing leaves the machine.

> **Restarting is not installing.** Bringing an already-approved service back up on this machine — the same
> image, the same volumes — is resuming what the user already said yes to, and this skill's own advice to keep
> a named volume assumes exactly that. A NEW image, a new volume, or a tool this machine does not have is an
> install, and needs the answer below.
>
> **Nothing here is installed without the user saying so.** Docker, Java, a scanner, a linter — each is a proposal
> with its cost stated, and the user picks. If they decline all of them, that is a valid answer: go to (c) and
> report "unverified" rather than installing anything to make a number appear.

Scan with whatever runner the project's stack uses — the scanner is the same product for every language:

| Project | Scan command |
|---|---|
| Any stack (generic) | `sonar-scanner -Dsonar.projectKey=app -Dsonar.sources=. -Dsonar.host.url=http://localhost:9000 -Dsonar.token=$T` |
| Maven / Gradle | `mvn sonar:sonar -Dsonar.host.url=… -Dsonar.token=$T` · `gradle sonarqube …` |
| .NET | `dotnet sonarscanner begin /k:app /d:sonar.host.url=… /d:sonar.token=$T` → `dotnet build` → `dotnet sonarscanner end /d:sonar.token=$T` |
| JS/TS, Python, Go, PHP, Ruby | the generic `sonar-scanner` above (add coverage report paths if the project produces them) |

**c) No server is possible at all** (no Docker, no Java, no permission to run one) → run the language's Sonar-rule
engine locally as a pre-check (**`references/local-engines.md`** — which engine per language, and how close it is
to Sonar's own rules) and **say what that is worth**, in these words rather than a
rating: *"the local rule engine reports N issues, none open; the SonarQube rating and the gate were not produced —
no analysis ran."* Then list what stays unverified: taint/injection, hotspot review state, coverage, duplication,
files outside the compiled language, and the project's own quality profile. Offer branch (b) — a local server, with
or without Docker — as the way to close it.

**Never invent the verdict.** A rating exists only where an analysis produced one; without it the honest output is
"unverified", and that is the sentence that saves the user from promising a clean report they cannot back.

## Step 2 — read the verdict, don't infer it

```bash
S=http://localhost:9000; K=app          # or the project's own host/key
curl -sfu "$T:" "$S/api/qualitygates/project_status?projectKey=$K"     # pass / fail, and which condition failed
curl -sfu "$T:" "$S/api/issues/search?componentKeys=$K&resolved=false&ps=500"   # rule id + file + line per finding
curl -sfu "$T:" "$S/api/hotspots/search?projectKey=$K&status=TO_REVIEW"          # hotspots are a SEPARATE endpoint
curl -sfu "$T:" "$S/api/measures/component?component=$K&metricKeys=alert_status,bugs,vulnerabilities,security_hotspots,code_smells,coverage,duplicated_lines_density,reliability_rating,security_rating,sqale_rating"
```

Also read the gate's definition (`/api/qualitygates/show`): most gates judge **new code**, not the whole project.
Chasing overall counts while the gate measures new code burns days and still fails; the reverse leaves real debt.
Know which one applies before planning the work.

## Step 3 — fix by rule, never by impression

Group findings by `rule` (`csharpsquid:S1481`, `typescript:S3776`, `python:S5852`, …) and take one rule at a time,
all occurrences together. Read what the rule actually asks, fix the cause, cite the rule id in the change. The
domain owner does the fixing — a security rule is `security-expert-csk`'s, a query/index rule is
`database-expert-csk`'s.

**Never close a finding by silencing it.** `#pragma warning disable`, `// NOSONAR`, `eslint-disable`, an exclusion in
`sonar-project.properties` — each one changes the report without changing the code. It needs a written reason and
the user's approval, every time.

**Security Hotspots do not close by editing code.** Each is reviewed in the UI and marked *safe* (with a rationale)
or *fixed*. Code changes alone leave it `TO_REVIEW` and the gate keeps failing.

## Step 4 — re-scan and diff. The loop is the deliverable

Re-run step 1's scan, re-read step 2, and report the **difference**: counts before → after, which rule ids
disappeared, which remain, which are new. "It should be clean now" is not a result — a second analysis is.
Repeat until the gate says `OK` and the counts are zero. Nothing here closes on a first pass.

## What even a local SonarQube cannot see

Community Build has no **taint/injection analysis** (data flow from user input to a dangerous sink — SQLi, XSS,
command injection); that engine is in the paid editions. It also has no branch/PR analysis. So a clean local gate
is not proof of injection safety: cover that with the **`security-scan`** and **`threat-model`** skills plus a
`security-expert-csk` review, and say which of the two verdicts you are reporting.

## DoD
- The verdict is quoted **from an analysis**: gate status, counts by severity, ratings, analysis date, and where it
  ran (project server or local container).
- Every finding closed by a code change, or by a suppression the user explicitly approved with a written reason.
- Hotspots reviewed in the UI, not merely edited around.
- A re-scan ran after the fixes and the before → after diff by rule id is reported.
- Injection risk stated separately (taint analysis is not in Community Build).
- Anything not done is said plainly — never implied clean.
