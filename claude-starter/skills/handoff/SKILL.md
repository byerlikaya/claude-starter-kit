---
name: handoff
description: |
  Oturum devir özeti: context dolunca / faz kapanınca / konu değişince docs/SESSION_STATE.md'ye
  eyleme-dönük devir yazar, sonra /clear önerir. session-manager-cck tetikler.
  Trigger phrases: "handoff", "devir", "oturum özeti", "session state", "context temizle", "devam edeceğim"
---

# Oturum Devri (Handoff)

## Ne zaman
`/context` > %75 · faz kapanışı · konu değişimi. Amaç: sonraki oturum **sıfırdan başlamasın**.

## Çıktı (docs/SESSION_STATE.md, lokal)
```
# Oturum Devri — <tarih>
## Yapıldı
- <tamamlanan iş + hangi dosyalar>
## Devam eden
- <yarım kalan + tam olarak nerede kalındı>
## Sıradaki adım
- <net, tek yüksek-değerli adım>
## Açık kararlar
- <bekleyen karar + seçenekler>
## Dosya işaretçileri
- docs/PLAN.md, ilgili modüller...
## Bloklar / riskler
- <varsa>
```

## İlkeler
- **Eyleme dönük:** "ne yapıldı" değil "şimdi tam olarak nereden devam" odaklı.
- Karar gerekçelerini koru (neden bu yol seçildi) — bağlam kaybolmasın.
- Yazıldıktan sonra `/clear` ile taze oturum.

## DoD
- Devir dosyası; yeni oturum yalnız bu dosyayı okuyup kaldığı yerden devam edebilir.
