---
name: a11y
description: |
  Frontend erişilebilirlik denetimi (WCAG): semantik HTML, klavye erişimi, odak yönetimi,
  kontrast, ARIA, ekran okuyucu. Arayüzü herkes için kullanılabilir yapar; regresyonu yakalar.
  Trigger phrases: "a11y", "erişilebilirlik", "accessibility", "WCAG", "ekran okuyucu", "klavye navigasyonu", "kontrast", "ARIA"
---

# Erişilebilirlik (a11y)

Amaç: arayüzü klavye, ekran okuyucu ve düşük görüş dahil **herkesin** kullanabilmesi. Hedef temel: **WCAG 2.1 AA**.
Yığın-bağımsız (web/React/RN); framework'e özel API için gerektiğinde web araması yap.

## Kontrol listesi
- [ ] **Semantik HTML**: `button`/`a`/`nav`/`main`/`h1..h6` doğru; `div`-buton yok
- [ ] **Klavye**: tüm etkileşim Tab ile erişilebilir, mantıklı sıra, görünür **odak halkası**
- [ ] **Odak yönetimi**: modal/route değişince odak taşınır, tuzak (focus trap) doğru
- [ ] **Kontrast**: metin ≥ 4.5:1, büyük metin ≥ 3:1
- [ ] **Alternatif metin**: anlamlı görselde `alt`; dekoratif görsel `alt=""`
- [ ] **Form**: her input'un `label`'ı var; hata mesajı programatik bağlı (`aria-describedby`)
- [ ] **ARIA**: yalnız gerekince; yanlış ARIA hiç-ARIA'dan kötü; rol/isim/durum doğru
- [ ] **Hareket/animasyon**: `prefers-reduced-motion` saygısı
- [ ] **Dil**: `<html lang>` doğru (i18n ile koordine)

## Nasıl
1. **Semantikle başla** — doğru element %80'i çözer. `role="button"`+`div` yerine `button`.
2. **Klavizle gez** — fareyi bırak, Tab/Shift-Tab/Enter/Escape ile tüm akışı dene; odak görünür ve sırası mantıklı mı.
3. **İsimlendirme** — her etkileşimli öğenin erişilebilir adı var mı (görsel-yalnız ikon butonlara `aria-label`).
4. **Kontrast** — renk çiftlerini oranla; yalnız renge bağlı anlam verme (ikon/metin ekle).
5. **Dinamik içerik** — canlı bölge (`aria-live`) ile ekran okuyucuya bildir; modal odağı yönet.
6. **Otomatik + manuel** — linter/axe gibi araçlar taban; ama klavye+okuyucu manuel testi şart (araçlar %100 yakalamaz).

## React / RN notu
- Web React: JSX'te semantik element + `htmlFor`/`aria-*`; tıklanabilir `div` yerine `button`.
- React Native: `accessible`, `accessibilityLabel`, `accessibilityRole`, `accessibilityState` (`frontend-rn-expo` ile koordine).

## Değişmez kurallar
1. **Semantik önce, ARIA sonra** — yanlış ARIA zarar verir.
2. **Klavyeyle tam kullanılabilir** olmalı — fare olmadan.
3. **Renk tek anlam taşıyıcı olamaz.**
4. **Otomatik araç yeterli değil** — manuel klavye+okuyucu testi.
5. **Mevcut tasarım sistemine uy** — bileşen kütüphanesi varsa erişilebilir kalıbını sürdür.
