---
name: sonarqube-check
description: |
  SonarQube kalite kapısı (dil-bağımsız): 0 Bug · 0 Vulnerability · 0 Security Hotspot · 0 Code Smell,
  build 0 uyarı/0 hata. SonarQube kullanan projelerde (Java · JS/TS · Python · Go · C# · PHP …) test/güvenlik sonrası çalışır.
  Trigger phrases: "sonarqube", "kalite kapısı", "quality gate", "code smell", "sonar tara"
---

# SonarQube Kalite Kapısı (dil-bağımsız)

Sıfır-tolerans kapısı: bir iş, aşağıdaki metrikler temiz olmadan kapanmaz. SonarQube 30'dan çok dili
analiz eder; kapı hangi dilde olursa olsun aynıdır — yalnız çalıştıran **scanner** yığına göre değişir.

## Kapı (hepsi zorunlu)
- **0 Bug · 0 Vulnerability · 0 Security Hotspot · 0 Code Smell**
- Build **0 uyarı / 0 hata**
- Coverage projenin tanımladığı eşiğin üstünde (yeni kodda özellikle)

## Çalıştırma (yığına göre scanner)
Önce projenin build sistemini tespit et, uygun scanner'ı seç:

- **Jenerik (JS/TS · Python · Go · PHP …)** — SonarScanner CLI + `sonar-project.properties`:
  ```bash
  sonar-scanner -Dsonar.host.url="<url>" -Dsonar.token="$SONAR_TOKEN"
  ```
- **.NET** — MSBuild entegrasyonu gerektiğinden özel scanner:
  ```bash
  dotnet sonarscanner begin /k:"<proje>" /d:sonar.host.url="<url>" /d:sonar.cs.opencover.reportsPaths="**/coverage.opencover.xml"
  dotnet build --no-incremental
  dotnet test --collect:"XPlat Code Coverage"
  dotnet sonarscanner end
  ```
- **Maven** — `mvn verify sonar:sonar` · **Gradle** — `gradle sonar` (SonarQube eklentisi).

Coverage raporunu dile göre üret (JS: lcov · Python: coverage.xml · Go: coverage.out · .NET: opencover) ve
ilgili `sonar.*.reportPaths` anahtarıyla bağla.

## İlkeler
- **Clean as You Code:** yeni/değişen kodda kapı sıfır; eski borç ayrı ele alınır ama yeni borç eklenmez.
- **Security Hotspot yok sayılmaz:** her biri incelenip "safe" gerekçesiyle işaretlenir ya da düzeltilir.
- Bulgu → ilgili uzman düzeltir; **erteleme yok**, "sonra bakarız" yok.

## DoD
- Quality Gate PASSED; PR/merge öncesi yeşil.
