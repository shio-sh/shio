# Shio — App Icon Concepts

The icon is the brand. It will be the only thing many people see before they decide whether to tap. It must read at 60pt on a home screen, at 29pt in Settings, and behave gracefully in tinted/clear/dark Liquid Glass contexts on iOS 26.

---

## ✅ LOCKED — Direction E: Kanji 塩 in DotGothic16

After exploring the four directions below plus a fifth (kanji + display type), the icon is locked as:

- **Glyph**: 塩 (Japanese for *salt*, the word's etymology)
- **Typeface**: DotGothic16 (Google Fonts) — pixel-grid Japanese font, terminal-coded
- **Background**: `#F4EEDF` (diluted bone — new `chrome.background.light` token)
- **Foreground**: `#0E0E10` (`ink.800`)
- **Size**: ~52% of canvas. Deliberately gives the character breathing room — not all icons need to fill the safe area; a 13-stroke kanji has its own visual density.
- **Composition**: geometric center on a 1024×1024 canvas.

Master at `/assets/icon/master.svg`. PNG exports at all required Apple sizes in `/assets/icon/shio-*.png`.

**Known trade-off**: at 29×29 raw (@1x Settings), the character degrades to "a complex CJK glyph" without holding identity. Accepted because modern iPhones (XS+) use @2x (58px) and @3x (87px) where the character reads beautifully — @1x is a corner case not worth diluting the home-screen impression for.

---

## Exploration history (preserved for context)

The four original directions explored below, plus the kanji direction that won. We mocked the kanji direction in Figma first, ran the 29pt brutal-test, and accepted the small-size trade-off in favor of distinctiveness and brand integrity.

---

## Constraints

- **Master canvas**: 1024×1024 px (App Store) → exported at all required sizes.
- **Safe area**: assume Apple's standard iOS icon mask (squircle); design with 18% inset from the literal 1024 canvas for visual centering.
- **Tintable variants** (iOS 26 Liquid Glass):
  - Light mode
  - Dark mode
  - Clear (tinted, monochrome over a glassy background)
- **Read at small sizes**: the 29pt (Settings) test is brutal — if a concept loses its identity at that size, it fails.
- **Avoid**:
  - Gradient soup
  - Drop shadows or 3D rendering
  - Tiny text within the icon (never "Shio" written inside)
  - Stock terminal glyphs (`>_`, `$`, `~`) used literally — they're a category cliché
  - Skeuomorphic textures (no salt-grain photoreal, no real-keyboard-key)

---

## Direction A — Salt Grain *(recommended for first mock)*

### Concept

A single, abstracted salt crystal — a soft cube tilted slightly, with one face slightly brighter than the others. The whole icon is the grain. The background is a deep neutral; the grain is in the brand accent.

### Why it could work

- **Literal nod to the name** — `shio` is Japanese for salt. The grain *is* the brand.
- **Premium and quiet** — single object on a clean ground, the Things 3 / Bear / Cardpointers move.
- **Distinctive at small sizes** — one shape, no details to lose.
- **Tints beautifully** — a single accent shape over a single neutral works in every Liquid Glass mode.

### Visual notes

- The cube is *not* a perfect isometric cube. It's an organic, slightly imperfect crystal — closer to a kintsugi salt-flake shape than a die. Soft corners, slight asymmetry.
- Faces are lit by a soft single light source (top-left) — but never with a literal gradient. Use 2–3 flat tone values, no continuous gradient ramp.
- Optional: a single subtle highlight glint on one corner — but only if it survives at 29pt. If it doesn't, drop it.

### Risk

- People who don't know "shio = salt" may read it as: a dice, a cube, a sugar cube, a button. Mitigate via wordmark proximity (in landing page / wordmark uses), accept ambiguity for the icon itself.

### Mockup brief for Figma

- Canvas: 1024 × 1024
- Background: `chrome.background` dark variant (`#0E0E10`), light variant (`#FAFAFA`)
- Salt grain: 480×480 centered, fill `salt.amber` (`#E8B968`), 2 darker tone faces at 88% and 76% lightness
- No outline. No shadow. No gradient.

---

## Direction B — The Cursor

### Concept

A solid block cursor (the macOS Terminal default), centered, in the brand accent — set against the brand background. That's it. The icon *is* the cursor.

### Why it could work

- **Immediately legible** — the user knows what app this is before they read the name.
- **Maximally minimal** — a single rectangle on a ground.
- **Honest** — Shio is a terminal. The icon is a terminal cursor.

### Risk

- **Generic risk is high** — every terminal app has flirted with this. We'd need a *distinctive* cursor — perhaps subtly tapered, slightly proud of the literal block, or with one corner softened.
- **Reads as Notepad / Notes apps** in some contexts (they also use a writing-implement-coded mark).
- **Cursor that blinks in icon**? No — Apple doesn't allow animated app icons. The icon must work static.

### Mockup brief for Figma

- Canvas: 1024 × 1024
- Background: `terminal.background` (`#000000` dark / `#FFFFFF` light) — *literal* terminal background
- Cursor: 240 × 360 (taller than wide, matching terminal block proportions), fill `terminal.foreground` or `salt.amber`
- Centered vertically and horizontally
- Optional variant: cursor positioned slightly off-center to imply "where text starts" — feels more alive

---

## Direction C — Wordmark Mark

### Concept

Just the letter "s" — or the bigram "sh" — set in a custom-tuned display cut, fill `salt.amber` on `chrome.background`. The icon is the wordmark, abstracted.

Think: Things (the checkmark-as-mark), Bear (the bear), Linear (the L mark).

### Why it could work

- **Iconic potential** — well-executed letter marks become instantly recognizable.
- **Direct brand reinforcement** — every icon impression also reinforces the name.
- **Premium feel** — letter marks are the move for considered indie apps.

### Risk

- **Letter-as-mark is generic without strong typography** — we'd need to commission or hand-tune a real letterform, not just set in SF Pro. That's design work that requires a typographer's eye.
- **The letter "s" is hard** — it has no straight edges, can read as cartoonish at small sizes.
- **"sh" might be cleaner than "s"** — two letters can be arranged more sculpturally and read as a composed mark, but starts looking like a bigram-mark cliché.

### Mockup brief for Figma

- Canvas: 1024 × 1024
- Background: `chrome.background` (dark and light)
- Letter: hand-tuned `s` or `sh`, fill `salt.amber`, sized to fill ~70% of the optical center
- Try at least two letterform candidates: a humanist lowercase `s` (warmer, friendlier) and a geometric one (more architectural)

---

## Direction D — Wave / Signal

### Concept

A single, elegant wave or ripple — abstracted, perhaps just two or three nested arcs. Suggests *connection*, *signal*, *salt dissolving in water* (a nod to the name without being literal).

### Why it could work

- **Connection-coded** — Shio is, at its core, about connecting your phone to your Mac.
- **Salt-dissolving metaphor** — softer interpretation of the name that doesn't require the user to know Japanese.
- **Distinctive and abstract** — wouldn't be confused with any current terminal app.

### Risk

- **Reads as audio / podcast / radio app** in some contexts — the wave is taken.
- **Less honest** — Shio is not "about" signals; that's metaphor stretching.
- **Hard to land at small sizes** — multiple arcs can muddy at 29pt.

### Mockup brief for Figma

- Canvas: 1024 × 1024
- Background: `chrome.background`
- Mark: 2–3 concentric arcs centered, stroke `salt.amber`, stroke widths decreasing from inner to outer (or vice versa — test both)
- No fill, just strokes — relies on negative space

---

## Recommendation for first round of mocks

Mock **Direction A (Salt Grain)** first — it's the most on-brand and the most differentiated from competitors. If it falls short at 29pt or tints poorly in Liquid Glass clear mode, fall back to **Direction C (Wordmark Mark)** as the second-place candidate.

**Skip B (Cursor)** unless A and C both fall through — it's too category-coded to feel premium.

**Skip D (Wave)** unless we want a more abstract, less literal direction.

---

## Process

1. **Sketch first** — 5-minute pencil sketches of each direction. No Figma yet. Goal: throw out bad ideas cheaply.
2. **Figma round 1** — mock the top 2 directions at 1024×1024 in both light and dark modes.
3. **Size test** — export at 1024, 180, 120, 87, 80, 60, 58, 40, 29, 20 pt and view on a real home screen on iPhone (light wallpaper, dark wallpaper, photo wallpaper).
4. **Liquid Glass test** — view in light mode, dark mode, tinted (a few accent colors), and clear (over a light backdrop and a dark backdrop).
5. **Decide.** Lock the master. Export all required variants per Apple's icon spec.

---

## Final spec (once chosen)

- 1024×1024 master PNG (App Store)
- 180×180 (iPhone @3x)
- 120×120 (iPhone @2x)
- 167×167 (iPad Pro @2x)
- 152×152 (iPad @2x)
- 87×87 / 80×80 / 60×60 / 58×58 / 40×40 / 29×29 / 20×20 (various)
- Tinted icon master (single-color, monochrome) for Liquid Glass clear mode
- Dark icon variant if visually distinct (optional in iOS 26)

All exports live in `/assets/icon/` in the repo. Source `.fig` and `.psd` in `/design/`.
