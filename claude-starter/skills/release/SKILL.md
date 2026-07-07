---
name: release
description: |
  Versioning and CHANGELOG: SemVer mapping (from Conventional Commits), Keep a Changelog format,
  tagging, pre-release gates. Runs at version release.
  Trigger phrases: "release", "version", "changelog", "version bump", "tag", "semver"
---

# Release & CHANGELOG

## SemVer mapping (derive from Conventional Commits)
- `fix:` → **PATCH** (x.y.Z)
- `feat:` → **MINOR** (x.Y.0)
- `BREAKING CHANGE:` / `feat!:` → **MAJOR** (X.0.0)

## CHANGELOG (Keep a Changelog)
Headings: **Added · Changed · Fixed · Removed · Security · Deprecated**.
Every version is dated; the `Unreleased` section can be auto-populated from commits.

## Pre-release gates (all must pass)
- [ ] Tests green + `sonarqube-check` PASSED
- [ ] `dependency-audit` clean (0 HIGH/CRITICAL)
- [ ] CHANGELOG up to date
- [ ] Version number conforms to SemVer

## Tagging
```bash
git tag -a vX.Y.Z -m "vX.Y.Z"    # asks for approval (§4.4); push on explicit request (§4.5)
```

## DoD
- Correct SemVer bump; complete CHANGELOG; tag + rollback plan ready.
