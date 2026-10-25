extends RefCounted
## Pure selection and scheduling for the dungeon-system announcer.
##
## No nodes and no autoloads: the Announcer node (scripts/ui/announcer.gd)
## feeds it trigger keys, a placeholder context and the current time in
## seconds, then draws whatever `on_screen` holds. Tests drive it directly.
##
## Selection (pick): weighted random over the trigger's eligible lines, with an
## RNG reseeded to `run_seed ^ event_counter` for every request, so the same
## run and the same sequence of events replays the same lines. A shown line
## puts its trigger on cooldown for that line's `cooldown_seconds`; a
## `once_per_run` line is not picked again until reset_run().
##
## Scheduling (enqueue/update): at most `max_visible` toasts; the queue is
## ordered by priority (FIFO within a priority). A toast is not shown within
## `rate_limit_seconds` of the previous one unless its priority is at least
## `bypass_priority`. When every slot is full, a queued toast with a higher
## priority than the weakest visible one replaces it once that one has been
## up for `min_on_screen_seconds`. While a modal is open nothing is shown:
## toasts below `bypass_priority` are dropped, the others wait. Queued toasts
## below `bypass_priority` go stale after `queue_ttl_seconds`.
const Lines = preload("res://scripts/core/announcer_lines.gd")

## trigger -> Array of line dictionaries (see announcer_lines.gd).
var lines: Dictionary = {}
## Settings merged over Lines.DEFAULT_SETTINGS.
var settings: Dictionary = {}
var run_seed := 0
## Requests made this run (pick() calls); part of the RNG seed.
var event_counter := 0
var modal := false
## Waiting toasts, highest priority first.
var queue: Array[Dictionary] = []
## Toasts currently displayed, oldest first.
var on_screen: Array[Dictionary] = []
## The newest `log_size` selected lines, oldest first (the system log panel).
var log_lines: Array[Dictionary] = []
## Increments whenever log_lines changes, so the UI can redraw lazily.
var log_version := 0
## Every entry selected this run, with its final status (for telemetry).
var history: Array[Dictionary] = []
var last_shown_at := -1.0e9
var _ready_at: Dictionary = {}
var _used: Dictionary = {}
var _next_id := 0
var _rng := RandomNumberGenerator.new()


func _init(data: Dictionary = {}) -> void:
    lines = data.get("lines", {})
    settings = Lines.settings_with_defaults(data.get("settings", {}))


## Forgets cooldowns, once-per-run marks, queued and visible toasts and the
## history; the log keeps scrolling across runs.
func reset_run(new_seed: int) -> void:
    run_seed = new_seed
    event_counter = 0
    _ready_at.clear()
    _used.clear()
    for entry in queue:
        entry["status"] = "cleared"
    for entry in on_screen:
        entry["status"] = "cleared"
    queue.clear()
    on_screen.clear()
    history.clear()
    last_shown_at = -1.0e9


func has_trigger(trigger: String) -> bool:
    return lines.has(trigger) and not (lines[trigger] as Array).is_empty()


## Picks a line for `trigger` and records it in the log and history, without
## queueing it. Returns {} if the trigger has no lines, is cooling down or has
## used up its once-per-run lines.
func pick(trigger: String, context: Dictionary, now: float) -> Dictionary:
    event_counter += 1
    if not has_trigger(trigger) or now < float(_ready_at.get(trigger, -1.0e9)):
        return {}
    var candidates: Array = lines[trigger]
    var eligible: Array[int] = []
    var total := 0.0
    for index in candidates.size():
        if not _used.has("%s#%d" % [trigger, index]):
            eligible.append(index)
            total += maxf(0.0, float(candidates[index].get("weight", 1.0)))
    if eligible.is_empty() or total <= 0.0:
        return {}
    _rng.seed = run_seed ^ event_counter
    var roll: float = _rng.randf() * total
    var chosen: int = eligible.back()
    for index in eligible:
        roll -= maxf(0.0, float(candidates[index].get("weight", 1.0)))
        if roll < 0.0:
            chosen = index
            break
    var line: Dictionary = candidates[chosen]
    _ready_at[trigger] = now + float(line.get("cooldown_seconds", 0.0))
    if bool(line.get("once_per_run", false)):
        _used["%s#%d" % [trigger, chosen]] = true
    var entry: Dictionary = _make_entry(trigger, Lines.resolve(String(line["text"]), context),
        int(line.get("priority", 1)), String(line.get("category", "flavour")), now)
    entry["line"] = chosen
    return entry


## pick() then enqueue(). Returns the entry ({} if nothing was picked).
func announce(trigger: String, context: Dictionary, now: float) -> Dictionary:
    var entry: Dictionary = pick(trigger, context, now)
    if not entry.is_empty():
        enqueue(entry, now)
    return entry


## Queues literal `text` (no line lookup, no cooldown). For other systems'
## one-off announcements.
func custom(text: String, priority: int, category: String, now: float,
        trigger: String = "custom") -> Dictionary:
    var entry: Dictionary = _make_entry(trigger, text, clampi(priority, 1, 5), category, now)
    enqueue(entry, now)
    return entry


## Adds `entry` to the queue (or drops it while a modal is open), then update().
func enqueue(entry: Dictionary, now: float) -> void:
    if modal and int(entry["priority"]) < _bypass():
        entry["status"] = "dropped_modal"
        return
    entry["status"] = "queued"
    var at: int = queue.size()
    for index in queue.size():
        if int(queue[index]["priority"]) < int(entry["priority"]):
            at = index
            break
    queue.insert(at, entry)
    _trim_queue()
    update(now)


## Opens or closes the modal gate. Opening hides every toast; priority >=
## bypass toasts that had been up for less than the minimum time are requeued.
func set_modal(open: bool, now: float) -> void:
    if open == modal:
        return
    modal = open
    if not open:
        update(now)
        return
    var survivors: Array[Dictionary] = []
    for entry in on_screen:
        var short: bool = now - float(entry["shown_at"]) < float(settings["min_on_screen_seconds"])
        if int(entry["priority"]) >= _bypass() and short:
            entry["status"] = "queued"
            survivors.append(entry)
        else:
            entry["status"] = "hidden_modal"
    on_screen.clear()
    var kept: Array[Dictionary] = []
    for entry in queue:
        if int(entry["priority"]) >= _bypass():
            kept.append(entry)
        else:
            entry["status"] = "dropped_modal"
    survivors.append_array(kept)
    queue = survivors


## Expires finished toasts, drops stale ones, and shows what the rules allow.
func update(now: float) -> void:
    var still: Array[Dictionary] = []
    for entry in on_screen:
        if now >= float(entry["expires_at"]):
            entry["status"] = "expired"
        else:
            still.append(entry)
    on_screen = still
    var fresh: Array[Dictionary] = []
    for entry in queue:
        if int(entry["priority"]) < _bypass() and \
                now - float(entry["created_at"]) > float(settings["queue_ttl_seconds"]):
            entry["status"] = "dropped_stale"
        else:
            fresh.append(entry)
    queue = fresh
    if modal:
        return
    while not queue.is_empty():
        var head: Dictionary = queue[0]
        var bypass: bool = int(head["priority"]) >= _bypass()
        if not bypass and now - last_shown_at < float(settings["rate_limit_seconds"]):
            break
        if on_screen.size() >= int(settings["max_visible"]):
            var victim: int = _preemptable(head, now)
            if victim < 0:
                break
            on_screen[victim]["status"] = "preempted"
            on_screen.remove_at(victim)
        queue.pop_front()
        head["status"] = "shown"
        head["shown_at"] = now
        head["expires_at"] = now + duration_for(String(head["text"]), settings)
        last_shown_at = now
        on_screen.append(head)


## Seconds a toast stays up: grows with length, clamped to the settings.
static func duration_for(text: String, config: Dictionary) -> float:
    var by_length: float = 1.0 + float(text.length()) * float(config.get("seconds_per_char", 0.04))
    return clampf(by_length, float(config.get("toast_seconds", 2.5)),
        float(config.get("toast_max_seconds", 5.0)))


## 0..1 opacity of a visible toast at `now` (fade in 0.15 s, fade out at the end).
func alpha_for(entry: Dictionary, now: float) -> float:
    var fade: float = maxf(0.01, float(settings["fade_seconds"]))
    var fade_in: float = clampf((now - float(entry.get("shown_at", now))) / 0.15, 0.0, 1.0)
    var fade_out: float = clampf((float(entry.get("expires_at", now)) - now) / fade, 0.0, 1.0)
    return minf(fade_in, fade_out)


func _make_entry(trigger: String, text: String, priority: int, category: String,
        now: float) -> Dictionary:
    _next_id += 1
    var entry := {
        "id": _next_id, "trigger": trigger, "text": text, "priority": priority,
        "category": category, "created_at": now, "shown_at": -1.0, "expires_at": -1.0,
        "status": "new", "counter": event_counter
    }
    history.append(entry)
    log_lines.append(entry)
    var limit: int = maxi(1, int(settings["log_size"]))
    while log_lines.size() > limit:
        log_lines.pop_front()
    log_version += 1
    return entry


## Index of the weakest visible toast `head` may replace, or -1.
func _preemptable(head: Dictionary, now: float) -> int:
    var weakest := -1
    for index in on_screen.size():
        var entry: Dictionary = on_screen[index]
        if weakest < 0 or int(entry["priority"]) < int(on_screen[weakest]["priority"]):
            weakest = index
    if weakest < 0 or int(on_screen[weakest]["priority"]) >= int(head["priority"]):
        return -1
    if now - float(on_screen[weakest]["shown_at"]) < float(settings["min_on_screen_seconds"]):
        return -1
    return weakest


## Keeps the queue within queue_size by dropping the lowest-priority, oldest
## entry below bypass priority; higher priorities are never dropped.
func _trim_queue() -> void:
    while queue.size() > int(settings["queue_size"]):
        var drop := -1
        for index in range(queue.size() - 1, -1, -1):
            if int(queue[index]["priority"]) >= _bypass():
                continue
            if drop < 0 or int(queue[index]["priority"]) <= int(queue[drop]["priority"]):
                drop = index
        if drop < 0:
            return
        queue[drop]["status"] = "dropped_overflow"
        queue.remove_at(drop)


func _bypass() -> int:
    return int(settings["bypass_priority"])
