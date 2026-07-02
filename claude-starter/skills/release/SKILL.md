---
name: release
description: |
  Sürümleme ve CHANGELOG: SemVer eşlemesi (Conventional Commits'ten), Keep a Changelog formatı,
  etiketleme, release öncesi kapılar. Sürüm çıkışında çalışır.
  Trigger phrases: "release", "sürüm", "changelog", "versiyon", "tag at", "semver"
---

# Sürüm & CHANGELOG

## SemVer eşlemesi (Conventional Commits'ten türet)
- `fix:` → **PATCH** (x.y.Z)
- `feat:` → **MINOR** (x.Y.0)
- `BREAKING CHANGE:` / `feat!:` → **MAJOR** (X.0.0)

## CHANGELOG (Keep a Changelog)
Başlıklar: **Added · Changed · Fixed · Removed · Security · Deprecated**.
Her sürüm tarihli; `Unreleased` bölümü commit'lerden otomatik doldurulabilir.

## Release öncesi kapılar (hepsi geçmeli)
- [ ] Testler yeşil + `sonarqube-check` PASSED
- [ ] `dependency-audit` temiz (0 HIGH/CRITICAL)
- [ ] CHANGELOG güncel
- [ ] Sürüm numarası SemVer'e uygun

## Etiketleme
```bash
git tag -a vX.Y.Z -m "vX.Y.Z"    # onay ister (§4.4); push açık talep (§4.5)
```

## DoD
- Doğru SemVer artışı; CHANGELOG eksiksiz; etiket + rollback planı hazır.
