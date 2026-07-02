---
name: sonarqube-check
description: |
  SonarQube kalite kapısı: 0 Bug · 0 Vulnerability · 0 Security Hotspot · 0 Code Smell,
  build 0 uyarı/0 hata. (.NET/DevArchitecture projelerinde) security-expert/test sonrası çalışır.
  Trigger phrases: "sonarqube", "kalite kapısı", "quality gate", "code smell", "sonar tara"
---

# SonarQube Kalite Kapısı

Sıfır-tolerans kapısı: bir iş, aşağıdaki metrikler temiz olmadan kapanmaz.

## Kapı (hepsi zorunlu)
- **0 Bug · 0 Vulnerability · 0 Security Hotspot · 0 Code Smell**
- Build **0 uyarı / 0 hata**
- Coverage projenin tanımladığı eşiğin üstünde (yeni kodda özellikle)

## Çalıştırma (.NET örneği)
```bash
dotnet sonarscanner begin /k:"<proje>" /d:sonar.host.url="<url>"   /d:sonar.cs.opencover.reportsPaths="**/coverage.opencover.xml"
dotnet build --no-incremental
dotnet test --collect:"XPlat Code Coverage"
dotnet sonarscanner end
```

## İlkeler
- **Clean as You Code:** yeni/değişen kodda kapı sıfır; eski borç ayrı ele alınır ama yeni borç eklenmez.
- **Security Hotspot yok sayılmaz:** her biri incelenip "safe" gerekçesiyle işaretlenir ya da düzeltilir.
- Bulgu → ilgili uzman düzeltir (backend/db/frontend); **erteleme yok**, "sonra bakarız" yok.

## DoD
- Quality Gate PASSED; PR/merge öncesi yeşil.
