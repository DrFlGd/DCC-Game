extends RefCounted
## Hit feedback state (COMBAT_AND_RPG §8): hit-stop, screen shake, sprite
## flashes, floating damage numbers and death bursts.
##
## Pure state, no nodes and no autoloads, so tests may preload it. Combat owns
## one instance (`combat.fx`) and feeds it from the damage pipeline; Game
## honours `hitstop` (the simulation freezes while it runs); RoomRenderer
## reads the rest and draws it. Nothing here touches `RunState.rng`, so
## feedback never changes a seeded run.
##
## Skills and items can trigger the same cues through Combat:
##   combat.fx.request_hitstop(0.06)            # capped per window unless forced
##   combat.fx.shake(Fx.SHAKE_MEDIUM)           # [amplitude px, seconds]
##   combat.fx.number(key, world_pos, 12, "crit")
##   combat.fx.flash(key, Color.WHITE)
##   combat.fx.burst(world_pos, Color("#9bd34a"))
## `key` is an enemy instance_id or "player".
##
## Wave 3C: `reduced_flash` (the accessibility setting, synced by Combat) turns
## flashes into a short subtle tint (no HDR white), caps every hit-stop at
## REDUCED_HITSTOP_MAX and caps the shake multiplier at REDUCED_SHAKE_CAP.

## Number styles: colour, font size, rise (px) and lifetime (s).
const STYLES := {
    "normal": {"color": Color("#ffffff"), "size": 11, "rise": 12.0, "life": 0.6},
    "crit": {"color": Color("#ffd84a"), "size": 15, "rise": 16.0, "life": 0.75},
    "miss": {"color": Color("#9aa3ad"), "size": 10, "rise": 10.0, "life": 0.5},
    "dot": {"color": Color("#d9e6a8"), "size": 8, "rise": 8.0, "life": 0.45},
    "player": {"color": Color("#ff5a5a"), "size": 12, "rise": 12.0, "life": 0.6},
    "heal": {"color": Color("#7cf08a"), "size": 11, "rise": 12.0, "life": 0.6},
}
## [amplitude px, duration s]. Translation only, never rotation.
const SHAKE_LIGHT := [0.6, 0.06]
const SHAKE_CRIT := [1.0, 0.08]
const SHAKE_MEDIUM := [2.0, 0.15]
const SHAKE_HEAVY := [4.0, 0.25]
const FLASH_SECONDS := 0.08
const MERGE_WINDOW := 0.1
const BURST_LIFE := 0.3
const MAX_NUMBERS := 40
## Reduced-flash limits (Wave 3C).
const REDUCED_FLASH_SECONDS := 0.05
const REDUCED_FLASH_STRENGTH := 0.3
const REDUCED_HITSTOP_MAX := 0.03
const REDUCED_SHAKE_CAP := 0.25
## Hit-stop defaults; Combat passes `feel.hitstop` from prototype_rules.json.
const HITSTOP_DEFAULTS := {"hit": 0.04, "crit": 0.07, "kill": 0.09, "phase": 0.09,
    "player_hit": 0.05, "room_clear": 0.12, "window": 0.5, "window_budget": 0.12}

## Seconds of simulation freeze left. Game skips gameplay while it is > 0.
var hitstop := 0.0
## Seconds of feedback time (advances during hit-stop too).
var time := 0.0
var config: Dictionary = HITSTOP_DEFAULTS.duplicate()
## Mirrors Settings.show_damage_numbers / screen_shake (Combat keeps them in sync).
var show_numbers := true
var shake_scale := 1.0
## Mirrors Settings.reduced_flash (Combat keeps it in sync).
var reduced_flash := false
var shake_amplitude := 0.0
var shake_left := 0.0
var shake_length := 0.0
## key -> {left: float, color: Color}
var flashes: Dictionary = {}
## {key, pos, text, value, style, age, life, rise, size, color}
var numbers: Array[Dictionary] = []
## {pos, color, age, life, particles: [{dir: Vector2, speed: float, size: float}]}
var bursts: Array[Dictionary] = []
## [time, seconds] of granted hit-stop inside the budget window.
var _stops: Array = []


func configure(hitstop_config: Dictionary) -> void:
    config = HITSTOP_DEFAULTS.duplicate()
    config.merge(hitstop_config, true)


## Clears transient visuals (room change). Hit-stop and shake keep running.
func clear() -> void:
    flashes.clear()
    numbers.clear()
    bursts.clear()


## Advances every timer. While `frozen` (hit-stop) only the hit-stop timer, the
## shake and the clock move; flashes, numbers and bursts hold their frame.
func update(delta: float, frozen: bool = false) -> void:
    time += delta
    hitstop = maxf(0.0, hitstop - delta)
    shake_left = maxf(0.0, shake_left - delta)
    if frozen:
        return
    for key in flashes.keys():
        flashes[key]["left"] = float(flashes[key]["left"]) - delta
        if float(flashes[key]["left"]) <= 0.0:
            flashes.erase(key)
    for i in range(numbers.size() - 1, -1, -1):
        numbers[i]["age"] = float(numbers[i]["age"]) + delta
        if float(numbers[i]["age"]) >= float(numbers[i]["life"]):
            numbers.remove_at(i)
    for i in range(bursts.size() - 1, -1, -1):
        bursts[i]["age"] = float(bursts[i]["age"]) + delta
        if float(bursts[i]["age"]) >= float(bursts[i]["life"]):
            bursts.remove_at(i)


# --- Hit-stop --------------------------------------------------------------------

## Asks for `seconds` of freeze. Overlapping requests take the longest, not the
## sum, and at most `window_budget` (120 ms) is granted inside any `window`
## (0.5 s) unless `force`. Returns the seconds actually added.
func request_hitstop(seconds: float, force: bool = false) -> float:
    if seconds <= 0.0:
        return 0.0
    if reduced_flash:
        seconds = minf(seconds, REDUCED_HITSTOP_MAX)
    var window: float = float(config["window"])
    for i in range(_stops.size() - 1, -1, -1):
        if time - float(_stops[i][0]) > window:
            _stops.remove_at(i)
    var wanted: float = maxf(0.0, seconds - hitstop)
    if not force:
        var used := 0.0
        for stop in _stops:
            used += float(stop[1])
        wanted = minf(wanted, maxf(0.0, float(config["window_budget"]) - used))
    if wanted <= 0.0:
        return 0.0
    hitstop += wanted
    _stops.append([time, wanted])
    return wanted


## Hit-stop for a named cue ("hit", "crit", "kill", "phase", "player_hit",
## "room_clear"); room_clear is forced past the budget.
func hitstop_for(cue: String) -> float:
    return request_hitstop(float(config.get(cue, 0.0)), cue == "room_clear")


## Splits a frame of `delta` s into the frozen part and the part the simulation
## may still use. Returns the simulated seconds (0 when the whole frame is frozen).
func consume(delta: float) -> float:
    if hitstop <= 0.0:
        update(delta)
        return delta
    var frozen: float = minf(delta, hitstop)
    update(frozen, true)
    var rest: float = delta - frozen
    if rest > 0.0:
        update(rest)
    return rest


# --- Shake -----------------------------------------------------------------------

## Starts a shake; a weaker request never cuts a stronger one short.
## `cue` is one of the SHAKE_* pairs, or pass amplitude and duration.
func shake(cue: Array, duration_override: float = -1.0) -> void:
    var amplitude: float = float(cue[0])
    var duration: float = float(cue[1]) if duration_override < 0.0 else duration_override
    if shake_left > 0.0 and current_shake() > amplitude:
        return
    shake_amplitude = amplitude
    shake_left = duration
    shake_length = maxf(0.001, duration)


## Current amplitude in px (linear decay), already scaled by the setting.
func current_shake() -> float:
    if shake_left <= 0.0:
        return 0.0
    var scale: float = minf(shake_scale, REDUCED_SHAKE_CAP) if reduced_flash else shake_scale
    return shake_amplitude * (shake_left / shake_length) * scale


## World-space renderer offset for this frame.
func shake_offset() -> Vector2:
    var amount: float = current_shake()
    if amount <= 0.0:
        return Vector2.ZERO
    return Vector2(sin(time * 71.0), cos(time * 59.0)) * amount


# --- Flash -----------------------------------------------------------------------

## Starts `key`'s hit flash. With reduced_flash it is a short tint instead:
## at most REDUCED_FLASH_SECONDS, colour clamped to 0..1 (no overbright white)
## and strength capped at REDUCED_FLASH_STRENGTH.
func flash(key: String, color: Color = Color.WHITE, duration: float = FLASH_SECONDS) -> void:
    if reduced_flash:
        duration = minf(duration, REDUCED_FLASH_SECONDS)
        color = Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0),
            clampf(color.b, 0.0, 1.0), color.a)
    flashes[key] = {"left": duration, "color": color}


## 0..1 strength of `key`'s flash (1 right after the hit; at most
## REDUCED_FLASH_STRENGTH with reduced_flash).
func flash_amount(key: String) -> float:
    if not flashes.has(key):
        return 0.0
    var amount: float = clampf(float(flashes[key]["left"]) / FLASH_SECONDS, 0.0, 1.0)
    return minf(amount, REDUCED_FLASH_STRENGTH) if reduced_flash else amount


func flash_color(key: String) -> Color:
    return flashes[key]["color"] if flashes.has(key) else Color.WHITE


# --- Damage numbers ----------------------------------------------------------------

## Spawns a floating number (or text such as "MISS") above `pos`. Numbers on
## the same key within MERGE_WINDOW merge into one. Returns the entry, or {}
## when numbers are switched off in the settings.
func number(key: String, pos: Vector2, value, style: String = "normal") -> Dictionary:
    if not show_numbers:
        return {}
    var look: Dictionary = STYLES.get(style, STYLES["normal"])
    if value is int or value is float:
        for entry in numbers:
            if String(entry["key"]) == key and float(entry["age"]) <= MERGE_WINDOW \
                    and entry["value"] is int and String(entry["style"]) == style:
                entry["value"] = int(entry["value"]) + int(value)
                entry["text"] = str(entry["value"])
                entry["age"] = 0.0
                return entry
    var entry := {"key": key, "pos": pos, "value": int(value) if (value is int or value is float) else null,
        "text": str(int(value)) if (value is int or value is float) else String(value),
        "style": style, "age": 0.0, "life": float(look["life"]), "rise": float(look["rise"]),
        "size": int(look["size"]), "color": look["color"]}
    numbers.append(entry)
    if numbers.size() > MAX_NUMBERS:
        numbers.remove_at(0)
    return entry


## Where `entry` is drawn now (rises with ease-out) and its alpha.
static func number_pose(entry: Dictionary) -> Dictionary:
    var t: float = clampf(float(entry["age"]) / maxf(0.001, float(entry["life"])), 0.0, 1.0)
    var rise: float = float(entry["rise"]) * (1.0 - (1.0 - t) * (1.0 - t))
    return {"pos": Vector2(entry["pos"]) + Vector2(0, -rise), "alpha": 1.0 - t * t}


# --- Death bursts --------------------------------------------------------------------

## 6-10 square particles flying out of `pos` in `color` for 0.3 s. `salt`
## (e.g. a hash of the instance id) varies the pattern without any RNG state.
func burst(pos: Vector2, color: Color, count: int = 8, salt: int = 0) -> Dictionary:
    var particles: Array = []
    var total: int = clampi(count, 6, 10)
    for i in range(total):
        var jitter: float = float(posmod(salt * 31 + i * 17, 13)) / 13.0
        var angle: float = TAU * (float(i) + jitter * 0.6) / float(total)
        particles.append({"dir": Vector2.RIGHT.rotated(angle), "speed": 40.0 + 30.0 * jitter,
            "size": 2.0 + float(posmod(salt + i, 3))})
    var entry := {"pos": pos, "color": color, "age": 0.0, "life": BURST_LIFE,
        "particles": particles}
    bursts.append(entry)
    return entry
