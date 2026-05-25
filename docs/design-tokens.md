# Shio — Design Tokens

This is the canonical design system spec. Figma mirrors this file; Swift code mirrors this file. If they disagree, this file wins until updated.

All tokens are named — not raw values. Never use `#1C1C1E` in code; use `color.chrome.surface`.

---

## 1. Color

### Naming model

Colors live in two layers:

- **Palette** — raw hex values. Never used directly by features.
- **Semantic tokens** — what features reference. Map to palette, light/dark resolved automatically.

### 1.1 Palette (raw)

#### Neutrals — "Ink" (cool near-black scale)

| Token | Hex | Use |
|---|---|---|
| `ink.50` | `#FAFAFA` | Lightest surface (light mode background) |
| `ink.100` | `#F2F2F4` | Light mode card / list row default |
| `ink.200` | `#E5E5E9` | Light mode dividers, subtle fills |
| `ink.300` | `#C9C9CF` | Light mode disabled, hairline borders |
| `ink.400` | `#8E8E93` | Tertiary text, placeholder, system gray-equiv |
| `ink.500` | `#636368` | Secondary text |
| `ink.600` | `#3A3A3C` | Dark mode card / list row default |
| `ink.700` | `#1C1C1E` | Dark mode primary surface |
| `ink.800` | `#0E0E10` | Dark mode app background |
| `ink.900` | `#000000` | Pure black — used only for OLED-true Dynamic Island / Live Activity contexts |

#### Accent — "Salt" (single warm-cool neutral that reads premium)

We pick one accent. Candidates to A/B in Figma:

| Token | Hex | Vibe |
|---|---|---|
| `salt.amber` | `#E8B968` | Warm, "salt under candlelight" — *recommended for first mock* |
| `salt.coral` | `#E47A6B` | Warm, slightly playful — alternative |
| `salt.teal` | `#5BA4A4` | Cool, technical — alternative |
| `salt.bone` | `#E8DCC4` | Off-white accent — alternative, very subtle |

The accent is used *sparingly* — connection-state indicators, focused borders, the brand mark. Never on body chrome.

#### Semantic states (not in accent — separate scale)

| Token | Hex | Use |
|---|---|---|
| `state.success` | `#30C46D` | Connected, succeeded |
| `state.warning` | `#E89D3C` | Backgrounding, retrying, degraded |
| `state.danger` | `#E25555` | Disconnected, error, destructive action |
| `state.info` | `#5B8DEF` | Informational, neutral signal |

State colors are calibrated for both themes — pure values shown here, dark/light tint adjustments via opacity (see 1.3).

### 1.2 Semantic tokens (what features reference)

#### App chrome

| Token | Dark | Light | Use |
|---|---|---|---|
| `chrome.background` | `ink.800` | `ink.50` | Top-level app surface |
| `chrome.surface` | `ink.700` | `#FFFFFF` | Cards, sheets, list rows |
| `chrome.surface.elevated` | `ink.600` | `#FFFFFF` (with shadow) | Modal sheets, popovers |
| `chrome.divider` | `ink.700` lightened 12% | `ink.200` | Hairlines, separators |
| `chrome.border` | `ink.600` | `ink.300` | Field borders, button borders |
| `chrome.fill` | `ink.700` lightened 6% | `ink.100` | Filled buttons (secondary) |
| `chrome.fill.pressed` | `ink.700` lightened 12% | `ink.200` | Pressed state |

#### Text

| Token | Dark | Light | Use |
|---|---|---|---|
| `text.primary` | `#F2F2F4` | `ink.900` | Body, headings |
| `text.secondary` | `ink.400` | `ink.500` | Subtitles, supporting text |
| `text.tertiary` | `ink.500` | `ink.400` | Placeholder, captions |
| `text.disabled` | `ink.500` 60% | `ink.400` 60% | Disabled |
| `text.accent` | `salt.amber` | `salt.amber` darkened 8% | Active state, focused |
| `text.danger` | `state.danger` | `state.danger` darkened 4% | Errors, destructive |

#### Terminal

The terminal uses macOS Terminal "Basic" profile colors pixel-for-pixel. **Do not deviate.**

| Token | Dark | Light | Source |
|---|---|---|---|
| `terminal.background` | `#000000` | `#FFFFFF` | macOS Terminal Basic |
| `terminal.foreground` | `#FFFFFF` | `#000000` | macOS Terminal Basic |
| `terminal.cursor` | `#FFFFFF` | `#000000` | Block cursor |
| `terminal.selection` | `#FFFFFF` 20% | `#000000` 20% | Selection highlight |
| `terminal.ansi.black` | `#000000` | `#000000` | xterm 0 |
| `terminal.ansi.red` | `#C91B00` | `#C91B00` | xterm 1 |
| `terminal.ansi.green` | `#00C200` | `#00C200` | xterm 2 |
| `terminal.ansi.yellow` | `#C7C400` | `#C7C400` | xterm 3 |
| `terminal.ansi.blue` | `#0225C7` | `#0225C7` | xterm 4 |
| `terminal.ansi.magenta` | `#CA30C7` | `#CA30C7` | xterm 5 |
| `terminal.ansi.cyan` | `#00C5C7` | `#00C5C7` | xterm 6 |
| `terminal.ansi.white` | `#C7C7C7` | `#C7C7C7` | xterm 7 |
| `terminal.ansi.brightBlack` | `#686868` | `#686868` | xterm 8 |
| `terminal.ansi.brightRed` | `#FF6E67` | `#FF6E67` | xterm 9 |
| `terminal.ansi.brightGreen` | `#5FFA68` | `#5FFA68` | xterm 10 |
| `terminal.ansi.brightYellow` | `#FFFA72` | `#FFFA72` | xterm 11 |
| `terminal.ansi.brightBlue` | `#6871FF` | `#6871FF` | xterm 12 |
| `terminal.ansi.brightMagenta` | `#FF77FF` | `#FF77FF` | xterm 13 |
| `terminal.ansi.brightCyan` | `#60FDFF` | `#60FDFF` | xterm 14 |
| `terminal.ansi.brightWhite` | `#FFFFFF` | `#FFFFFF` | xterm 15 |

### 1.3 Opacity scale

Used for overlays, disabled states, dividers.

| Token | Value |
|---|---|
| `opacity.disabled` | 0.40 |
| `opacity.muted` | 0.60 |
| `opacity.divider` | 0.08 |
| `opacity.overlay` | 0.45 |
| `opacity.hover` | 0.06 |
| `opacity.pressed` | 0.12 |

---

## 2. Typography

### 2.1 Type families

| Token | Family | Use |
|---|---|---|
| `font.chrome` | SF Pro | All UI chrome (titles, body, buttons, settings) |
| `font.mono` | SF Mono | Terminal, code, hostnames, command previews |
| `font.display` | SF Pro Display | Hero / large titles (≥34pt) only |

We never ship a third typeface. No Inter, no IBM Plex, no JetBrains Mono in v1. SF Mono in the terminal is non-negotiable — it matches the user's expectation from macOS Terminal.

### 2.2 Type scale

Tight, opinionated, six sizes max for chrome.

| Token | Size | Line Height | Weight | Use |
|---|---|---|---|---|
| `text.display` | 34pt | 41pt | 600 (Semibold) | Onboarding hero, empty-state hero |
| `text.title1` | 22pt | 28pt | 600 (Semibold) | Screen titles |
| `text.title2` | 17pt | 22pt | 600 (Semibold) | Section headers |
| `text.body` | 15pt | 20pt | 400 (Regular) | Body, list rows, settings |
| `text.body.emphasis` | 15pt | 20pt | 500 (Medium) | Emphasis within body |
| `text.callout` | 13pt | 18pt | 400 (Regular) | Subtitles, captions, hints |
| `text.footnote` | 11pt | 14pt | 400 (Regular) | Footnotes, fingerprints, legal |

### 2.3 Mono scale (terminal & code)

| Token | Size | Line Height | Use |
|---|---|---|---|
| `mono.terminal.default` | 13pt | 18pt | Default terminal font size on iPhone |
| `mono.terminal.iPad` | 14pt | 20pt | Default on iPad |
| `mono.terminal.min` | 9pt | 12pt | Smallest (after pinch-out) |
| `mono.terminal.max` | 24pt | 32pt | Largest (after pinch-in) |
| `mono.inline` | 13pt | 18pt | Hostnames, commands in chrome |
| `mono.fingerprint` | 11pt | 14pt | SSH fingerprints |

### 2.4 Letter-spacing

| Token | Value | Use |
|---|---|---|
| `tracking.tight` | -0.02em | `text.display`, `text.title1` |
| `tracking.normal` | 0 | Most body |
| `tracking.wide` | 0.04em | Small all-caps labels (avoid; we don't use all-caps) |

### 2.5 Wordmark

The `shio` wordmark is hand-tuned. In code, it's an SVG/PDF asset, not live text. Reference: `/assets/wordmark.svg`.

---

## 3. Spacing

4-point grid. Named tokens only.

| Token | px | Use |
|---|---|---|
| `space.0` | 0 | Resets |
| `space.xxs` | 2 | Hair-fine adjustments (icon nudges) |
| `space.xs` | 4 | Tight grouping (icon-to-label) |
| `space.sm` | 8 | Default inline gap |
| `space.md` | 12 | Section internal padding |
| `space.lg` | 16 | Standard padding, list row padding |
| `space.xl` | 24 | Section spacing |
| `space.xxl` | 32 | Major section gap |
| `space.xxxl` | 48 | Empty-state vertical centering, hero spacing |
| `space.layout` | 64 | Top-of-screen, large layout breathing |

### Layout-specific

| Token | Value | Use |
|---|---|---|
| `padding.screen.horizontal.iPhone` | 20 | Horizontal screen padding on iPhone |
| `padding.screen.horizontal.iPad` | 32 | Horizontal screen padding on iPad |
| `padding.row.vertical` | 14 | List row vertical |
| `padding.button.vertical` | 12 | Button height = 44pt minimum tap target |
| `padding.button.horizontal` | 20 | Button horizontal |
| `tapTarget.min` | 44 | All interactive elements minimum |

---

## 4. Radius

| Token | Value | Use |
|---|---|---|
| `radius.0` | 0 | Resets |
| `radius.xs` | 4 | Inline chips, small badges |
| `radius.sm` | 6 | Accessory keys, small buttons |
| `radius.md` | 10 | Standard buttons, fields |
| `radius.lg` | 14 | Cards, list rows, host cards |
| `radius.xl` | 20 | Sheets, modals |
| `radius.full` | 9999 | Pills, circular avatars |

---

## 5. Shadow / Elevation

Used sparingly. Dark mode uses opacity tricks more than shadow. Light mode uses subtle shadows.

| Token | Dark | Light |
|---|---|---|
| `shadow.0` | none | none |
| `shadow.1` | none | `0 1px 2px rgba(0,0,0,0.04)` |
| `shadow.2` | `0 8px 24px rgba(0,0,0,0.50)` | `0 4px 12px rgba(0,0,0,0.08)` |
| `shadow.3` | `0 16px 48px rgba(0,0,0,0.60)` | `0 12px 32px rgba(0,0,0,0.12)` |

Use `shadow.2` for sheets, `shadow.3` for popovers/menus. Everything else uses borders or background contrast.

---

## 6. Motion

### 6.1 Easing

| Token | Curve | Use |
|---|---|---|
| `ease.standard` | `cubic-bezier(0.32, 0.72, 0.0, 1.0)` | Default; most chrome motion |
| `ease.enter` | `cubic-bezier(0.0, 0.0, 0.2, 1.0)` | Things appearing |
| `ease.exit` | `cubic-bezier(0.4, 0.0, 1.0, 1.0)` | Things disappearing |
| `ease.spring.gentle` | spring(response: 0.5, dampingFraction: 0.85) | Sheets, popovers |
| `ease.spring.snappy` | spring(response: 0.32, dampingFraction: 0.80) | Toggles, button feedback |

### 6.2 Duration

| Token | Value | Use |
|---|---|---|
| `duration.instant` | 0ms | Terminal interactions, keypress feedback |
| `duration.fast` | 150ms | Button presses, focus rings |
| `duration.standard` | 240ms | Most transitions, sheet presents |
| `duration.slow` | 400ms | Large state changes, scene transitions |
| `duration.deliberate` | 600ms | Onboarding step transitions only |

### 6.3 Principles

- **Terminal interactions are instantaneous.** Cursor blink, character echo, scroll — never animated by Shio.
- **Chrome moves with intent.** When the host list opens, it tells you it opened; it doesn't bounce.
- **No motion for its own sake.** No parallax, no spring overshoots in v1, no animated icons.
- **Reduce Motion**: respect the system setting fully. Cross-fade replaces translate/scale.

---

## 7. Iconography

### 7.1 Source

- **Primary**: SF Symbols 6+, matched to current font weight.
- **Custom**: only where SF Symbols genuinely fail — the keyboard accessory row keys (`Esc`, `Ctrl`, `Opt`, etc.), the Tailscale glyph, the Mosh glyph.
- **Stroke**: SF Symbols default stroke weight matches body weight; custom glyphs match this — 1.5px equivalent at 17pt.

### 7.2 Sizes

| Token | Size | Use |
|---|---|---|
| `icon.xs` | 12 | Inline status dots, micro-badges |
| `icon.sm` | 16 | Inline with body text |
| `icon.md` | 20 | List row icons, button icons |
| `icon.lg` | 28 | Accessory keys, large taps |
| `icon.xl` | 44 | Empty-state, onboarding hero icons |

### 7.3 Specific icons

| Concept | SF Symbol | Note |
|---|---|---|
| Mac (host) | `desktopcomputer` | Default host icon |
| Connection (active) | `circle.fill` in `state.success` | Status indicator |
| Connection (disconnected) | `circle.fill` in `text.tertiary` | |
| Tailscale | Custom glyph (Tailscale logo) | Trademark, use sparingly |
| SSH key | `key.fill` | |
| Settings | `slider.horizontal.3` | Not `gearshape` — feels too generic |
| Pro Mode | `wrench.adjustable.fill` | |

---

## 8. Components

Each component has all states (default / pressed / disabled / loading / error). Full visual spec in Figma; this enumerates them.

| Component | Variants |
|---|---|
| Button (primary) | default, pressed, disabled, loading |
| Button (secondary) | default, pressed, disabled |
| Button (text) | default, pressed, disabled, destructive |
| List row | default, pressed, selected, swipe-revealed |
| Host card | connected, disconnected, connecting, error |
| Field (text input) | default, focused, error, disabled |
| Toggle | off, on, disabled |
| Sheet | mounting, idle, dismissing |
| Modal | mounting, idle, dismissing |
| Banner | info, warning, danger (auto-dismissing or persistent) |
| Accessory key | default, pressed, modifier-active, modifier-locked |
| Status pill | success, warning, danger, info |

---

## 9. Haptics

| Token | UIImpactFeedbackStyle | Use |
|---|---|---|
| `haptic.light` | `.light` | Key press in soft keyboard accessory |
| `haptic.medium` | `.medium` | Toggle, modifier-lock activation |
| `haptic.heavy` | `.heavy` | Destructive confirmation |
| `haptic.success` | `.success` (notification) | Connection established |
| `haptic.warning` | `.warning` (notification) | Reconnecting |
| `haptic.error` | `.error` (notification) | Connection lost |

---

## 10. Sound

- **None in v1.** No connection sound. No bell sound by default (terminal bell is a Settings toggle).
- Optional terminal bell: short, tasteful, custom sample (TBD).

---

## 11. Implementation notes

- **Swift exposure**: define a `DesignTokens` enum namespace. Colors via `Color(token: .chromeBackground)` etc. Avoid raw hex literals anywhere in feature code.
- **Figma source of truth**: Figma variables mirror these tokens exactly. CI may diff Figma export → Swift in v1.1+.
- **xterm.js theming**: CSS variables in the WebView wrapper consume the same tokens via a Swift → CSS bridge at session start.
- **Dynamic Type**: only the `text.*` tokens scale. `mono.*` tokens scale separately via a Settings control (the terminal has its own size, controlled by user, not by Dynamic Type).
