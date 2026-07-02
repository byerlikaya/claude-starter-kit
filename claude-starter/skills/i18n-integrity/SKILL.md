---
name: i18n-integrity
description: |
  Çeviri bütünlüğü denetimi: her metin anahtarı tüm proje dillerinde var mı, sabit-kodlu string
  var mı, placeholder/çoğul tutarlı mı. Kullanıcıya görünen metin değişince çalışır.
  Trigger phrases: "i18n", "çeviri", "dil dosyası", "eksik çeviri", "yerelleştirme", "translate"
---

# Çeviri Bütünlüğü (i18n)

Amaç: hiçbir dilde eksik/kırık metin kalmasın. Varsayılan diller: **TR / EN / DE / RU** (proje ayarlar).

## Denetim eksenleri
- **Anahtar eşitliği:** her anahtarın TÜM dillerde karşılığı var; eksik/fazla anahtar = bulgu.
- **Sabit-kodlu string yok:** kullanıcıya görünen metin koda gömülmez, dil dosyasından gelir.
- **Placeholder tutarlılığı:** `{name}`, `%s`, ICU `{count, plural, ...}` her dilde birebir aynı.
- **Çoğul kuralları:** dile özgü çoğul formları (özellikle RU) doğru.
- **Boş/aynı değer:** çevrilmemiş (kaynakla birebir aynı) placeholder değer işaretlenir.

## Kontrol (anahtar seti karşılaştırma)
```bash
# Örnek: JSON dil dosyalarının anahtar setlerini karşılaştır
for f in locales/*.json; do echo "== $f =="; jq -r 'keys[]' "$f" | sort > "/tmp/$(basename $f).keys"; done
diff /tmp/tr.json.keys /tmp/en.json.keys   # farklar = eksik/fazla anahtar
```

## DoD
- Tüm dillerde anahtar setleri eşit; sabit-kodlu kullanıcı metni yok; placeholder'lar tutarlı.
- **Eksik çeviri = kırmızı** (erteleme yok).
