extends RefCounted
## Generic ground hazards: telegraph -> active -> expire.
##
## Live entries are plain dictionaries stored in `Combat.hazards` (one array
## per current room; Combat clears it on room transitions). Any system may add
## entries there (grace debris, trap plates, enemy puddles from 2C):
##
##   {pos: Vector2, radius: float, telegraph_remaining: float, damage: int,
##    duration: float, source: String, kind: String}
##
## Optional keys: `telegraph` (total telegraph seconds, for the fill ratio;
## defaults to the first seen telegraph_remaining), `ticks` (int, collapse
## ticks drained on activation if the crawler is inside), `hits_enemies`
## (bool, default false), `interval` (float > 0: re-activates every interval
## while active, i.e. a damage-over-time puddle; 0 = one activation),
## `label` (String drawn above the telegraph, e.g. "-1"), `color` (Color).
## Bookkeeping keys written by this module: `hit` ({target_key: true} for the
## current activation), `active_time`, `activations`.
##
## Rules: nothing happens during the telegraph. Once active, each target is
## hit at most once per activation, and the crawler is skipped (not hit) while
## `player.invulnerability > 0` (dodge i-frames avoid it). Damage is flat (no
## AC roll) and goes through `Combat.apply_damage(target, amount, {source})`.
## Pure module: no autoload references, safe to preload from tests.

const DEFAULT_COLOR := Color("#ff9c5a")


## Builds a normalised entry. `extra` keys are merged over the defaults.
static func make(kind: String, pos: Vector2, radius: float, telegraph: float, damage: int,
        duration: float, source: String, extra: Dictionary = {}) -> Dictionary:
    var entry := {
        "kind": kind, "pos": pos, "radius": radius, "telegraph": telegraph,
        "telegraph_remaining": telegraph, "damage": damage, "duration": duration,
        "source": source
    }
    entry.merge(extra, true)
    return normalize(entry)


## Fills missing keys so entries written by other teams behave like make().
static func normalize(entry: Dictionary) -> Dictionary:
    if not entry.has("kind"):
        entry["kind"] = "generic"
    if not entry.has("source"):
        entry["source"] = "hazard:" + String(entry["kind"])
    if not entry.has("telegraph"):
        entry["telegraph"] = float(entry.get("telegraph_remaining", 0.0))
    if not entry.has("telegraph_remaining"):
        entry["telegraph_remaining"] = float(entry["telegraph"])
    for key in ["radius", "duration"]:
        if not entry.has(key):
            entry[key] = 0.0
    if not entry.has("damage"):
        entry["damage"] = 0
    if not entry.has("hit"):
        entry["hit"] = {}
    if not entry.has("active_time"):
        entry["active_time"] = 0.0
    if not entry.has("activations"):
        entry["activations"] = 0
    return entry


static func is_active(entry: Dictionary) -> bool:
    return float(entry.get("telegraph_remaining", 0.0)) <= 0.0


## 0..1 progress of the telegraph (1 = about to land).
static func telegraph_ratio(entry: Dictionary) -> float:
    var total: float = float(entry.get("telegraph", 0.0))
    if total <= 0.0:
        return 1.0
    return clampf(1.0 - float(entry.get("telegraph_remaining", 0.0)) / total, 0.0, 1.0)


## True when `point` (with `radius`) overlaps the hazard circle.
static func overlaps(entry: Dictionary, point: Vector2, radius: float = 0.0) -> bool:
    return Vector2(entry["pos"]).distance_to(point) <= float(entry["radius"]) + radius


## Advances every entry by `delta` and removes expired ones (in place).
## `player` is {pos: Vector2, radius: float, invulnerable: bool};
## `foes` is the current room's enemy array (dictionaries with pos, radius).
## Returns the hits to apply, in a stable order:
##   {entry, target: "player" | <foe Dictionary>, damage: int, ticks: int}
## No HP or tick changes happen here; Combat.update_hazards applies them.
static func step(entries: Array, delta: float, player: Dictionary, foes: Array = []) -> Array[Dictionary]:
    var hits: Array[Dictionary] = []
    var index := 0
    while index < entries.size():
        var entry: Dictionary = normalize(entries[index])
        var was_active: bool = is_active(entry)
        if not was_active:
            entry["telegraph_remaining"] = float(entry["telegraph_remaining"]) - delta
            if not is_active(entry):
                index += 1
                continue
            entry["activations"] = 1
            entry["hit"] = {}
        else:
            entry["active_time"] = float(entry["active_time"]) + delta
            var interval: float = float(entry.get("interval", 0.0))
            if interval > 0.0 and float(entry["active_time"]) >= interval * float(entry["activations"]):
                entry["activations"] = int(entry["activations"]) + 1
                entry["hit"] = {}
        _collect_hits(entry, player, foes, hits)
        if float(entry["active_time"]) >= float(entry["duration"]) and was_active:
            entries.remove_at(index)
            continue
        if float(entry["duration"]) <= 0.0:
            entries.remove_at(index)
            continue
        index += 1
    return hits


static func _collect_hits(entry: Dictionary, player: Dictionary, foes: Array,
        hits: Array[Dictionary]) -> void:
    var seen: Dictionary = entry["hit"]
    if not seen.has("player") and not bool(player.get("invulnerable", false)) \
            and overlaps(entry, Vector2(player.get("pos", Vector2(-9999, -9999))),
                float(player.get("radius", 0.0))):
        seen["player"] = true
        if int(entry["damage"]) > 0 or int(entry.get("ticks", 0)) > 0:
            hits.append({"entry": entry, "target": "player", "damage": int(entry["damage"]),
                "ticks": int(entry.get("ticks", 0))})
    if not bool(entry.get("hits_enemies", false)) or int(entry["damage"]) <= 0:
        return
    for foe in foes:
        var key: String = "foe:" + String(foe.get("instance_id", str(foe.get("pos"))))
        if seen.has(key) or not overlaps(entry, Vector2(foe["pos"]), float(foe.get("radius", 0.0))):
            continue
        seen[key] = true
        hits.append({"entry": entry, "target": foe, "damage": int(entry["damage"]), "ticks": 0})


## Draws every entry on `canvas` (a CanvasItem already transformed to world
## pixels): a ground circle outline that fills up during the telegraph, then a
## solid flash while active. Call from a _draw() callback only.
static func draw_all(canvas: CanvasItem, entries: Array, font: Font = null) -> void:
    for entry in entries:
        draw_telegraph(canvas, entry, font)


static func draw_telegraph(canvas: CanvasItem, entry: Dictionary, font: Font = null) -> void:
    var center: Vector2 = entry["pos"]
    var radius: float = float(entry.get("radius", 8.0))
    var color: Color = entry.get("color", DEFAULT_COLOR)
    if is_active(entry):
        canvas.draw_circle(center, radius, Color(color, 0.75))
        canvas.draw_arc(center, radius, 0.0, TAU, 28, Color.WHITE, 1.5)
    else:
        var ratio: float = telegraph_ratio(entry)
        canvas.draw_circle(center, radius, Color(color, 0.12))
        canvas.draw_circle(center, radius * ratio, Color(color, 0.35))
        canvas.draw_arc(center, radius, 0.0, TAU, 28, Color(color, 0.9), 1.0)
    var label: String = String(entry.get("label", ""))
    if label != "" and font != null:
        canvas.draw_string(font, center + Vector2(-6, -radius - 3), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("#ff7b7b"))
