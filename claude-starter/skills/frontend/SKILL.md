---
name: frontend
description: |
  Stack-agnostic frontend discipline (web · mobile · desktop): component structure, state, data fetching,
  loading/empty/error states, i18n, accessibility, performance. frontend-expert-csk applies it on every stack.
  Trigger phrases: "frontend", "screen", "component", "page", "UI", "state management", "interface"
---

# Frontend Discipline (stack-agnostic)

Web (React/Next/Vue/Svelte/Angular), mobile (React Native/Flutter) or desktop — shared principles.
The stack-specific "how" (native bridge, router choice, etc.) lives in the relevant project skill; this skill applies to all of them.

## Architecture
- **Presentation / logic separation:** component/view is pure and thin; business logic lives in the hook/composable/service layer.
- **Reusability:** repeated UI is factored out; the prop contract is clear and typed.
- **Folder:** feature-based (`features/<name>/`) — view, logic, and test together.

## State & data
- **Local state first** (`useState`/signal); if global is needed, the project's choice (store/context) — nothing imposed.
- **Data fetching:** cache + error + loading states are considered; race/abort are handled.

## State-complete UI (design it from the start)
Every data-bound view covers **four states**: **loading · empty · error · full**.
Don't code only the "full" case; empty/error/loading are part of the experience.

## i18n & accessibility (default, not decoration)
- User-visible text comes from the language file (project languages); no hard-coded strings (`i18n-integrity`).
- Meaningful labels/roles, sufficient contrast, keyboard/screen-reader access, appropriate touch/click target.

## Visual & UX quality
This skill covers *structure*; the **visual/UX design layer** — hierarchy, spacing rhythm, typographic scale, a
restrained color system, and polished states — lives in **`frontend-design`**. Apply it when the work is about how the
interface *looks and feels*, not just how it's wired.

## Responsive & performance
- Works across the target screen/device matrix (responsive/adaptive).
- Unnecessary renders (memo/callback), bundle size, lazy loading, virtualization for long lists.

## Verify at runtime (contract)
Prove a change works by **observing the running UI**, structured — not by interpreting a screenshot. Have components
emit `data-verify-*` state attributes, register verifiable units with fixtures + invariants (≥1 adversarial `probe`
each), expose `window.__verify`, and adopt the `PASS/FAIL/BLOCKED/SKIP` taxonomy (when in doubt, FAIL). Then drive
the browser to check it. The full convention: **`references/verify-contract.md`**.

## DoD (this skill's contribution)
- `/simplify`; no dead styles/unused props.
- The four states are covered; `i18n-integrity` clean; accessibility passes the baseline matrix.
- `review-agent-csk` clean.

## Constraints
- Surgical change; follow existing conventions, do not impose a stack/preference.
- Do not present data the platform does not provide as if it existed; do not promise a capability that isn't there.
- §4 applies: no AI trace or vendor template name in code/comments/strings.
