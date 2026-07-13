---
name: frontend-design
description: |
  Visual and UX design quality for interfaces: hierarchy, spacing rhythm, typographic scale, a restrained color
  system, layout composition, and polished states. The taste layer above frontend architecture and a11y.
  Trigger phrases: "visual design", "design system", "make it look good", "UI polish", "layout", "spacing", "typography"
---

# Frontend Design (visual & UX quality)

`frontend` decides how the code is structured; `a11y` decides whether everyone can use it; **this skill decides
whether it looks considered and feels right.** The through-line: **a few consistent decisions, applied everywhere,
read as "designed" — many one-off decisions read as "assembled".** Design is subtraction and rhythm, not adding flourish.

> **Kit adaptation (local, .claude/):** Stack-agnostic. **Detect and respect the project's existing design system**
> (tokens, component library, brand) — never impose a personal aesthetic or a new library. Accessibility is a floor,
> not a trade-off: apply `a11y` alongside (contrast, focus, motion). §4 Prohibitions apply.

## The six levers (order = impact; fix hierarchy before you touch color)
1. **Hierarchy** — the eye must land on the one primary thing first. Establish it with size, weight, and space — not with more color. One primary action per view; everything else is visibly secondary.
2. **Spacing & rhythm** — consistent spacing from a single scale (e.g. 4/8px steps). Group related things with *less* space, separate groups with *more*. Whitespace is the cheapest way to look premium.
3. **Typography** — one or two families, a small scale (≈4–6 steps), consistent line-height (~1.5 body). Limit weights. Measure ~45–75 chars per line. Type does most of the hierarchy work.
4. **Color** — a restrained system: 1 brand/accent, a neutral ramp, semantic states (success/warn/error). Accent is for *action and emphasis*, not decoration. Verify contrast (→ `a11y`).
5. **Layout & composition** — align to a grid; consistent alignment edges. Respect proximity/similarity (Gestalt). Responsive by *intent* (reflow, not just shrink); design the breakpoints, don't inherit them by accident.
6. **State & polish** — design loading / empty / error / disabled / hover / focus as first-class, not afterthoughts. Motion is restrained and purposeful (~150–250ms, ease), and honors `prefers-reduced-motion`.

## Checklist
- [ ] One clear primary action; hierarchy readable at a glance (squint test)
- [ ] All spacing from one scale; related grouped, groups separated
- [ ] Type scale limited and consistent; line length and line-height comfortable
- [ ] Color restrained; accent reserved for action; contrast passes (`a11y`)
- [ ] Aligned to a grid; responsive by intent with designed breakpoints
- [ ] Loading / empty / error / disabled states designed, not default
- [ ] Motion purposeful, reduced-motion honored
- [ ] Existing design tokens/system reused — nothing one-off invented

---

## Tokens, scales, and a heuristic design review
Spacing/type/color scale systems, turning ad-hoc values into tokens, dark-mode and density variants, and a
squint-test / heuristic-review pass to run before handing UI back: **`references/design-review.md`**.

## Coordination
Architecture, state, and folder structure → `frontend`. Accessibility gate (contrast, focus, ARIA) → `a11y`.
Applied by **frontend-expert-csk** on any stack; the stack-specific "how" stays in the project's frontend skill.

## Invariant rules
1. **Hierarchy before decoration** — fix what the eye sees first before adding any color or flourish.
2. **One scale per dimension** — spacing, type, and radius each come from a single defined scale.
3. **Reuse the project's system** — detect existing tokens/components; never impose a new aesthetic or library.
4. **Accessibility is a floor** — contrast, focus, and reduced-motion are non-negotiable, not a style trade-off.
5. **Every state is designed** — loading/empty/error/disabled are part of the design, not defaults.
