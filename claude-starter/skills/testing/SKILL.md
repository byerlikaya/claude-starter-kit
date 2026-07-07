---
name: testing
description: |
  Test "nasıl"ı: piramit, AAA, izolasyon, risk-kapsamı, deterministiklik; "testler yeşil"
  garantisini sağlar. test-expert-cck bunu uygular.
  Trigger phrases: "test yaz", "test çalıştır", "coverage", "testler yeşil mi", "unit test", "integration test"
---

# Test Disiplini

Amaç: **davranış doğruluğu** — testi geçirmek için ürün kodunu bozmadan, gerçek davranışı test et.

## İlkeler
- **Piramit:** çok birim, orta entegrasyon, az uçtan-uca (e2e). e2e'yi kritik akışla sınırla.
- **AAA:** Arrange-Act-Assert; **tek test = tek davranış**.
- **İzolasyon & deterministiklik:** harici bağımlılık mock/fake; zaman ve rastgelelik sabitlenir; test sırası bağımsız.
- **Risk-kapsamı:** metrik değil risk. Kritik yol + **sınır** + **negatif** + **yetki (IDOR/404)** senaryoları.
- **İsimlendirme:** `neyi_test_ediyor_hangi_durumda_ne_bekliyor` — hata anında ne kırıldığı açık.
- **Kırmızı-yeşil:** önce başarısız test, sonra implementasyon.

## Dikkat
- **Flaky = bug:** ara sıra kırılan test tolere edilmez, kökten çözülür.
- Snapshot/altın-dosya testinde gereksiz kırılganlıktan kaçın (yalnız anlamlı çıktıyı doğrula).

## DoD (bu skill'in katkısı)
- İlgili test komutu yeşil (örn. `dotnet test`); kritik yollar kapsandı; boş/anlamsız test yok.
