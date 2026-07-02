---
name: frontend-rn-expo
description: |
  OPSİYONEL, stack-özel: React Native + Expo (prebuild) ayrıntıları. Yalnız mobil RN projelerinde
  kullanılır; jenerik ilkeler `frontend` skill'inde. Web/masaüstü projede bu skill devre dışıdır.
  Trigger phrases: "expo", "react native", "native köprü", "expo router", "rn ekran", "prebuild"
---

# React Native + Expo (stack-özel katman)

Jenerik frontend disiplini için **`frontend`** skill'ini izle; bu dosya yalnız RN+Expo'ya özgü ekler.
Web/masaüstü projede kullanılmaz (gerekirse sil).

## RN + Expo'ya özgü
- **Navigation:** expo-router (dosya-bazlı) veya react-navigation — projede hangisi varsa onu izle.
- **Liste:** `FlatList`/`FlashList` + `keyExtractor`; ağır listede sanallaştırma.
- **Native köprü:** yalnız gerektiğinde; JS tarafı **tiplenmiş**, hata yolları açık (native reddederse UI ne yapar).
  Expo prebuild / config plugin ile; platform farkını (iOS/Android) gözet.
- **Capability'ye göre render:** cihazda olmayan yeteneği UI'da **vaat etme**; koşullu göster.
- **Varlıklar:** görsel boyut/çözünürlük, `expo-image` cache, splash/icon prebuild uyumu.

## DoD (jenerik `frontend` DoD'una ek)
- Hedef iOS/Android sürüm matrisinde çalışır; native köprü hata yolları test edilmiş.
