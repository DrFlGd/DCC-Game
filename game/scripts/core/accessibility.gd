extends RefCounted
## Accessibility helpers (Wave 3C): text size, high contrast, reduced flash
## and colour-blind telegraphs, read from the shared Settings instance
## (scripts/core/settings.gd). Pure statics, no autoloads, so every UI script
## and tests may preload it.
##
##   Accessibility.px(15)                     # 15 * text_scale, rounded
##   Accessibility.panel(Color(...))          # opaque black in high contrast
##   Accessibility.telegraph_color("melee", RoomRenderer.TELEGRAPH_COLORS)
##   Accessibility.steady(pulse, 0.4)         # no pulsing with reduced_flash
##
## UI that is built once (labels, buttons) re-reads these when it is rebuilt;
## Game emits Events.settings_changed after every change so long-lived panels
## (announcer log, settings screen) rebuild at once. Immediate-mode drawing
## (HUD, toasts, renderer) reads them every frame.
const Settings = preload("res://scripts/core/settings.gd")

## Screen-shake multiplier ceiling while reduced_flash is on (the slider still
## applies below it).
const REDUCED_SHAKE_CAP := 0.25
## Outline width (px) for high-contrast text.
const OUTLINE := 4
const OUTLINE_COLOR := Color(0, 0, 0, 1)
const HIGH_CONTRAST_PANEL := Color(0.0, 0.0, 0.0, 0.94)
const HIGH_CONTRAST_BORDER := Color(1.0, 1.0, 1.0, 0.9)
## Saturated, mutually distinct telegraph colours for high contrast mode.
const HIGH_CONTRAST_TELEGRAPHS := {"melee": Color("#ff1f1f"), "area": Color("#ffe000"),
    "dash": Color("#ff7a00"), "ranged": Color("#ff3dff"), "puddle": Color("#9dff00"),
    "summon": Color("#ffffff"), "support": Color("#29b6ff")}


static func text_scale() -> float:
    return float(Settings.shared().text_scale)


## `base_px` scaled by the text-size setting (or by `scale` when given).
static func px(base_px: float, scale: float = -1.0) -> int:
    var factor: float = text_scale() if scale <= 0.0 else scale
    return maxi(1, roundi(base_px * factor))


static func high_contrast() -> bool:
    return bool(Settings.shared().high_contrast)


static func reduced_flash() -> bool:
    return bool(Settings.shared().reduced_flash)


static func colorblind_telegraphs() -> bool:
    return bool(Settings.shared().colorblind_telegraphs)


## Panel background: `normal`, or near-opaque black in high contrast.
static func panel(normal: Color) -> Color:
    return HIGH_CONTRAST_PANEL if high_contrast() else normal


## Text outline width: 0 normally, OUTLINE in high contrast.
static func outline() -> int:
    return OUTLINE if high_contrast() else 0


## Telegraph colour for attack `type`: `palette`'s colour, or the stronger
## high-contrast one.
static func telegraph_color(type: String, palette: Dictionary) -> Color:
    if high_contrast() and HIGH_CONTRAST_TELEGRAPHS.has(type):
        return HIGH_CONTRAST_TELEGRAPHS[type]
    return palette.get(type, Color.RED)


## Fill alpha of a telegraph shape (stronger in high contrast).
static func telegraph_fill() -> float:
    return 0.38 if high_contrast() else 0.22


## Effective screen-shake multiplier: the slider, capped by reduced_flash.
static func shake_scale(slider: float = -1.0) -> float:
    var value: float = float(Settings.shared().screen_shake) if slider < 0.0 else slider
    value = clampf(value, 0.0, 1.0)
    return minf(value, REDUCED_SHAKE_CAP) if reduced_flash() else value


## `value` (a pulsing amount), or `steady` while reduced_flash is on.
static func steady(value: float, steady_value: float) -> float:
    return steady_value if reduced_flash() else value
