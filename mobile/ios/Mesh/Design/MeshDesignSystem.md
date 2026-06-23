# Mesh Design System

Self-custody USDT wallet — minimal, restrained, spacious. Reference: dark fintech onboarding (black + violet CTAs).

## Principles

- **Pure black** — `#000000` background, no gradients or orbs
- **One accent** — `#5D68D7` periwinkle blue for primary CTAs
- **Chrome control** — 44pt circle, `chromeFill` + hairline border (`MeshChromeButton`)
- **Surfaces** — flat `#1C1C1E` panels, 16pt radius; no glass, no glow
- **Space** — 24pt screen padding, generous vertical gaps, content breathes
- **Full-width actions** — 56pt purple capsule primary, dark gray secondary
- **Typography** — bold 28pt titles, 15pt secondary copy, no gradient text

## Typography

**Geist Sans** (bundled TTF) — all UI text via `MeshTheme.Typography` / `MeshFont`.

| Role | Style |
|------|--------|
| Screen title | 32pt Geist SemiBold |
| Body / secondary | 16–17pt Geist Light / Regular |
| Label | 13pt Geist Light |
| Caption | 14pt Geist Light |

## Components

- `MeshMinimalOnboarding` — `MeshOnboardingScreen`, `MeshNavigationHeader`, `MeshTitleBlock`, `MeshOptionButton`, `MeshBulletList`, `MeshInputPanel`
- `MeshPrimaryButton` / `MeshSecondaryButton` — full-width capsules
- `MeshAmbientBackground` — black + optional subtle vertical line
- `meshSurfacePanel()` — flat gray card

## Layout

- Welcome: centered title, stacked Create (purple) + Restore (gray) at bottom
- Flow screens: back chevron, title block, content, purple footer CTA
- Brand mark: small “M” top-right on welcome and wallet home

## Do not use

- Side-by-side giant glass action cards
- Gradient heroes, 3D illustrations, purple glow orbs
- `ultraThinMaterial`, frosted glass grids
- White primary buttons (legacy Revolut style)
- Dense status strips and capability grids on welcome
