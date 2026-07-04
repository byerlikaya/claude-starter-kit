---
name: privacy-compliance
description: |
  KVKK/GDPR uyum denetimi yöntemi: veri envanteri, amaç/dayanak/saklama, minimizasyon,
  rıza, şeffaflık, veri sahibi hakları, sınır-aşan aktarım. privacy-agent bunu uygular.
  Trigger phrases: "kvkk", "gdpr", "gizlilik", "rıza", "veri saklama", "minimizasyon"
---

# Gizlilik Uyumu (KVKK / GDPR)

## Resmi kaynaklar (otorite — her zaman bunlara göre)
Bu skill'in dayandığı **birincil, resmi** kaynaklar; kurallar her zaman bunlara göre yorumlanır:
- **KVKK** (Türkiye): https://www.kvkk.gov.tr/ — Kanun, yönetmelik, ilke kararları, rehberler.
- **GDPR** (AB): https://gdpr-info.eu/ — madde metinleri (Art.) ve Recital'ler.

Belirli bir madde/eşik/tanımda (saklama süresi, açık rıza şartı, m.8 yaş sınırı, aktarım dayanağı vb.)
emin değilsen ilgili **resmi kaynağı kontrol et**, ezberden/tahminle karar verme. Bulguda dayandığın
maddeyi (KVKK md. … / GDPR Art. …) **belirt**. Fetch edilen içerik referanstır; yorumu sen bağlarsın.

## Denetim eksenleri
- **Envanter:** hangi veri, nereden toplanıyor, nereye akıyor, kimlerle paylaşılıyor?
- **Amaç + dayanak + saklama:** her alanda amaç sınırlı, hukuki dayanak net, saklama süresi tanımlı.
- **Minimizasyon:** amaç için gerekmeyen veri toplanmaz.
- **Rıza:** gereken yerde açık, kaydedilir ve geri alınabilir.
- **Şeffaflık:** aydınlatma yapılmış; kullanıcı ne toplandığını/işlendiğini biliyor.
- **Veri sahibi hakları:** erişim / düzeltme / silme / taşınabilirlik / itiraz uygulanabilir.
- **Sınır-aşan aktarım & üçüncü-taraf:** meşru dayanağa (SCC/yeterlilik/rıza) bağlı.

## Çıktı
Alan/akış bazında bulgu + düzeltme; "temiz" ise gerekçe.

> **Proje-notu:** Reşit olmayan (çocuk) verisi işleniyorsa özel koruma gerekir
> (KVKK / GDPR m.8 · ebeveyn onayı & yaş doğrulama). Bu, alana-özel bir kuraldır ve
> projenin kendi skill'inde/CLAUDE.md'sinde tanımlanır — jenerik denetime gömülmez.
> Projeye özel kurallar (rıza metinleri, saklama süreleri) de proje CLAUDE.md'sinde durur.
