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
## "guild_hall", "exit", "treasure", "elite", "trap", "shrine"). `ledger_entry` is the CollapsePolicy.evaluate() result
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
## The player took the unsealed exit of floor `depth`. Emitted before the
## intermission opens, and also on the final floor right before
## run_ended("victory").
signal floor_cleared(depth: int)
## The run is over. `outcome` is "victory", "collapsed", "defeated" or
## "abandoned"; `summary` is RunState.summary() (its "cause" says why).
signal run_ended(outcome: String, summary: Dictionary)
## Game's state machine moved between states, named as in game.gd's State enum:
## "TITLE", "RUNNING", "LEVEL_UP", "PAUSED", "INTERMISSION", "SUMMARY".
## For UI, audio and the announcer to follow screens without polling Game.
signal game_state_changed(previous: String, current: String)

# --- Collapse clock and rooms (Wave 2E) ---------------------------------------

## The clock reached 0 through a non-exit event and a grace period of
## `seconds` began (10 s the first time on a floor, 5 s the second). Doors
## unlock, entries are free, debris falls. Emitted after RunState.grace is set.
signal grace_started(seconds: float)
## The grace period ended. `stabilised` is true when ticks were regained (the
## floor is safe again); false when it ended by hard collapse, the exit or
## death (RunState.grace.outcome says which).
signal grace_ended(stabilised: bool)
## A ground hazard was added to Combat.hazards. `data` is the live entry
## (hazards.gd shape: pos, radius, telegraph_remaining, damage, duration,
## source, kind, ...); mutate it only through the hazards module.
signal hazard_spawned(data: Dictionary)
## A treasure chest in `room_id` was opened and rolled `loot_ids` (content
## ids from the treasure_room loot table). Inventory is the items team's job.
signal chest_opened(room_id: int, loot_ids: Array)
## A shrine was used; `choice` is "stabilise" (+ticks) or "mend" (heal).
signal shrine_used(choice: String)
## The crawler rested at a guild hall (full heal, once per floor).
signal guild_rested()

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

## An item entered the inventory (scripts/inventory.gd, Wave 2B): a pickup,
## a purchase or a swap. Emitted after RunState.inventory changed.
signal item_picked_up(item_id: String)
## An active item or a consumable was used (its on_use effects already ran).
signal item_used(item_id: String)
## Content id `item_id` was placed on the floor as a pickup at world
## `position` (swap drops, loot drops, chest and loot-box contents) (2B).
signal item_dropped(item_id: String, position: Vector2)
## RunState.inventory changed in any way (slots, stacks, charges, credits).
## Passive stat modifiers are recomputed in response (2B).
signal inventory_changed()
## Credits moved by `amount` (negative when spent); `total` is the new balance (2B).
signal credits_changed(amount: int, total: int)
## A status was added to (`active` true) or removed from (`active` false) an
## actor. `target` is "player" or an enemy instance_id (2B, status_system.gd).
signal status_changed(target: String, status_id: String, active: bool)
## The boss loot box in `room_id` was opened and rolled `loot_ids` (the
## boss_kill table); the ids are placed as pickups at the crate (2B).
signal loot_box_opened(room_id: int, loot_ids: Array)
## The player learned a skill. Owned by the skills team.
signal skill_learned(skill_id: String)

# --- Presentation ------------------------------------------------------------

## Player settings changed and were saved. `settings` is Settings.to_dict()
## (resolution, fullscreen, master_volume, show_damage_numbers, screen_shake).
signal settings_changed(settings: Dictionary)

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
