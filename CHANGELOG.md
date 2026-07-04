# Değişiklik Günlüğü

Bu projenin önemli değişiklikleri burada tutulur. Biçim [Keep a Changelog](https://keepachangelog.com/tr/),
sürümleme [SemVer](https://semver.org/lang/tr/).

## [1.0.0] - 2026-07-03

İlk kararlı sürüm. Türkçe, opinionated-ama-backend'i-seçmeli agent/skill iskeleti.

### Eklendi
- **10 ajan** (ince tetikleyici) + **27 skill** (disiplin katmanı: kod-inceleme, güvenlik, veritabanı,
  dağıtım, gözlemlenebilirlik, dokümantasyon, erişilebilirlik, api-tasarımı, performans, olay-müdahale,
  red-team, i18n, gizlilik, sürüm ve daha fazlası).
- **Profilli kurulum sihirbazı** (`start.sh`): `--backend/--frontend/--mobile/--fullstack` +
  backend yığını `--dotnet` (DevArchitecture tam) / `--generic` (yığın-bağımsız). Bayrak yoksa interaktif.
- **DevArchitecture backend temeli**: sıfırdan projede onay kapısıyla birebir dahil; mevcut projede uyarı.
- **Kural→kapı**: iz-denetçisi (`pre-commit`/`commit-msg` + repo-özel `.trace-allowlist.txt`), `guard-bash.sh`
  destrüktif blok, `settings.json` izin kapıları.
- **Gerçek context ölçümü**: `context-usage.sh` transcript'ten gerçek doluluğu okur; `UserPromptSubmit`
  hook'u her tur enjekte eder — oturum-sağlığı tahmine değil ölçüme dayanır.
- **Doğrulama**: statik `smoke-test.sh` + davranışsal `routing-eval.sh` (golden routing + çakışma).
- **CI**: GitHub Actions her push/PR'da sözdizimi + smoke + routing + 6 profil e2e prova.

### Notlar
- Disiplin katmanı ve frontend yığın-bağımsız; backend opinionated (.NET/DevArchitecture) veya jenerik.
- Dil Türkçe. Yapay zeka izi / üçüncü-taraf şablon adı artefaktlara sızmaz (§4).

[1.0.0]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.0
