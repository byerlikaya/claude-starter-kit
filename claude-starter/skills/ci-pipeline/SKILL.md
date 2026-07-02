---
name: ci-pipeline
description: |
  CI ardışık düzeni disiplini: lint→build→test→kalite→güvenlik aşamaları, fail-fast,
  deterministik build, sır yönetimi, PR kapıları. CI yapılandırması değişince çalışır.
  Trigger phrases: "ci", "pipeline", "github actions", "build hattı", "pr kapısı", "workflow"
---

# CI Ardışık Düzeni

## Aşamalar (fail-fast — erken patlarsa dur)
1. **Lint / format** — stil ve statik analiz
2. **Build** — 0 uyarı/0 hata
3. **Test** — birim + entegrasyon, coverage toplanır
4. **Kalite** — `sonarqube-check` Quality Gate
5. **Güvenlik** — `dependency-audit` + `security-scan` (uygunsa)
6. **Artefakt / paketleme** — (deploy ayrı, `vps-deploy`)

## İlkeler
- **Deterministik:** bağımlılıklar pinli, cache doğru anahtarlanmış; "bende çalışıyordu" yok.
- **Sır yönetimi:** CI secret store; repoda/loglarda düz metin sır YOK (trace-scan ile örtüşür).
- **PR kapısı:** quality gate + testler zorunlu geçer; kırmızı merge edilmez.
- **Branch koruması:** doğrudan main'e push kapalı; PR + review zorunlu.

## DoD
- Tüm aşamalar yeşil; PR kapıları zorunlu; sır sızıntısı yok; build tekrarlanabilir.
