---
name: docs-writer
description: |
  Dokümantasyonu koda eşzamanlı tutar: public API/davranış değişince README, kullanım ve
  ilgili dokümanı günceller. Doğru, minimal, güncel belge; ölü/yanıltıcı doküman bırakmaz.
  Trigger phrases: "dokümantasyon", "docs", "README güncelle", "API dokümanı", "belge yaz", "dokümante et", "kullanım yaz"
---

# Dokümantasyon

Amaç: dokümanın **koda uyması**. Yanlış/eski doküman, dokümansızlıktan kötüdür (güven verir, yanıltır).
Tetik: public bir API, komut, yapılandırma veya kullanıcıya görünen davranış değiştiğinde.

## Ne zaman zorunlu
- Public fonksiyon/endpoint/CLI imzası veya davranışı değişti.
- Yeni özellik, yapılandırma anahtarı veya ortam değişkeni eklendi.
- Kurulum/çalıştırma adımları değişti.
- Kırıcı değişiklik yapıldı (ayrıca `release`/CHANGELOG ile koordine).

## Kontrol listesi
- [ ] Değişen public yüzey için doküman güncel
- [ ] Örnekler **çalışır** (kopyala-yapıştır test edildi/zihinsel izlendi)
- [ ] Ölü/yanıltıcı ifade kaldırıldı (eski isim/parametre kalmadı)
- [ ] Yeni yapılandırma/env belgelendi (varsayılan + zorunluluk)
- [ ] Kapsam minimal — kodun tekrarı değil, "neden/nasıl kullanılır"
- [ ] Dokümanda secret/gerçek kimlik yok (placeholder)

## Nasıl
1. **Değişen yüzeyi belirle** — diff'ten public imza/davranış farkını çıkar.
2. **Doğru dokümanı bul** — README, `docs/`, docstring, OpenAPI, komut `--help`. Birden çoksa hepsini güncelle.
3. **Yaz**: ne yapar · nasıl çağrılır (örnek) · girdi/çıktı · sınır/hata durumu. Kısa ve doğru.
4. **Örnekleri doğrula** — komut/kod örneği gerçekten çalışır mı.
5. **Eskiyi temizle** — kaldırılan API/parametre referanslarını sil.
6. **Çeviri**: kullanıcıya görünen doküman çok dilliyse `i18n-integrity` ile koordine.

## İlkeler
- **Kaynak tek** — davranış kodda; doküman onu *açıklar*, kopyalamaz (kopyalanan doküman eskir).
- **Örnek > paragraf** — çalışan bir örnek, üç paragraftan iyi.
- **Minimal** — bakılmayacak devasa doküman yazma; en çok sorulan soruyu yanıtla.

## Değişmez kurallar
1. **Doğruluk > eksiksizlik** — yanlış doküman yazma; emin değilsen işaretle/sor.
2. **Örnekler çalışır olmalı.**
3. **Eski/ölü doküman bırakma.**
4. **Secret/gerçek kimlik yok** — placeholder kullan (§4 ile uyumlu).
5. **Kod tekrarı yapma** — imzayı kopyalayıp durma; kullanımı anlat.
