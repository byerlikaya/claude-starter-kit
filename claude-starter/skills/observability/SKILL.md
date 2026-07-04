---
name: observability
description: |
  Yığın-bağımsız gözlemlenebilirlik: yapılandırılmış log, korelasyon-id, metrik ve trace ekler;
  log'da PII/secret sızıntısını engeller. Üretim sorununu "neden oldu" diye izlenebilir kılar.
  Trigger phrases: "observability", "gözlemlenebilirlik", "yapılandırılmış log", "structured logging", "trace ekle", "metrik ekle", "korelasyon id", "log ekle"
---

# Gözlemlenebilirlik

Amaç: bir üretim olayında "ne oldu, nerede, neden" sorusunu **log'a bakarak** yanıtlayabilmek.
Yığın-bağımsızdır; framework'e özel kütüphane/format için gerektiğinde web araması yap.

## Üç sinyal
- **Log** — olay kaydı (yapılandırılmış/JSON, seviyeli).
- **Metrik** — sayısal zaman serisi (istek sayısı, gecikme, hata oranı, kaynak).
- **Trace** — bir isteğin servisler arası yolculuğu (span'ler + korelasyon-id).

## Kontrol listesi
- [ ] Log **yapılandırılmış** (JSON/anahtar-değer), string interpolation değil
- [ ] Her log satırında **korelasyon-id** (request/trace id) var
- [ ] Seviyeler doğru: DEBUG/INFO/WARN/ERROR ayrımı anlamlı
- [ ] **PII/secret loglanmıyor** (parola, token, kart, TC/kimlik, e-posta gövdesi)
- [ ] Hata log'u bağlam taşıyor (girdi özeti, kullanıcı/kaynak id — PII değil), stack trace kullanıcıya sızmaz
- [ ] Kritik iş metriği + altyapı metriği yayılıyor (varsa)
- [ ] Servisler arası çağrıda korelasyon-id **taşınıyor** (header/propagation)

## Nasıl
1. **Yapılandırılmış logger** kur/kullan — çıktı makine-okunur (JSON). Framework'ün önerdiği kütüphaneyi ara.
2. **Korelasyon-id**: girişte (HTTP middleware / mesaj tüketici) üret ya da gelen `X-Request-Id`/trace header'ından al; log context'ine koy; alt çağrılara **ilet**.
3. **Seviye disiplini**: INFO = iş olayı, WARN = beklenen-ama-dikkat, ERROR = müdahale gerek. DEBUG üretimde kapalı/örneklemeli.
4. **Bağlam alanları**: `event`, `correlation_id`, `user_id`(PII değil, opak id), `duration_ms`, `outcome`. Serbest metne gömme.
5. **Metrik**: en az RED (Rate, Errors, Duration) veya USE; iş-kritik sayaçlar. Framework metrik kütüphanesini ara.
6. **Trace** (dağıtık sistemde): span başlat/bitir, korelasyon-id'yi trace-id'ye bağla.

## PII / secret sızıntısı (kritik)
Log'a **asla**: parola, token, API anahtarı, kart no, TC/kimlik, tam e-posta/telefon gövdesi, ham istek gövdesi.
- Maskele: `user@***`, kart `**** 1234`, token `sk-p…789`.
- Gerekliyse **opak id** logla (hash/uuid), ham değeri değil.
- Bu eksen `security-scan` (loglarda hassas veri) ve `privacy-compliance` (KVKK/GDPR) ile örtüşür — kişisel veri varsa onları da tetikle.

## Değişmez kurallar
1. **Yapılandırılmış > serbest metin** — grep'lenebilir, ayrıştırılabilir.
2. **Korelasyon-id her satırda** — yoksa dağıtık hata izlenemez.
3. **PII/secret loglanmaz** — maskele veya opak id.
4. **Gürültü yapma** — her satır bir soruyu yanıtlamalı; anlamsız spam log ekleme.
5. **Mevcut format'a uy** — repoda logger varsa onun kalıbını sürdür, yenisini dayatma.
