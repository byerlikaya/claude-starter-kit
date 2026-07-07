---
name: review
description: Denetim geçişi — review + güvenlik + kalite kapıları.
---
# /review
Değişiklik setini denetim üçlüsünden geçir (salt-okunur):
1. **review-agent-cck** (code-review) — "genel kod-sağlığını iyileştiriyor mu"; önem-sıralı yorum.
2. **security-expert-cck** (security-scan) — auth/IDOR/injection/secret; severity'li bulgu.
3. (SonarQube kullanılıyorsa) **sonarqube-check** — 0/0/0/0 kapısı (dil-bağımsız).

Her ajan ana thread'e **kısa özet** döner; ham çıktı gerekiyorsa `docs/`'a. Kod DEĞİŞTİRME;
bulguları önem sırasıyla topla, düzeltmeyi ilgili uzmana bırak.
