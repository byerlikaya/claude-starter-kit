---
name: frontend-rn-expo
description: |
  OPTIONAL, stack-specific: React Native + Expo (prebuild). Mobile RN projects only; the generic principles
  live in the `frontend` skill.
---

# React Native + Expo (stack-specific layer)

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "expo", "react native", "native bridge", "expo router", "rn screen", "prebuild"

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
