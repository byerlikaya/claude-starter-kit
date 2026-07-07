---
name: testing
description: |
  The "how" of testing: pyramid, AAA, isolation, risk-coverage, determinism; guarantees the
  "tests are green" promise. test-expert-cck applies this.
  Trigger phrases: "write a test", "run the tests", "coverage", "are the tests green", "unit test", "integration test"
---

# Testing Discipline

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
- The relevant test command is green (e.g. `dotnet test`); critical paths are covered; no empty/meaningless tests.
