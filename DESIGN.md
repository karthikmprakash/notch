# Persona dashboard design

The current UI keeps the reference images’ matte surfaces, black physical notch,
blue active states, individually clipped tiles, and rounded island outline.

- Grid: 76 pt nominal cells, 6 pt gaps, 10 pt outer padding. A shared
  column pitch fills each complete row; short rows remain centered.
- Ribbon wraps at 10 cells (834 pt default width); Board wraps at 6
  (520 pt minimum width). Wider hardware notches expand the minimum width.
- Navigation: two tabs in each wing beside the measured hardware notch,
  in a fixed 520 pt minimum navigation region. Their screen positions stay
  identical when switching between Board and Ribbon. The cutout contains no controls.
- Tiles: 82 pt Compact / 112 pt Comfortable, 10 pt insets, 10 pt corners.
  Compact is the default; existing profiles migrate once without changing
  composition. Later density choices persist. Footer: 22 pt, Apps/pin/settings.
- Media and Developer: 520 × 244 pt with a 179 × 32 pt notch. Focus:
  520 × 156 pt. Everyday: 834 × 156 pt. No separate navigation row or caption.
- Typography: SF system, 12 pt semibold card titles, 10–11 pt supporting text,
  10 pt wing labels, 12–13 pt control symbols. Weather is 26 pt in Compact;
  timer is 22 pt with monospaced digits. Small symbols keep 22–26 pt hit areas.
- Switching workspaces is immediate, with no geometric interpolation or spring.
  A stable transparent AppKit canvas contains all states; only display changes
  resize the window. SwiftUI updates the shape and contents together. The
  transparent area is excluded from pointer capture.
- Small tiles get minimal icon/value controls, rather than squeezing the full
  card into one column. Medium/wide tiles expose their normal feature UI.
- Dark Matte keeps the original palette. White Matte keeps the original
  background/text/accent but uses #E9EBEF tiles for clearer separation.
- Music keeps the vinyl motif; title/artist above progress and transport.
- System controls have tooltips/accessibility labels and persistent volume/brightness values; Comfortable also shows text labels.
- Focus uses a static progress ring with 15/25/50 minute presets. Clicking the timer opens the duration menu in either density.
- Developer shows real hook state and a local, bounded activity history.
- Settings groups workspace composition, integrations, general behavior, and
  developer setup into four tabs, with a miniature layout preview.
- Hover: screen-coordinate sampling at 20 Hz; 12 pt side / 10 pt lower approach margin; 250 ms dwell, 300 ms exit grace. Click capture is limited to the actual island.
- Global open shortcut: Control–Option–Space; existing permission shortcuts stay.

The compact Media layout was checked in the running signed release build. Unit
coverage exercises repeated workspace switches, stable canvas bounds at both
densities, the maximum tile grid, long permission cards, and wing/footer hit
regions, plus hover dwell/re-entry and settings persistence.

## Future custom content

Bookmarks, references, and statuses should use the same tile chrome, shared
column pitch, saved workspace composition, and minimal one-cell presentation.
Use a compact summary that opens details on demand. Keep navigation positions
fixed and bound long lists to a scrolling tile/detail surface; do not keep
increasing the notch footprint as more content is saved. Custom content editors
and storage are future work, not features shipped by this layout revision.

---

The following is the historical v1 measurement sheet; its dimensions describe
v1 and the original references, not the current persona dashboards.

# Layout spec — measured from the two mockups

Both mockups (`design/mockup-dark-matte.png`, `design/mockup-white-matte.png`) are
1400×247 px captures of the same layout at 2×, so every number below is
`pixels / 2` in points. They are the reference for every step: after a build,
capture the top of the screen and compare against these numbers.

## Island

| | mockup | this build |
|---|---|---|
| expanded width | 679 pt | 679 pt |
| padding around tiles | 12.5 pt | 12.5 pt |
| gap below the notch band | 12.5 pt | 12.5 pt |
| tile height | 70 pt (139 px) | 70 pt |
| tile corner radius | 12 pt (24 px) | 12 pt |
| notch band corner radius (bottom) | ~9.5 pt | 10 pt |
| island bottom corner radius | ~24 pt | 24 pt |
| island top corner radius | small rounding | 18 pt (`Layout.openTopRadius`) |
| shoulder flare | none — the mockups show a plain rounded card | none |

Total expanded height = `notch height + 12.5 + 70 + 12.5`.
On this Mac the notch is 179 × 32 pt, so the island is 679 × 127 pt.

### Island outline

The open island is **one rounded card flush with the top of the screen**, with
the black notch band drawn inside it — that is what both mockups show. An
earlier build flared the card out of the notch with an iPhone-style "shoulder";
because the island (679 pt) is ~3.8× the notch (179 pt) that flare became a
250 pt-wide, 14 pt-tall slope on each side and read as if the corners had been
cut off. It is gone.

The **closed** pill keeps square top corners and is exactly notch height, so pill
and notch read as a single shape; only its bottom corners round (11 pt).

## Tile grid

One cell = **60 pt**, gap = **6 pt**. A tile that spans *n* cells is
`n × 60 + (n − 1) × 6` wide:

| cells | width | in the mockup |
|---|---|---|
| 1 | 60 pt | (not used) |
| 2 | 126 pt | Weather, Controls |
| 3 | 192.5 pt | Music, Messages |

The mockup row is 3 + 2 + 3 + 2 = 10 cells → 654 pt of tiles + 3 × 6 pt gaps +
2 × 12.5 pt padding = **679 pt**.

## Sub-elements measured in the music / messages / controls tiles

| element | measured |
|---|---|
| album art block | ~55 pt tall, bleeds past the tile padding, clipped by the tile |
| vinyl disc peeking right of the cover | ~15 pt overlap |
| progress bar | 3 pt tall, full width of the text column, rounded ends |
| progress fill / track | in the mockup the fill is 62 % (2:14 of 3:34 ✔) |
| transport row | 3 icons, ~24.5 pt apart, centred |
| accent badge (unread count) | 12 pt circle, centred on the row |
| quick-control buttons | 2 rows × 3, ~35 × 25 pt, 4 pt gaps, 6 pt tile padding |
| messages rows | 2 rows, name + badge + preview + time, right edge has a chevron |

## Colours

The hex values you gave are used as-is:

| | Dark Matte | White Matte |
|---|---|---|
| background | `#16181F` | `#F7F8FA` |
| tile | `#21242D` | `#FBFBFC` |
| text | `#E3E7EF` | `#1E2129` |
| secondary text | `#A4ABBA` | `#545A69` |
| accent | `#8FC7FF` | `#3B82D0` |

**Two discrepancies worth knowing about**, both found by measuring the mockups:

1. **Dark mockup is brighter than the spec.** Measured island `#272936`,
   tiles `#373743` — i.e. every channel is ~+18 above your hex values. Your
   values are used instead (they look right on a real screen; the mockups were
   likely rendered with a lifted black level).
2. **In the light mockup the tiles are *darker* than the panel** (tiles
   `#E2E2E4`, panel `#F0F1F3`), the opposite of the spec, where the tile
   `#FBFBFC` is *lighter* than the panel `#F7F8FA`. The spec is used. In the
   White Matte theme this makes tiles read as one flat panel separated only by a
   hairline, while the mockup reads as distinct white cards on grey. Flipping it
   is a one-line change in `Theme.whiteMatte` if you prefer the mockup.

## Peek

Not in the mockups; derived from them so it matches: 360 pt wide (or notch +
160 pt, whichever is bigger), 64 pt tall below the notch band, same shoulder
flare and bottom radius as the expanded island, icon in a 30 pt rounded square
tinted with the accent, title 13.5 pt semibold, optional subtitle 11.5 pt.
