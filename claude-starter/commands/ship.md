---
name: ship
description: DoD kapısı + commit önerisi (onay bekler).
---
# /ship
Kapanış akışı — sırayla:
1. **DoD kapısı:** `/simplify` uygulandı mı · testler yeşil mi (test-expert-cck) · (.NET'te) `sonarqube-check` 0/0/0/0.
   Biri kırmızıysa **DUR**, neyin eksik olduğunu bildir; erteleme yok.
2. Temizse **commit-agent-cck** (commit-message) staged diff'ten atomik Conventional Commit **önerir**.
3. Commit YALNIZ kullanıcı "commit et" derse çalışır (§4.4). "Tamamlandı" onay değildir.

Destrüktif işlem yok (§4.5). Mesajda yapay zeka izi / vendor adı yok (§4.1/§4.2 — hook zaten tarar).
