---
name: dependency-audit
description: |
  Bağımlılık denetimi: bilinen zafiyet (CVE), lisans uyumu, terk edilmiş/eski paket, lockfile
  bütünlüğü, yeni bağımlılık gerekçesi. Paket ekleme/güncelleme/lockfile değişiminde çalışır.
  Trigger phrases: "bağımlılık", "dependency audit", "npm audit", "paket güvenliği", "CVE", "lisans"
---

# Bağımlılık Denetimi

## Denetim eksenleri
1. **Bilinen zafiyet (CVE):** ekosisteme uygun denetim
   ```bash
   npm audit --production           # Node
   dotnet list package --vulnerable # .NET
   pip-audit                        # Python
   ```
2. **Lisans uyumu:** kopyasol/GPL gibi projeyle uyumsuz lisansları işaretle (ticari kapalı kaynakta risk).
3. **Bakım durumu:** terk edilmiş / uzun süredir güncellenmemiş / tek-bakımcı paketleri not et.
4. **Transitive bağımlılık:** dolaylı bağımlılıklardaki zafiyetleri de tara.
5. **Lockfile bütünlüğü:** lockfile commit'li ve manifest ile tutarlı; sürümler pinli.
6. **Yeni bağımlılık gerekçesi:** gerçekten gerekli mi? Tek küçük fonksiyon için ağır paket ekleme (supply-chain yüzeyi).

## Çıktı
Severity-sıralı liste: `paket · sürüm · sorun (CVE/lisans/bakım) · yükseltme yolu`.

## DoD
- 0 bilinen HIGH/CRITICAL zafiyet; lisanslar uyumlu; lockfile tutarlı; her yeni paket gerekçeli.
