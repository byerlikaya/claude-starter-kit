---
name: review
description: Denetim geçişi — review + güvenlik + kalite kapıları.
---
# /review
Değişiklik setini denetim üçlüsünden geçir (salt-okunur):
1. **review-agent** (code-review) — "genel kod-sağlığını iyileştiriyor mu"; önem-sıralı yorum.
2. **security-expert** (security-scan) — auth/IDOR/injection/secret; severity'li bulgu.
3. (.NET'te) **sonarqube-check** — 0/0/0/0 kapısı.

Her ajan ana thread'e **kısa özet** döner; ham çıktı gerekiyorsa `docs/`'a. Kod DEĞİŞTİRME;
bulguları önem sırasıyla topla, düzeltmeyi ilgili uzmana bırak.
