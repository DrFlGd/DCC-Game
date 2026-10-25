# Content rules: weapons, items, skills, effects and loot

**Status:** Wave 1B content layer. Data, validators and pure rule modules exist and are tested. They are **not yet wired into gameplay**: the running prototype still uses the hard-coded shot and swing in `main.gd`. Integration happens in Wave 2B (weapons/effects in combat) and Wave 2F (items, skills, loot in the run loop).

All content is plain JSON under [`game/data/content/`](../../game/data/content/). You can add or rebalance content without touching GDScript, as long as you use the fields described here. When you run the content test, every file is checked against these rules.

| File | Holds |
| --- | --- |
| [`effects.json`](../../game/data/content/effects.json) | Stat vocabulary, status definitions, and every reusable **effect** record |
| [`weapons.json`](../../game/data/content/weapons.json) | Melee and ranged weapons |
| [`items.json`](../../game/data/content/items.json) | Active, passive and consumable items |
| [`skills.json`](../../game/data/content/skills.json) | Skill-point skills with ranks and prerequisites |
| [`loot_tables.json`](../../game/data/content/loot_tables.json) | Rarity curve by depth and drop tables by context |

| Module | Purpose |
| --- | --- |
| [`content_db.gd`](../../game/scripts/content/content_db.gd) | `load_all()`, `validate(db)`, lookups (`weapon`, `item`, `skill`, `effect`, `status`), `loadout()`, `attack_profile()` |
| [`effect_resolver.gd`](../../game/scripts/content/effect_resolver.gd) | `collect_modifiers`, `apply_stat_modifiers`, `apply_status`, `tick_statuses`, `evaluate_condition`, shields, cooldowns |
| [`loot_rules.gd`](../../game/scripts/content/loot_rules.gd) | `roll(db, table_id, seed, depth, room_id, salt)`: deterministic drops |
| [`content_test.gd`](../../game/tests/content_test.gd) | Validation, counts, stacking, ordering, expiry, conditions, cycles, loot determinism |

Run the checks from the repository root:

```sh
godot --headless --path game --script res://tests/content_test.gd
```

A problem is reported as `<id>: <what is wrong>`, for example `wpn_broken_spoon: unknown effect 'fx_missing_effect'` or `wpn_broken_spoon: damage_die=0 outside 1..20`.

---

## 1. Ids and naming

- Every record has an `id` in **snake_case**: lowercase letters, digits and single underscores.
- The prefix shows the record type:

| Prefix | Type | Example |
| --- | --- | --- |
| `wpn_` | weapon | `wpn_mop_pike` |
| `itm_` | item (active, passive or consumable) | `itm_spite_battery` |
| `skl_` | skill | `skl_open_wounds` |
| `fx_` | effect | `fx_bleed_on_hit_25` |

- Status ids have no prefix (`burning`, `slowed`).
- Ids must be unique within a file. Never rename a shipped id; add a new one instead, because ids will be stored in save files and loot history.
- Effect ids should describe what the effect does, not who owns it, so they can be reused: `fx_heal_on_kill_2`, not `fx_vampire_straw_effect`. Rank-specific skill effects are the exception (`fx_iron_gut_2`).
- Display text (`name`, `description`) is free text. Flavour must be **original**: a sardonic dungeon "System" voice, sponsors, loot boxes, audiences, achievements. Never use character names or lines from the books.

## 2. Rarity tiers

| Tier | Intended role | Earliest typical depth |
| --- | --- | --- |
| `common` | Baseline tools, cheap consumables, starter gear | 1 |
| `uncommon` | Build-defining but modest: first synergy pieces | 1 |
| `rare` | Strong synergy pieces, multiplicative effects | 2–3 |
| `epic` | Build capstones, unusual attack patterns | 4+ |
| `legendary` | Run-warping, build-agnostic; never required | 6+ |

`min_depth` on a record is a hard floor: below it, the record can never drop. The loot curve (section 7) controls how often each rarity appears at a given depth.

## 3. The effect model

Every gameplay rule on a weapon, item or skill is an **effect** record in `effects.json`. Records reference effects by id, so one effect can be shared ("25% bleed on hit" is defined once).

An effect reads as: **when** `trigger` fires, **if** `condition` holds, do `operation` to `target` with `magnitude` for `duration`, combining with copies by `stacking`, at most once per `cooldown`.

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | `fx_...` |
| `trigger` | yes | When it fires; see the trigger table |
| `condition` | no | Object of extra requirements, all of which must hold (AND) |
| `target` | yes | `self`, `target` (the enemy hit or killed), `enemies_in_radius`, `projectile` |
| `radius` | for `enemies_in_radius` | World pixels, 8..384 (one tile = 16px, a room = 384px) |
| `operation` | yes | What it does; see the operations table |
| `stat` | for stat operations | A key from the `stats` list in `effects.json` |
| `status` | for status operations | A status id |
| `apply` | for `spawn_projectile_modifier` | `add` (default) or `multiply` |
| `magnitude` | yes | The number the operation uses |
| `die` | no, heal/damage only | Adds 1d`die` to `magnitude` (rolled through `rpg_rules.gd`) |
| `duration` | yes | Seconds. `0` = permanent while equipped (passives) or instant. Must be > 0 for `apply_status` |
| `stacking` | yes | `refresh`, `ignore` or `stack_count:N` |
| `cooldown` | no | Seconds before the same source can fire this effect again (internal cooldown) |
| `interval` | for `periodic` | Seconds between firings |
| `description` | yes | One designer-readable sentence. UI tooltips will use it |

### Triggers

| Trigger | Fires when |
| --- | --- |
| `passive` | Always on while owned. Re-evaluated whenever stats are recomputed (conditions like low HP switch it on and off) |
| `on_hit` | Your attack hits an enemy (once per projectile or pellet, once per enemy hit by a swing) |
| `on_kill` | You kill an enemy |
| `on_damage_taken` | You lose HP (after shields) |
| `on_room_enter` | You enter a room (each entry) |
| `on_room_clear` | The last enemy in a room dies |
| `on_use` | You activate the item or skill, or drink the consumable |
| `on_dodge` | You perform a dodge (see `skl_sidestep`) |
| `on_level_up` | You gain a level |
| `periodic` | Every `interval` seconds while owned |

### Operations

| Operation | Uses | Effect |
| --- | --- | --- |
| `add` | `stat`, `magnitude` | Adds to a stat (negative values subtract) |
| `multiply` | `stat`, `magnitude` | Multiplies a stat. Must be in (0, 10]; `0.9` = 10% lower |
| `set` | `stat`, `magnitude` | Forces a stat to a value. **With `status` instead of `stat`, sets that status's stack count; `0` removes it (cleanse)** |
| `heal` | `magnitude`, optional `die` | Restores HP |
| `damage` | `magnitude`, optional `die` | Deals damage directly. **It auto-hits: no d20 roll and no AC** |
| `apply_status` | `status`, `duration`, `magnitude` | Applies a status; see section 4 |
| `grant_ticks` | `magnitude` (1..5, whole) | Adds ticks back to the collapse clock. Must target `self` |
| `spawn_projectile_modifier` | `stat` from `projectile_stats`, `apply`, `magnitude` | Changes projectiles you fire (pierce, count, speed, spread, range, knockback, damage) |
| `cooldown_reduction` | `stat` from `cooldown_keys`, `magnitude` (seconds) | Instantly takes seconds off running cooldowns: `melee`, `ranged`, `items`, `skills`, `dodge`, `all` |

**Stat order is fixed:** for any stat, all `add`s are applied first, then all `multiply`s, then `set` (the last `set` wins). So `+10` and `x2` on a base of 100 always gives 220, whatever the order of your items.

**Stats** (the `stats` list in `effects.json`): the six abilities `STR DEX CON INT WIS CHA`; `max_hp`, `ac`, `move_speed`; `attack_bonus` (to-hit); `damage_bonus`, `melee_damage_bonus`, `ranged_damage_bonus`; `melee_cooldown`, `ranged_cooldown` (seconds; multiply them by less than 1 to attack faster); `melee_reach`, `arc_degrees`, `projectile_speed`, `projectile_count`, `spread_degrees`, `pierce`, `knockback`, `range`; `crit_threshold` (natural roll needed to crit, 20 by default); `dodge_cooldown`, `damage_taken_mult`, `heal_mult`, `xp_mult`, `pickup_radius`. Some of these do nothing yet; see section 10. To add a new stat, add it to the list **and** ask for integration code: a stat name alone does not implement anything.

### Conditions

All keys are optional and are combined with AND. An unknown key fails validation, and at runtime it is treated as false.

| Key | Value | True when |
| --- | --- | --- |
| `chance` | 0 < p ≤ 1 | A seeded roll succeeds. It is rolled **last**, only if every other key passed |
| `hp_below_pct` / `hp_above_pct` | 0..100 | Your HP percentage is below or above the value |
| `slot` | `melee` / `ranged` | The triggering attack used that slot |
| `status_present` / `status_absent` | status id | The target has, or lacks, that status |
| `target_tag` / `weapon_tag` | string | The target or your weapon has that tag |
| `ticks_below` | 1..99 | The collapse clock has fewer ticks left than the value |
| `depth_at_least` | 1..99 | You are at least this deep |
| `room_kind` | string | You are in this room kind (`normal`, `boss`, `guild_hall`, ...) |
| `nearby_enemies_at_least` | 1..99 | At least this many enemies are close by (integration defines "close") |

Enemies do not have tags yet (`target_tag` will match nothing until Wave 2 adds them to `enemies.json`).

### Stacking

`stacking` controls two things:

1. **How many copies of the same effect id count.** `refresh` and `ignore` count once; `stack_count:N` counts up to N copies. Two Hazard Vests (`fx_ac_plus_1`, `stack_count:2`) give +2 AC, but a third adds nothing.
2. **How an applied status combines** with one already on the target (next section).

## 4. Statuses

Statuses are defined in `effects.json` under `statuses`. An `apply_status` effect names one and can override its duration, magnitude and stacking. An effect `magnitude` or `duration` of 0 means "use the status default".

| Status | Kind | Behaviour | Default stacking |
| --- | --- | --- | --- |
| `burning` | debuff | magnitude × stacks damage every 1.0s | `stack_count:3` |
| `poisoned` | debuff | magnitude × stacks damage every 1.0s, lasts longer | `stack_count:5` |
| `bleeding` | debuff | magnitude × stacks damage every 0.5s | `stack_count:5` |
| `slowed` | debuff | `move_speed` × 0.6 | `refresh` |
| `stunned` | debuff | Cannot move or attack (`blocks_actions`) | `ignore` (cannot be chained) |
| `shielded` | buff | magnitude is a pool of damage absorbed before HP; removed when empty | `refresh` |
| `hasted` | buff | `move_speed` × 1.3, both attack cooldowns × 0.85 | `refresh` |
| `evasive` | buff | Ignores hits (`invulnerable`; dodge i-frames) | `ignore` |
| `concealed` | buff | Enemies lose you and attack your decoy (`untargetable`) | `ignore` |

Stacking rules when the status is **already active**:

- `ignore`: nothing changes.
- `refresh`: remaining time becomes the longer of what is left and the new duration (a refresh never shortens a status). Magnitude becomes the larger of the two.
- `stack_count:N`: adds one stack, up to N, and refreshes as above. Damage per tick is magnitude × stacks.

Periodic ticks fire every `tick_interval`. A tick that lands exactly on expiry still fires, so a 3-second burn with a 1-second interval ticks 3 times. Status fields: `name`, `kind` (`buff`/`debuff`), `periodic` (`none`/`damage`/`heal`), `tick_interval`, `default_magnitude`, `default_duration`, `default_stacking`, `stat_modifiers` (a list of `{stat, operation, magnitude}`), `flags` (`blocks_actions`, `absorbs_damage`, `invulnerable`, `untargetable`), `tags`, `description`.

## 5. Weapons (`weapons.json`)

Weapons only change the inputs to the existing d20 rules in [`rpg_rules.gd`](../../game/scripts/rpg_rules.gd); they never bypass them:

- **To hit:** d20 + ability modifier + proficiency (+ `attack_bonus` modifiers) against the target's AC. A natural 20 crits and doubles the dice.
- **Damage:** 1d`damage_die` + ability modifier + `damage_bonus` (+ `damage_bonus` / `melee_damage_bonus` / `ranged_damage_bonus` modifiers), minimum 1.
- Multi-projectile weapons roll to hit and damage **per projectile**.

| Field | Melee | Ranged | Notes |
| --- | --- | --- | --- |
| `id`, `name`, `description`, `sprite`, `tags` | ✓ | ✓ | `sprite` is a placeholder path; no art is required yet |
| `slot` | `melee` | `ranged` | |
| `attack_pattern` | `arc`, `thrust`, `spin` | `single`, `spread`, `burst`, `beam` | `beam` is a placeholder (see section 10) |
| `damage_die` | ✓ | ✓ | Whole number 1..20 (normally 4/6/8/10/12) |
| `damage_bonus` | ✓ | ✓ | -5..10, added on top of the ability modifier |
| `ability` | ✓ | ✓ | `STR` or `DEX` |
| `cooldown` | ✓ | ✓ | Seconds between attacks, 0.05..5 |
| `reach` | ✓ | | Pixels from the player's centre, 8..96 (enemy radius is added at hit time) |
| `arc_degrees` | ✓ | | Full width of the swing, 1..360. 127° is the prototype's 0.45 dot-product test |
| `range` | | ✓ | Pixels travelled before the shot expires; lifetime = range ÷ speed |
| `projectile_speed` | | ✓ | Pixels per second, 40..600 (0 is allowed for beams) |
| `projectile_count` | | ✓ | Projectiles per shot, 1..12 |
| `spread_degrees` | | ✓ | Total fan angle for `spread`, or random jitter for `burst` |
| `burst_count`, `burst_interval` | | `burst` only | Shots per trigger pull, seconds between them |
| `knockback` | ✓ | ✓ | Push impulse in pixels, 0..200 |
| `pierce` | ✓ | ✓ | Extra enemies passed through (for thrusts: enemies in a line) |
| `rarity`, `min_depth` | ✓ | ✓ | |
| `effects` | ✓ | ✓ | Effect ids. Weapons may only use `passive`, `on_hit`, `on_kill` and `periodic` triggers |
| `adaptation_type` | ✓ | ✓ | `original` or `adapted`. `canon` requires a `source_reference` and is not used in the starter pool |
| `synergy_notes`, `value` | optional | optional | `value` is a placeholder shop price |

**Prototype baseline:** the current shot is 215 px/s, 0.28s, d6 DEX, 2s lifetime. The current swing is 32px reach, 0.5s, d6 STR, about a 127° arc. `wpn_nail_pistol` and `wpn_crowbar` reproduce these exactly, so Wave 2B can swap the hard-coded attacks for data without changing the feel. Every other weapon sits within about ×0.5–×2 of those numbers.

### Starter weapons

| Id | Pattern | Dice | Reach/range | Cooldown | Rarity | Identity |
| --- | --- | --- | --- | --- | --- | --- |
| `wpn_crowbar` | arc 127° | d6 STR | 32 | 0.50 | common | Baseline starter |
| `wpn_box_cutter` | arc 100° | d4 DEX | 26 | 0.36 | common | Fast blade, 25% bleed |
| `wpn_demolition_maul` | arc 160° | d10+1 STR | 36 | 0.85 | uncommon | Two-handed cleave, 10% stun, big knockback |
| `wpn_mop_pike` | thrust 40° | d8 STR | 48 | 0.62 | common | Reach, pierces 2 |
| `wpn_novelty_flail` | spin 360° | d6+1 STR | 30 | 0.90 | rare (depth 2) | All-around, 35% slow |
| `wpn_nail_pistol` | single | d6 DEX | 430 | 0.28 | common | Baseline starter |
| `wpn_confetti_scattergun` | spread 4×40° | d4 DEX | 170 | 0.80 | uncommon | Close-range shotgun |
| `wpn_siege_crossbow` | single | d10+2 DEX | 420 @150px/s | 1.10 | uncommon | Slow heavy bolt, pierces 2, slows |
| `wpn_staple_rifle` | burst 3 | d4 DEX | 320 | 0.75 | rare (depth 3) | Burst, 20% poison |
| `wpn_laser_pointer` | beam | d4 DEX | 200 | 0.20 | epic (depth 4) | Placeholder beam, 15% ignite |

## 6. Items (`items.json`) and skills (`skills.json`)

### Items

Items use the same metadata as weapons (`id`, `name`, `rarity`, `min_depth`, `effects`, `tags`, `sprite`, `description`, `adaptation_type`, `synergy_notes`, `value`), plus:

| Field | Meaning |
| --- | --- |
| `kind` | `active` (reusable, has a cooldown), `passive` (always on), `consumable` (used up) |
| `cooldown` | Actives: recharge amount, in `cooldown_unit`. Must be > 0 for actives |
| `cooldown_unit` | `seconds` (≤600), `rooms_cleared` (≤20) or `floors` (≤5). Anything that touches the collapse clock should recharge on rooms or floors, never on seconds, so standing still cannot farm it |
| `charges` | Uses per recharge (actives) or uses per item (consumables, normally 1) |
| `stack_max` | How many copies can be carried (consumables) or owned (passives) |
| `balance_flags` | Optional warnings for reviewers, e.g. `collapse_clock` |

Rules: actives need at least one `on_use` effect; consumable effects must **all** be `on_use`; passives may not have `on_use` effects.

Starter items: actives `itm_time_pouch`, `itm_floor_stomp`, `itm_fan_club_decoy`, `itm_safety_button`; passives `itm_hazard_vest`, `itm_knockoff_sneakers`, `itm_serrated_lanyard`, `itm_lighter_bandolier`, `itm_ricochet_wax`, `itm_spite_battery`, `itm_vampire_straw`, `itm_last_gasp_adrenaline`, `itm_sponsor_stopwatch`, `itm_golden_trophy`; consumables `itm_bandage_roll`, `itm_sponsored_medkit`, `itm_sketchy_antidote`, `itm_speed_draught`, `itm_tick_shard`, `itm_party_popper`.

### Skills

| Field | Meaning |
| --- | --- |
| `kind` | `active` (activated, has a cooldown) or `passive` |
| `max_rank` | 1..5 |
| `ranks` | Exactly `max_rank` entries. Each is `{ "effects": [...] }` and may override `cooldown`. A rank **replaces** the previous rank's effects; it does not add to them, so list everything the rank should do |
| `cost` | Skill points per rank, 1..5 |
| `unlock_level` | Character level needed to take rank 1 |
| `prerequisites` | List of `{ "skill": "skl_...", "rank": N }`. Cycles are rejected |
| `cooldown`, `stamina_cost` | Actives only. Stamina does not exist yet (section 10) |

Starter tree:

```
skl_iron_gut (L1) ──► skl_mandatory_hype (L3, active)
skl_brawler  (L1) ──► skl_open_wounds    (L3)
skl_steady_aim (L1, rank 2) ──► skl_arson_enthusiast (L4)
skl_sidestep (L2, active)       skl_panic_mode (L5)
```

## 7. Loot tables (`loot_tables.json`)

**`rarity_weights_by_depth`** is a list of bands. A floor uses the deepest band whose `min_depth` ≤ its depth. Bands must start at 1 and increase.

| From depth | common | uncommon | rare | epic | legendary |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 70 | 25 | 5 | 0 | 0 |
| 3 | 55 | 30 | 12 | 3 | 0 |
| 5 | 40 | 32 | 18 | 8 | 2 |
| 8 | 30 | 30 | 22 | 13 | 5 |

**`tables`** are keyed by context. All five contexts must exist: `room_normal_clear`, `treasure_room`, `boss_kill`, `guild_hall_shop`, `floor_start`.

| Field | Meaning |
| --- | --- |
| `rolls` | Number of drops attempted (0..10), or `{ "min": a, "max": b }` |
| `empty_chance` | 0..1 chance that each roll gives nothing |
| `unique` | When true (the default), no record drops twice from one roll of the table |
| `min_rarity`, `max_rarity` | Rarity window for this table |
| `rarity_multipliers` | Per-rarity multiplier on the depth curve (default 1) |
| `sources` | Where candidates come from: `{ "from": "weapons" or "items", "kind"?, "slot"?, "tag"?, "weight" }`. The first source a record matches sets its weight |
| `exclude` | Ids that never drop from this table (starter weapons, tick shards in normal rooms) |

Records can also carry an optional `loot_weight` (default 1) to make them rarer or more common within their rarity.

**How a roll works:** (1) roll `empty_chance`; (2) choose a rarity using depth curve × multiplier, among rarities that still have an eligible record; (3) choose a record of that rarity using its source weight × `loot_weight`. A record is eligible when its `min_depth` ≤ depth and it is not excluded or already dropped. The random seed is built from the table id, run seed, depth, room id and a salt, so the same inputs always give the same loot. Use a different salt for each separate roll in the same room (e.g. reroll buttons).

## 8. Adding a new item in 5 steps

1. **Write or reuse the effects.** Search `effects.json` for an effect that already does what you need. If none exists, add a record with a new `fx_` id and fill in `trigger`, `target`, `operation`, `magnitude`, `duration`, `stacking` and a one-line `description`.
2. **Add the item** to `items.json` with a new `itm_` id. Set `kind`, `rarity` and `min_depth`, list the effect ids in `effects`, and fill in `cooldown`/`cooldown_unit`/`charges`/`stack_max`, `tags`, a placeholder `sprite` path, original flavour `description`, `adaptation_type: "original"` and `synergy_notes`.
3. **Decide where it drops.** It joins any loot table whose `sources` match its kind and rarity automatically. Add it to a table's `exclude` list if it must not drop there.
4. **Flag risks.** If it touches the collapse clock, healing loops or something else likely to trivialise a floor, add `balance_flags` and say why in `synergy_notes`.
5. **Run the content test.** Fix every reported problem until the test passes. Starter-pool counts are asserted, so removing content can fail the test too.

Weapons and skills follow the same steps: effects first, then the record, then loot (weapons) or prerequisites (skills).

## 9. Builds and synergies

Each build is viable without any one specific item. Starter weapons, Sidestep and the common consumables are useful in every build.

| Build | Core pieces | How it plays | Watch for |
| --- | --- | --- | --- |
| **Bleeder** (DEX melee) | Box Cutter, Serrated Lanyard, Brawler → Open Wounds, Knockoff Running Shoes | Fast hits stack bleeding; Open Wounds adds damage against bleeding targets | Bleed stacks cap at 5 per target |
| **Juggernaut** (STR melee) | Demolition Maul or Novelty Flail, Hazard Vest, Spite Battery, Iron Gut → Mandatory Hype, Floor-Stomp | Stand in the crowd, cleave, punish hits | Spite Battery has a 2s internal cooldown |
| **Kiter** (DEX ranged) | Nail Pistol or Siege Crossbow, Ricochet Floor Wax, Steady Aim, Sidestep, Inflatable Fan Club | Pierce lines of enemies from range and keep moving | Pierce stacking on the crossbow (2 + 1 + 1) |
| **Arsonist** (DEX ranged) | Confetti Scattergun, Staple Rifle or Laser Pointer, Lighter-Fluid Bandolier, Steady Aim → Arson Enthusiast | Many projectiles mean many ignite rolls; kills spread fire | Scattergun pellets × ignite chance |
| **Clock-runner** (utility) | Borrowed Time Pouch, Sponsor's Stopwatch, Panic Mode, Speed Draught | Plays on the edge of the collapse clock | **Flagged** `collapse_clock`: see open questions |

Effects that touch the collapse clock (`grant_ticks`) are deliberately small (1–2 ticks), recharge on rooms rather than seconds, and are excluded from normal-room drops.

## 10. Not implemented yet

These are data and pure functions only. In particular:

- **No gameplay wiring.** `main.gd` does not read these files. Wave 2B replaces `_fire`/`_melee` with `ContentDB.attack_profile()` and runs `collect_modifiers` on hit, on kill, on damage taken and on use. Wave 2F adds the inventory, skill points, loot drops and the shop.
- **Attack patterns:** `thrust`, `spin`, `spread` and `burst` need integration code; `beam` is only a placeholder (proposed: short hitscan ticks).
- **Statuses on enemies and the player:** there is no status map on actors yet, and no status VFX or HUD icons.
- **Unused stats:** `knockback`, `crit_threshold`, `dodge_cooldown`, `damage_taken_mult`, `heal_mult`, `xp_mult` and `pickup_radius` have no consumers yet.
- **No stamina resource and no dodge action** exist yet (`stamina_cost`, `on_dodge`).
- **No currency.** `value` is a placeholder shop price.
- **No decoy actor.** `concealed` only marks the player as untargetable; the decoy entity belongs to integration.
- **Enemy tags** for `target_tag` do not exist.
- **Timed stat buffs** (stat operations with `duration > 0`) are not tracked by the resolver. The starter pool uses statuses for every temporary buff.
- **No art:** every `sprite` path is a placeholder; see [`assets/weapons/README.md`](../../game/assets/weapons/README.md).
- **Balance** is first-pass and untested in play. `BALANCE_GUIDELINES.md` (Phase 3) is still to be written.
