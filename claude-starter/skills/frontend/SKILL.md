---
name: frontend
description: |
  Yığın-bağımsız frontend disiplini (web · mobil · masaüstü): component/view yapısı, state,
  veri çekme, durum-tam UI (loading/empty/error), i18n, erişilebilirlik, performans.
  frontend-expert-cck bunu HER yığında uygular; stack-özel ayrıntı ilgili proje skill'inde.
  Trigger phrases: "frontend", "ekran", "component", "sayfa", "UI", "state yönetimi", "arayüz"
---

# Frontend Disiplini (yığın-bağımsız)

Web (React/Next/Vue/Svelte/Angular), mobil (React Native/Flutter) veya masaüstü — ortak ilkeler.
Yığına özgü "nasıl" (native köprü, router seçimi vb.) ilgili proje skill'inde; bu skill hepsinde geçerli.

## Mimari
- **Sunum / mantık ayrımı:** component/view saf ve ince; iş mantığı hook/composable/service katmanında.
- **Yeniden kullanılabilirlik:** tekrar eden UI parçalanır; prop sözleşmesi net ve tiplenmiş.
- **Klasör:** özellik-bazlı (`features/<ad>/`) — view, mantık, test bir arada.

## State & veri
- **Yerel state önce** (`useState`/signal); global gerekirse projenin seçimi (store/context) — dayatma yok.
- **Veri çekme:** cache + hata + yükleniyor durumları düşünülür; yarış/iptal (race/abort) gözetilir.

## Durum-tam UI (baştan tasarla)
Her veri-bağlı görünüm **dört durumu** karşılar: **loading · empty · error · dolu**.
Sadece "dolu"yu kodlama; boş/hata/yükleniyor deneyimin parçası.

## i18n & erişilebilirlik (varsayılan, süs değil)
- Kullanıcıya görünen metin dil dosyasından (proje dilleri); sabit-kodlu string yok (`i18n-integrity`).
- Anlamlı etiket/rol, yeterli kontrast, klavye/ekran-okuyucu erişimi, uygun dokunma/tıklama hedefi.

## Responsive & performans
- Hedef ekran/cihaz matrisinde çalışır (responsive/uyarlanabilir).
- Gereksiz render (memo/callback), bundle boyutu, lazy yükleme, uzun listelerde sanallaştırma.

## DoD (bu skill'in katkısı)
- `/simplify`; ölü stil/kullanılmayan prop yok.
- Dört durum karşılanmış; `i18n-integrity` temiz; erişilebilirlik temel matriste geçer.
- `review-agent-cck` temiz.

## Kısıtlar
- Cerrahi değişiklik; mevcut konvansiyona uy, yığın/tercih dayatma.
- Platformun vermediği veriyi varmış gibi gösterme; olmayan yeteneği vaat etme.
- §4 geçerli: kod/yorum/string'de yapay zeka izi ve vendor şablon adı yok.
