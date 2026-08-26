---
name: release
description: |
  Versioning and CHANGELOG: SemVer mapped from Conventional Commits, Keep a Changelog format, tagging,
  pre-release gates.
  Use when cutting a version: bumping, writing the CHANGELOG entry, or tagging.
---

# Release & CHANGELOG

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "release", "cut a release", "changelog", "version bump", "bump the version", "new version", "tag", "semver"

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
- [ ] **Every distribution channel has a documented way to GET this version.** Publishing and reaching users are
      different events. A channel whose consumers pin at install time — an editor extension, a plugin, a vendored
      copy — leaves them on the version they installed until they ask for a new one, so a security fix ships and
      does not arrive. For each channel name the upgrade command in the README, and say plainly where it is not
      automatic. This was a real gap: three channels documented `npm i -g` / `brew upgrade` / a refresh command
      while the plugin channel documented only how to install.

## Tagging
```bash
git tag -a vX.Y.Z -m "vX.Y.Z"    # asks for approval (§4.4); push on explicit request (§4.5)
```

## DoD
- Correct SemVer bump; complete CHANGELOG; tag + rollback plan ready.
