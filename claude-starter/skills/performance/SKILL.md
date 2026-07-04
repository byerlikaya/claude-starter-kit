---
name: performance
description: |
  Yığın-bağımsız performans disiplini: önce ölç, darboğazı bul, sonra optimize et. N+1, gereksiz
  allocation, yanlış async sınırı, eksik index/cache, ağır payload. Erken optimizasyondan kaçınır.
  Trigger phrases: "performans", "performance", "yavaş", "optimizasyon", "profiling", "N+1", "gecikme", "bellek sızıntısı", "load test"
---

# Performans

Temel kural: **önce ölç, sonra optimize et.** Ölçmeden yapılan optimizasyon tahmindir; genelde yanlış yeri
hızlandırıp karmaşıklık ekler. Yığın-bağımsız; profil aracı/kütüphane için gerektiğinde web araması yap.

## Yöntem (sırayla)
1. **Hedef koy** — "kabul edilebilir" nedir? (p95 gecikme, throughput, bellek tavanı). Sayısal.
2. **Ölç** — profiler/APM/benchmark ile gerçek darboğazı bul; tahminle başlama.
3. **En pahalı tek şeyi düzelt** — Amdahl: %5'lik yolu 2x hızlandırmak boşa; sıcak yolu hedefle.
4. **Yeniden ölç** — gerçekten iyileşti mi, regresyon var mı.
5. **Dur** — hedefe ulaştıysan bitir; sonsuz mikro-optimizasyon yapma.

## Sık darboğazlar
| Alan | Kalıp | Çözüm |
|---|---|---|
| **DB** | N+1 sorgu, eksik index, `SELECT *`, tablo taraması | eager/batch yükleme, index (db-migration), gerekli kolon |
| **Bellek** | gereksiz allocation, büyük nesne tutma, sızıntı | havuzlama, stream, referans bırakma |
| **Async** | yanlış sync/async sınırı, bloklayan I/O, seri await | paralel await, non-blocking I/O |
| **Ağ/payload** | aşırı büyük yanıt, sıkıştırma yok, chatty API | sayfalama, alan seçimi, gzip, batch (api-design) |
| **Cache** | tekrarlanan pahalı hesap, cache yok/yanlış | uygun katmanda cache + doğru invalidation |
| **Frontend** | gereksiz render, büyük bundle, bloklayan kaynak | memo, code-split, lazy, kritik CSS |

## Ölçüm ipuçları
- **Yük altında** ölç (tek istek yanıltır); gerçekçi veri hacmiyle.
- **p50 değil p95/p99** — kuyruk gecikmesi kullanıcıyı yakar.
- Mikro-benchmark'a güvenme; uçtan uca profil daha dürüst.

## Değişmez kurallar
1. **Ölçmeden optimize etme** — profil olmadan değişiklik = tahmin.
2. **Sıcak yolu hedefle** — küçük payı hızlandırma.
3. **Doğruluğu bozma** — hız için davranış/kenar durumu feda etme.
4. **Karmaşıklık bütçesi** — okunabilirliği ciddi düşüren optimizasyonu ancak ölçülü kazanç varsa yap; yorumla.
5. **Hedefe ulaşınca dur** — YAGNI; erken/aşırı optimizasyon yok.
