---
name: frontend-rn-expo
description: |
  OPTIONAL, stack-specific: React Native + Expo (prebuild). Mobile RN projects only; the generic principles
  live in the `frontend` skill.
  Trigger phrases: "expo", "react native", "native bridge", "expo router", "rn screen", "prebuild"
---

# React Native + Expo (stack-specific layer)

For generic frontend discipline, applies the `frontend` skill; this file only covers the RN+Expo-specific additions.
Not used in web/desktop projects (delete it if needed).

## RN + Expo specifics
- **Navigation:** expo-router (file-based) or react-navigation — follow whichever the project uses.
- **Lists:** `FlatList`/`FlashList` + `keyExtractor`; virtualization for heavy lists.
- **Native bridge:** only when needed; the JS side is **typed**, error paths are explicit (what the UI does if native rejects).
  Via Expo prebuild / config plugin; mind the platform difference (iOS/Android).
- **Render by capability:** do **not** promise in the UI a capability the device lacks; show it conditionally.
- **Assets:** image size/resolution, `expo-image` cache, splash/icon prebuild compatibility.

## DoD (in addition to the generic `frontend` DoD)
- Works across the target iOS/Android version matrix; native bridge error paths are tested.
