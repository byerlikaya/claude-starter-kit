---
name: adr
description: |
  Mimari Karar Kaydı (ADR): geri-alması pahalı/kalıcı kararları bağlam-karar-sonuç formatında
  belgeler. Kalıcı mimari kararda çalışır; docs/adr/ altına yazılır.
  Trigger phrases: "adr", "mimari karar", "karar kaydı", "neden bu yaklaşım", "architecture decision"
---

# Mimari Karar Kaydı (ADR)

## Ne zaman
Geri dönüşü pahalı, uzun ömürlü ya da tartışmalı bir mimari/teknoloji seçiminde
(veritabanı seçimi, auth stratejisi, kritik kalıp). Küçük/geri-alınabilir kararlar ADR gerektirmez.

## Format (docs/adr/NNNN-kisa-baslik.md, ~1 sayfa)
```
# NNNN. <Karar başlığı>
Durum: öneri | kabul edildi | reddedildi | değiştirildi (NNNN yerine)
## Bağlam
Hangi problem/kısıt bu kararı gerektiriyor?
## Karar
Ne yapmaya karar verildi (net, tek cümle + gerekçe)?
## Sonuçlar
Artılar / eksiler / kabul edilen ödünler.
## Değerlendirilen alternatifler
Neden seçilmediler?
```

## İlkeler
- **Değişmez:** yeni karar eski ADR'yi `superseded` yapar; ADR **silinmez** (karar tarihçesi korunur).
- Numaralı ve tarihli; kısa tut.

## DoD
- Karar + gerekçe + reddedilen alternatifler kayıtlı; durum güncel.
