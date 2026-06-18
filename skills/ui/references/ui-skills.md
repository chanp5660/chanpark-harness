---
name: ui-skills-summary
description: "UI Skills constraint set summary (implementation quality first)"
---

# UI Skills Summary

A constraint set to prevent common failure points in UI implementation.

## Stack
- MUST: Use Tailwind CSS default values (exceptions only for existing customizations or explicit requests)
- MUST: Use `motion/react` when JavaScript animations are needed
- SHOULD: Use `tw-animate-css` for Tailwind entrance/minor animations
- MUST: Use `cn` (`clsx` + `tailwind-merge`) for class management

## Components
- MUST: Use accessible primitives for keyboard/focus behavior
- MUST: Prefer existing primitives
- NEVER: Mix primitives on the same interactive surface
- SHOULD: Prefer Base UI when compatible
- MUST: Add `aria-label` to icon-only buttons
- NEVER: Hand-implement keyboard/focus behavior (unless explicitly requested)

## Interaction
- MUST: Use AlertDialog for destructive actions
- SHOULD: Use structural skeletons for loading states
- NEVER: Use `h-screen`; use `h-dvh` instead
- MUST: Account for `safe-area-inset` on fixed elements
- MUST: Display errors close to the point of interaction
- NEVER: Block paste in input/textarea

## Animation
- NEVER: Do not add animations unless explicitly requested
- MUST: Animate only `transform` / `opacity`
- NEVER: Animate `width/height/top/left/margin/padding`
- SHOULD: Animate `background/color` only on small, localized UI
- SHOULD: Use `ease-out` for entrances
- NEVER: Feedback animations must not exceed 200ms
- MUST: Pause loops when off-screen
- SHOULD: Respect `prefers-reduced-motion`
- NEVER: Custom easing is prohibited unless explicitly requested
- SHOULD: Avoid animations on large images or full-bleed surfaces

## Typography
- MUST: Use `text-balance` for headings
- MUST: Use `text-pretty` for body text
- MUST: Use `tabular-nums` for numeric values
- SHOULD: Use `truncate` or `line-clamp` in dense UI
- NEVER: Do not arbitrarily change `tracking-*`

## Layout
- MUST: Use a fixed `z-index` scale (avoid arbitrary `z-*` values)
- SHOULD: Use `size-*` for squares

## Performance
- NEVER: Do not animate large `blur()` / `backdrop-filter`
- NEVER: Do not apply `will-change` unconditionally
- NEVER: Write in render what does not need to be written in `useEffect`

## Design
- NEVER: Gradients are prohibited unless explicitly requested
- NEVER: No purple or multi-color gradients
- NEVER: Do not use glow as a primary visual cue
- SHOULD: Use Tailwind default shadow scale
- MUST: Empty states must present one clear "next action"
- SHOULD: Limit accent color to one
- SHOULD: Prefer existing theme/tokens over introducing new colors

## Sources
- https://www.ui-skills.com/
- https://agent-skills.xyz/skills/baptistearno-typebot-io-ui-skills
