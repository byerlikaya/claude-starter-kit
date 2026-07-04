---
name: api-design
description: |
  API sözleşmesi tasarımı: tutarlı kaynak/adlandırma, hata modeli, sürümleme, sayfalama,
  geriye-uyum ve OpenAPI. Tüketiciyi kırmadan evrilen, tahmin edilebilir arayüz üretir.
  Trigger phrases: "api tasarımı", "api design", "api sözleşmesi", "api versiyonlama", "openapi", "swagger", "rest sözleşmesi", "kırıcı api değişikliği"
---

# API Tasarımı

Amaç: tüketicinin **tahmin edebileceği**, kırılmadan **evrilebilen** bir sözleşme. Bir kez yayınlanan
public API bir taahhüttür; kırıcı değişiklik pahalıdır. Yığın-bağımsız (REST temel; GraphQL/gRPC benzer ilkeler).

## Kontrol listesi
- [ ] Kaynak adları **tutarlı** (çoğul isim, `kebab`/`camel` tek stil), fiil değil kaynak
- [ ] HTTP semantiği doğru: GET (yan etkisiz) · POST · PUT/PATCH · DELETE; doğru **durum kodu**
- [ ] **Hata modeli** tek tip: makine-okunur kod + insan mesajı + (varsa) alan detayları
- [ ] **Sürümleme** stratejisi belli (URL `/v1` veya header); kırıcı değişiklik yeni sürüm
- [ ] **Sayfalama/filtre/sıralama** büyük koleksiyonlarda tanımlı ve tutarlı
- [ ] **Geriye-uyum**: alan ekleme additive; alan silme/anlam değiştirme kırıcı → sürüm
- [ ] **İdempotency** (POST/ödeme gibi) gerekiyorsa anahtar destekli
- [ ] Sözleşme **OpenAPI**'de belgeli; örnek istek/yanıt var (`docs-writer` ile koordine)

## Nasıl
1. **Kaynağı modelle** — fiil değil isim: `POST /orders` (✓), `POST /createOrder` (✗).
2. **Durum kodları**: 200/201/204 · 400 doğrulama · 401/403 yetki · 404 · 409 çakışma · 422 · 429 · 5xx. Anlamlı kullan.
3. **Hata sözleşmesi** — her hata aynı şekil:
   ```json
   { "code": "ORDER_NOT_FOUND", "message": "Sipariş bulunamadı", "details": [] }
   ```
   Stack trace / iç detay sızdırma (`security-scan` ile örtüşür).
4. **Sürümleme**: additive değişiklik aynı sürümde; kırıcı (alan sil/yeniden adlandır/zorunlu alan ekle) → `/v2`.
5. **Koleksiyon**: sayfalama (cursor veya offset), filtre/sıralama parametreleri; tutarlı zarf.
6. **Sözleşmeyi yaz** — OpenAPI/şema; örneklerle. Değişikliği `docs-writer`'a, kırıcıysa `release`/CHANGELOG'a bağla.

## Kırıcı vs additive
| Additive (güvenli) | Kırıcı (sürüm ister) |
|---|---|
| Opsiyonel alan/endpoint ekle | Alan sil / yeniden adlandır |
| Yeni opsiyonel parametre | Zorunlu parametre ekle |
| Yeni enum değeri (tüketici toleranslıysa) | Tip/anlam değiştir, durum kodu değiştir |

## Değişmez kurallar
1. **Public API bir taahhüt** — kırıcı değişiklik sessizce yapılmaz; sürüm + duyuru.
2. **Tutarlılık > yerel zeka** — tek adlandırma/hata/sayfalama kalıbı tüm API'de.
3. **Hata modeli tek tip ve makine-okunur.**
4. **İç detay sızdırma** — stack trace / DB hatası tüketiciye gitmez.
5. **Sözleşme belgeli** — OpenAPI + örnek; koddan sonra değil, tasarımda.
