extends Node
## Autoload `Events`: the project-wide signal bus.
##
## Gameplay systems announce what happened here; UI, telemetry, audio and the
## feature teams subscribe instead of reaching into each other's nodes. Emitters
## never depend on who listens. Payloads use plain types (int, String, Vector2,
## Dictionary) so listeners stay decoupled from node classes.
##
## Conventions:
## - Signals are emitted *after* the state change they describe has been applied
##   to `RunState`, except `message`, which is purely presentational.
## - `owner` arguments are the String "player" or "enemy".
## - Never emit gameplay signals from `_draw` code.
## - Scripts that a `--script` test `preload`s cannot reference the `Events`
##   identifier at compile time (see tests/run_all.sh); tests use
##   `get_root().get_node("Events")` instead.

# --- Run and floor lifecycle -------------------------------------------------

## A new run began with this seed; `RunState` has already been reset.
signal run_started(seed: int)
## Floor `depth` (1-based) was generated. `floor` is the Generator dictionary
## (rooms, start_id, boss_id, exit_id, guild_id, seed).
signal floor_started(depth: int, floor: Dictionary)
## The player entered `room_id` of type `kind` ("start", "normal", "boss",
## "guild_hall", "exit"). `ledger_entry` is the CollapsePolicy.evaluate() result
## that paid for the transition (empty for the floor's start room).
## `first_visit` is true the first time this room is entered on this floor.
signal room_entered(room_id: int, kind: String, ledger_entry: Dictionary, first_visit: bool)
## Every enemy in `room_id` is dead. Emitted once, when the last one dies.
## Feature stub: loot/reward rules may hook here.
signal room_cleared(room_id: int)
## The collapse clock moved from `before` to `after` ticks. Only emitted when
## the value actually changes; `reason` is human readable.
signal ticks_changed(before: int, after: int, reason: String)
## The boss of the current floor died; the exit is now unlocked.
signal boss_defeated(definition_id: String)
## The player reached the exit of floor `depth`.
signal floor_cleared(depth: int)
## The run is over. `outcome` is "escaped", "collapsed" or "defeated";
## `summary` is RunState.summary().
signal run_ended(outcome: String, summary: Dictionary)

# --- Combat ------------------------------------------------------------------

## An enemy instance (enemy["instance_id"], e.g. "3_1") lost `amount` HP.
signal enemy_damaged(instance_id: String, amount: int, critical: bool)
## An enemy of type `definition_id` died at world `position`, worth `xp`.
## XP is awarded by Game in response to this signal.
signal enemy_killed(definition_id: String, xp: int, position: Vector2)
## The player lost `amount` HP. `source` describes the attacker or hazard.
signal player_damaged(amount: int, source: String)
## The player regained `amount` HP (after clamping to max HP).
signal player_healed(amount: int)
## Player HP reached zero. `cause` is the source of the killing blow.
signal player_died(cause: String)
## A projectile was spawned. `data` is the live projectile dictionary
## (pos, velocity, ttl, owner, die, bonus, attack_bonus).
signal projectile_fired(owner: String, data: Dictionary)
## A melee swing started at world `position` towards unit vector `direction`.
signal melee_swung(owner: String, position: Vector2, direction: Vector2)

# --- Progression -------------------------------------------------------------

## The player gained `amount` XP; `total` is the new cumulative XP.
signal xp_gained(amount: int, total: int)
## The player reached `level`; `pending_points` ability points are unspent.
signal level_up(level: int, pending_points: int)
## Ability scores changed (level-up allocation, future items/curses).
signal stats_changed(scores: Dictionary)
## Achievement `id` (data/achievements.json) was earned for the first time.
## Emitted by the Announcer (2G); it saves the profile and shows a toast.
signal achievement_unlocked(id: String)

# --- Feature-team stubs (declared now so teams can wire them in parallel) ----

## An item entered the inventory. Owned by the items team.
signal item_picked_up(item_id: String)
## An item or active effect was consumed. Owned by the items team.
signal item_used(item_id: String)
## The player learned a skill. Owned by the skills team.
signal skill_learned(skill_id: String)

# --- Presentation ------------------------------------------------------------

## Asks the dungeon-system announcer for a line. `trigger` is a key in
## data/announcer.json; `context` fills its {placeholders}. With no lines for
## `trigger`, context["text"] is shown verbatim (context "priority" 1-5 and
## "category" optional). Flavour only: terse gameplay status stays on `message`.
signal announcement_requested(trigger: String, context: Dictionary)
## A one-line status message for the HUD. `category` is one of "info",
## "combat", "progression", "collapse" or "outcome". The newest message wins.
signal message(text: String, category: String)


## Convenience wrapper so emitters read like prose.
func say(text: String, category: String = "info") -> void:
    message.emit(text, category)
