# System-driven widget appearance

Status: implemented on `stonework/widget-system-theming-a3ca1f`

Supersedes the widget color direction in [TailOps glass refresh](2026-08-29-liquid-glass-refresh.md). The Settings and Wormhole windows are unchanged.

## Decision

The widget no longer draws its own look. Monroe adjusts appearance once in System Settings, and every desktop widget follows:

- Light or Dark appearance, the Clear and Tinted widget styles, and the glass tint amount come from the system glass platter. The widget's removable container background is the translucent system fill (`.fill.tertiary`), not the navy-to-cyan gradient.
- The accent is the System Settings accent color, read from `NSColor.controlAccentColor`. `Color.accentColor` resolved to SwiftUI's default blue in off-screen rendering when the accent was overridden, so the widget uses `.tint`.
- Tiles, chips, borders, and secondary text use adaptive system fills and hierarchical styles, so they work in Light mode as well as Dark.
- Status color stays semantic: green online, orange warning, gray offline. Offline is gray in rows as well as tiles, so asleep phones and laptops do not read as faults. Status is also carried by symbol shape, because Clear and Tinted styles render all color white.

Fan Lever follows the same conventions. Each repository keeps its own `WidgetChrome.swift` rather than sharing a package; keep the two copies in step.

## Proof boundary

Off-screen renders show Light, Dark, and overridden-accent appearances. They do not show the system glass platter or the Clear and Tinted styles, which only the installed desktop widget can prove.
