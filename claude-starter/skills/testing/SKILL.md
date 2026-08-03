---
name: testing
description: |
  The how of testing: pyramid, AAA, isolation, risk coverage, determinism. Guarantees the DoD's "tests are
  green". test-expert-csk applies it.
---

# Testing Discipline

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "write a test", "run the tests", "coverage", "are the tests green", "unit test", "integration test"

Goal: **behavior correctness** — test real behavior without breaking product code just to make a test pass.

## Principles
- **Pyramid:** many unit, fewer integration, few end-to-end (e2e). Limit e2e to critical flows.
- **AAA:** Arrange-Act-Assert; **one test = one behavior**.
- **Isolation & determinism:** external dependencies are mocked/faked; time and randomness are fixed; test order is independent.
- **Risk-coverage:** risk, not metrics. Critical path + **boundary** + **negative** + **authorization (IDOR/404)** scenarios.
- **Naming:** `what_it_tests_under_which_condition_what_it_expects` — on failure it is clear what broke.
- **Red-green:** first a failing test, then the implementation.

## Watch out
- **Flaky = bug:** an occasionally failing test is not tolerated; it is fixed at the root.
- In snapshot/golden-file tests, avoid needless brittleness (assert only the meaningful output).

## DoD (this skill's contribution)
- The project's own test command is green — read it off the manifest/CI (`dotnet test` · `npm test` · `pytest` ·
  `go test ./...`), don't assume one; critical paths are covered; no empty/meaningless tests.
