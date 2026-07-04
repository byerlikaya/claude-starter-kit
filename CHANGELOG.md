# Değişiklik Günlüğü

Bu projenin önemli değişiklikleri burada tutulur. Biçim [Keep a Changelog](https://keepachangelog.com/tr/),
sürümleme [SemVer](https://semver.org/lang/tr/).

## [Unreleased]

### Eklendi
- **`devops-expert` ajanı (11.)** — ops/devops uzmanı; `ci-pipeline` · `vps-deploy` · `incident-runbook`
  skillerini sahiplenir (bu skiller artık orkestrasyon-only değil). Core (tüm profillerde). Tasarım paneli +
  4-mercek düşmanca doğrulamayla üretildi.
- **Deploy tool-kapıları:** `settings.json` `permissions.ask`'e `ssh`/`scp`/`rsync`/`docker` eklendi —
  dışa-dönük deploy fiilleri artık araç seviyesinde onaya takılır (yalnız LLM davranışına değil).

### Düzeltildi
- **Auto-rollback çelişkisi:** `vps-deploy` geri dönüşü `rm -rf` yerine atomik `rsync --delete` kullanır;
  böylece `guard-bash` (yerel `rm -rf` bloğu) otomatik geri dönüşü engellemez (yerel rm -rf koruması sürer).

### Değişti
- `privacy-agent` ve `privacy-compliance`: KVKK (kvkk.gov.tr) ve GDPR (gdpr-info.eu) resmi kaynakları
  otoriter referans olarak eklendi; kural yorumu her zaman bu kanallara göre, dayanılan madde bulguda belirtilir.
- **Skill sahipliği netleştirildi:** domain skilleri owning uzman ajanlara açıkça bağlandı (backend-expert →
  api-design/observability/performance/dependency-audit/i18n-integrity; frontend-expert → a11y/i18n/observability/
  performance/dependency-audit; security-expert → red-team; review-agent → docs-writer; planner → adr;
  commit-agent → release; session-manager → token-budget). `i18n-integrity` **core** yapıldı (backend de
  kullanıcıya görünen metin üretir). Yalnız hook/ops skilleri (trace-scan, ci-pipeline, vps-deploy,
  incident-runbook) bilinçli olarak orkestrasyon-sahipli kaldı.

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
