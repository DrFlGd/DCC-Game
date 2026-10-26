# Combat and RPG — rules v1

- **Status:** Proposed. The d20 core, six stats, XP/levels, level-up allocation and the basic melee and ranged attacks are **implemented**. Wave 2D implemented §3 (dodge, stamina, movement penalties), the knockback step of §6, §8 (hit feedback) and §9 (D-07 door lock). Wave 2B implemented the weapon patterns (§4.1, §5), statuses on actors (§7), the item side of the damage pipeline (§6) and the D-09 inventory (§12). Wave 2F implemented §11 (skill points, learning rules, active skills, the `use_skill_*` actions and INT scaling). Each section lists its deviations.
- **Last updated:** 2026-10-26
- **Roadmap:** Phase 1C and 1D
- **Decisions covered:** D-02 (aim input), D-07 (door lock), D-09 (inventory and resources), D-10 (companions), D-14 (melee ruleset)
- **Related:** [Content rules (weapons, items, skills, effects, statuses)](CONTENT_RULES.md) · [Game design](GAME_DESIGN.md) · [Enemy tiers](ENEMY_TIERS.md) · [Encounter rules](ENCOUNTER_RULES.md) · [Prototype spec](ROOM_ENEMY_RPG_PROTOTYPE.md) · [`rpg_rules.gd`](../../game/scripts/rpg_rules.gd)

**Where this lives in code (Wave 1A architecture):**

- `player.gd` owns movement, aim and the attack and dodge timers.
- `combat.gd` owns projectiles, hit rolls, enemy attacks and the single damage entry point `apply_damage(target, amount, context)`.
- The `RunState` autoload (`core/run_state.gd`) holds HP, XP, level, ability scores, inventory, skills, the seeded `rng` and telemetry.
- The `Events` autoload (`core/events.gd`) carries the signals that items, skills, the HUD and the announcer react to: `enemy_damaged`, `enemy_killed`, `player_damaged`, `player_died`, `projectile_fired`, `melee_swung`, `xp_gained`, `level_up`, `item_used`, `skill_learned`.

New features hook into those signals or into `apply_damage`. They do not edit `game.gd`.

Units: world pixels (px), where 16 px is one tile, and seconds (s). The room interior is 384×384 px.

## 1. Current prototype behaviour

These values were in `main.gd` at main @ 9bb993d. The Wave 1A refactor moved them unchanged into `player.gd` and `combat.gd` constants.

| Thing | Value | Source (after 1A) |
| --- | --- | --- |
| Player move speed | 105 px/s, 8-way, normalised diagonal | `prototype_rules.json` `player_speed`; `player.gd` `DEFAULT_SPEED` |
| Player collision radius | 5.5 px | `player.gd` `RADIUS` |
| Aim | Mouse (or the right stick via the `aim_*` actions), continuous; facing snaps to 8 sprite directions | `player.gd` `aim_at` |
| Ranged | `fire` held (LMB). Cooldown 0.28 s; projectile 215 px/s, life 2.0 s (≈ 430 px); stopped by obstacle cells. Hit = d20 + DEX mod + proficiency vs AC; damage d6 + DEX mod | `player.gd` `FIRE_COOLDOWN`; `combat.gd` `PLAYER_SHOT_*` |
| Melee | `melee` held (Space). Cooldown 0.50 s. Hits every enemy within 32 px + its radius whose direction has a dot product > 0.45 with the aim (≈ ±63°, i.e. 127° total). Resolves instantly, with no LOS check. d20 + STR mod + proficiency; d6 + STR mod | `player.gd` `MELEE_COOLDOWN`; `combat.gd` `MELEE_REACH`, `MELEE_ARC_DOT` |
| Melee visual | Arc of radius 30 px, ±0.7 rad (≈ ±40°), shown for 0.17 s. **Narrower than the hit cone** | `room_renderer.gd`; `player.gd` `MELEE_FLASH` |
| Player i-frames after being hit | 0.8 s | `player.gd` `HIT_INVULNERABILITY` |
| Crits | Natural 20 doubles the damage dice; natural 1 always misses | `rpg_rules.gd` |
| Enemy attacks | No wind-up. When the cooldown is 0, the target is in range and LOS is clear, a melee attack resolves instantly and a ranged attack spawns its projectile instantly. The initial cooldown is a random 0.2–0.8 s | `combat.gd` |
| Enemy projectiles | Speed from data (spitting rat 117.5 px/s), life 2.8 s; `twin_shot` fires two at ±0.15 rad | `combat.gd` |
| HP | 10 + CON mod at level 1; + max(1, 6 + CON mod) per level | `rpg_rules.gd`, `RunState.sync_progression()` |
| AC | 10 + DEX mod (12 at start) | `rpg_rules.gd` |
| Level-up | 2 points per level, cap 20, a modal overlay that cannot be skipped | `character_menu.gd`; `game.gd` state `LEVEL_UP` |

Single-target DPS before hit chance: ranged ≈ 19.6 (5.5 / 0.28), melee ≈ 11 (5.5 / 0.50). **The prototype favours ranged by about 1.8×.** The Wave 1B starter weapons `wpn_nail_pistol` and `wpn_crowbar` reproduce these numbers on purpose, so that 2B can switch to data without changing the feel. §4.2 records the balance target for the retune that comes after.

## 2. Input — D-02

**Proposed default (D-02):** mouse aim on desktop, plus right-stick aim on gamepad. The Wave 1A Input Map already provides this: the `aim_*` actions use the right-stick axes. All gameplay input goes through Input Map actions, and no code reads raw keycodes.

Rows marked *1A* are bound in `project.godot` today. Rows marked *proposed* are added by the feature PR that needs them.

| Action | Keyboard / mouse | Gamepad | Status |
| --- | --- | --- | --- |
| `move_up/down/left/right` | WASD / arrows | Left stick | 1A (the D-pad was removed in 2B and now drives the belt) |
| `aim_up/down/left/right` | (mouse position) | Right stick | 1A |
| `fire` | LMB (hold repeats) | RT | 1A |
| `melee` | Space (hold repeats) | RB | 1A |
| `dodge` | Shift | B | 1A (bound; action implemented in 2D) |
| `use_item` (active item) | Q | LB | **2B** (live) |
| `swap_weapon` | Tab | Y | 1A (bound; reserved, see §12) |
| `interact` (pick up, shrine, service) | E | A | 1A; 2B adds weapon/active pickups, the loot box and the shop |
| `map` | M | Back/View | 1A (bound; full map in 2E) |
| `pause` | Esc | Start/Menu | 1A |
| `restart_seed` / `new_seed` / `debug_level_up` | R / N / F9 | — | 1A. Proposed: R and N only on the summary screen or in debug builds, to avoid accidental restarts |
| `use_skill_1`, `use_skill_2` (active skills, §11) | Z / X | LT / X | **2F** (live) |
| `use_consumable` (selected belt slot) | C | D-pad down | **2B** |
| `next_consumable` (cycle the belt) | V | D-pad right | **2B** |
| `toggle_log` | L | L3 | 2G |

*Implemented (2B), deviation:* one `use_consumable` action plus `next_consumable` instead of six `use_consumable_1..6` actions (number keys stay free for dialogs). The stick clicks were taken (L3 is `toggle_log`), so the belt uses the D-pad, which no longer duplicates the left stick for movement. *Implemented (2F):* `use_skill_1` is Z / LT (axis 4) and `use_skill_2` is X / gamepad X (button 2). Game polls both with a press-edge latch, so a held LT fires once per pull. Free gamepad inputs left: R3, D-pad up/left. `tests/inventory_test.gd` fails if two gameplay actions share a key or button; `tests/skills_test.gd` also checks axis directions.

Gamepad aim keeps the last direction when the stick is released (deadzone 0.25). Aim assist is off; an optional 8° magnetism setting is an open question.

## 3. Movement, dodge and stamina

**Implemented in Wave 2D** (`player.gd` dodge/dash state and attack phases, `RunState` stamina, `Game.try_dodge`, `Combat.player_move_multiplier`; tunables in `prototype_rules.json` `feel.stamina`, `feel.dodge`, `feel.attack_timing`, `feel.attack_move_multipliers`). Deviations:

- The roll follows an ease-out curve (fast start), covering exactly 48 px in 0.25 s.
- I-frames are a dedicated `player.dodge_iframes` timer that blocks every damage source, DoT included. Since the 2B merge, `Combat.on_player_dodged()` also applies the `evasive` status for the same window and fires `on_dodge`. ItemSystem mirrors any `evasive` status, such as one from an item, into `dodge_iframes`.
- The prototype melee and ranged attacks still resolve instantly, so they have no wind-up. Melee has 0.10 s active and 0.18 s recovery (arc defaults), and ranged has 0.28 s recovery, so holding `fire` keeps the 85 % speed. 2B's patterns call `player.begin_attack(pattern, windup, active, recovery)`.
- A dodge press is buffered for 0.12 s, so a press during recovery still fires.
- WIS scaling is +10 % regen per positive modifier, so the starting WIS 12 regenerates 33/s. The two-chain rule holds: the third dodge is ready 0.75 s after the second.
- The content stat `dodge_cooldown` is `player.dodge_gap` (from `feel.dodge.cooldown`, 0); the items team sets it from loadout modifiers.

- **Move:** 105 px/s. Movement speed while attacking: arc 60 %, thrust 40 %, spin 50 %, ranged 85 %.
- **Dodge roll (Proposed default, `dodge` action):** travels 48 px (3 tiles) over 0.25 s in the movement direction, or the aim direction when standing still.
  - **I-frames** for the first 0.20 s, implemented by applying the Wave 1B `evasive` status (`invulnerable` flag) for 0.20 s. Then 0.10 s of recovery during which the crawler cannot dodge or attack.
  - Passes through enemies but not obstacles; it slides along walls.
  - A dodge can cancel attack *recovery* but not *wind-up* or *active* frames.
  - It cannot pass through a locked door.
  - It fires the content trigger `on_dodge`, which the `skl_sidestep` skill uses.
- **Stamina pool:** 100, held in `RunState`. It is used only by dodge and skills (`stamina_cost` in `skills.json`), never by basic attacks.
  - Dodge costs 35.
  - Regeneration is 30/s after a 0.6 s delay since the last spend, with WIS scaling (§11).
  - Starting from full, the crawler can chain 2 dodges back to back, and a third dodge becomes available ≈ 0.75 s after the second.
  - The content stat `dodge_cooldown` (1B) adds a minimum gap between dodges, 0 by default.
- **Hit i-frames:** stay at 0.8 s after the crawler takes damage, and are shown as the existing white ring plus a sprite blink.

## 4. Melee — D-14

**Proposed default (D-14):** melee attacks are **directionally aimed, weapon-specific patterns** (arc, thrust, spin). Each swing has wind-up, active and recovery frames. A swing can hit several targets, applies knockback and is gated by its cooldown. Stamina is reserved for dodge and skills.

The shape numbers (reach, angle, cooldown, dice, knockback, pierce) come from each weapon record, as defined in [CONTENT_RULES.md §5](CONTENT_RULES.md#5-weapons-weaponsjson). This section adds the **timing and hit rules** that the records do not cover yet.

### 4.1 Patterns

| Rule | **Arc** (`wpn_crowbar`, `wpn_box_cutter`, `wpn_demolition_maul`) | **Thrust** (`wpn_mop_pike`) | **Spin** (`wpn_novelty_flail`) |
| --- | --- | --- | --- |
| Hit shape | Sector of radius `reach` + target radius, width `arc_degrees`, centred on aim | Capsule of length `reach` along aim, width 10 px (`arc_degrees` only sets the visual flare) | Circle of radius `reach` + target radius |
| Starter values | crowbar: 32 px, 127°, 0.50 s, d6, knockback 20 | pike: 48 px, 0.62 s, d8, knockback 25, pierce 2 | flail: 30 px, 360°, 0.90 s, d6+1, knockback 35 |
| Wind-up / active / recovery (proposed defaults) | 0.08 / 0.10 / 0.18 s | 0.12 / 0.08 / 0.20 s | 0.20 / 0.15 / 0.30 s |
| Targets per swing | every enemy in the sector, as in the prototype | 1 + `pierce`, in order along the line | every enemy in the circle |
| Knockback direction | away from the crawler | along the aim | radial |
| Aim behaviour | follows the aim until active begins | locks at the start of wind-up | n/a |

Proposed new optional weapon fields for 2B/2D (to be added to the content schema): `windup`, `active` and `recovery` in seconds. When absent, the defaults above apply. `cooldown` keeps its 1B meaning: the time from one swing start to the next.

*Implemented (2B):* the three hit shapes, targets per swing and knockback directions in the table (`Combat.melee_hits()`; thrust half-width 5 px plus the target radius; arc and spin keep the prototype's resolution order), read from `Loadout.attack_profile("melee")` with passives and statuses applied. The swing outline is drawn as the real shape (sector at `reach` with the weapon's `arc_degrees`, the thrust lane, the spin circle), which fixes the ±40° / ±63° mismatch. After the 2D merge, a swing calls `player.begin_attack(<weapon pattern>, 0, melee_active, melee_recovery)`, so the per-pattern movement penalty applies. The weapon's `knockback` (STR-scaled like 2D's default shove) goes in the damage context, and 2D's finalise step applies it. **Deviations:** hits still resolve on the press. There is no wind-up, the phase lengths come from `feel.attack_timing` rather than per-weapon data, and there is no per-swing LOS. `wpn_crowbar`'s 127° gives a dot threshold of 0.446 instead of 0.45.

### 4.2 Rules

- **Active frames:** during the active window, the hit shape is tested every physics tick against enemy circles. Each enemy can be hit at most **once per swing** (per-swing hit registry). Each hit fires the content trigger `on_hit` once per enemy.
- **Line of sight:** a target only counts if the segment from the crawler to the target centre is not blocked by an obstacle cell. The same `has_line_of_sight` helper already serves enemies. This is new; the prototype ignores LOS.
- **Hold to repeat:** holding `melee` swings again as soon as the cooldown allows. This matches the prototype.
- **Knockback:** the weapon's `knockback` (px) is applied as an impulse over 0.12 s with linear decay. Obstacles stop it with no wall-slam damage in v1. It is scaled by the target's `knockback_resist` (0 = full, 1 = immune): chasers 0, tanks 0.75, elites +0.25, bosses 1. Knockback never pushes an actor through a door portal.
- **Visual = hitbox:** the drawn arc, line or circle must match the hit shape exactly. This fixes the prototype's mismatch between a ±40° drawing and a ±63° hit cone.
- **Balance target (for the post-2B balance pass):** single-target melee DPS should be ≈ 1.1–1.3× ranged DPS at equal stats and rarity, to pay for the risk. Multi-target and knockback are the melee identity. Starting points for the retune, once playtested:
  - raise `wpn_crowbar` to d8 at 0.45 s; or
  - slow `wpn_nail_pistol` to 0.40 s.
  Record the result in `BALANCE_GUIDELINES.md` (Phase 3).

## 5. Ranged attacks

- **Starting ranged weapon:** `wpn_nail_pistol` reproduces the prototype: d6 + DEX, cooldown 0.28 s, 215 px/s, range 430 px, pierce 0. Projectile radius 2.5 px.
- **Patterns** (`attack_pattern`):
  - `single`;
  - `spread`: `projectile_count` shots fanned over `spread_degrees`;
  - `burst`: `burst_count` shots `burst_interval` apart, with jitter;
  - `beam`: a placeholder. Proposed: hitscan ticks every 0.1 s along `range`, blocked by obstacles.
  Each projectile rolls to hit separately (CONTENT_RULES §5).
- *Implemented (2B):* all four patterns, from `Loadout.attack_profile("ranged")`. `spread` fans `projectile_count` pellets evenly over `spread_degrees`; `burst` fires the first shot at once and queues the rest `burst_interval` apart (the staple rifle: 3 shots over 0.14 s), each jittered by ±`spread_degrees`/2 with `RunState.rng`; `beam` is one hitscan tick per trigger pull, so it ticks every `cooldown` (0.2 s for the laser pointer, not the proposed 0.1 s) while held, along `range`, stopped by obstacles, hitting 1 + `pierce` enemies nearest first. Pierce uses a per-projectile hit registry (`projectile["hit"]`). Extra projectiles from modifiers on a no-spread weapon fan 8° apart. Projectiles carry `pierce`, `knockback`, `effects`, `weapon_id` and `slot`; a projectile keeps the weapon that fired it for `on_hit`.
- **Collision:** projectiles are removed on obstacle cells (as implemented). Each projectile hits once, unless `pierce > 0`, in which case it can hit up to `pierce + 1` distinct targets.
- **Hostile projectile guardrails** (per band, [ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band)): maximum speed 140 / 160 / 180 / 200 / 230 px/s. Drawn radius ≥ 2.5 px with a contrasting outline. At most 12 hostile projectiles alive in the room at band I, rising to 24 at band V.
- **Dodging projectiles:** the crawler's 105 px/s lateral speed must always be enough to sidestep a single aimed shot fired from ≥ 120 px. That is why a projectile's band cap is no more than about 2.2× the crawler's speed.

## 6. Hit resolution and damage pipeline

Wave 1A made `combat.gd` `apply_damage(target, amount, context)` the **only** place that changes HP. It emits the existing signals `Events.enemy_damaged`, `enemy_killed`, `player_damaged` and `player_died`. Its doc comment reserves the space *before* the HP change for resistances, shields, statuses and on-hit triggers. All rolls use `RunState.rng` in a fixed order, which keeps runs deterministic. v1 fills the pipeline in this order:

| Step | Where | What |
| --- | --- | --- |
| 1. **Base:** attack roll | `combat.gd` `hit_enemy` / `hit_player` | Roll d20 + attack bonus (ability mod + proficiency + `attack_bonus` modifiers) against the target's AC. A natural roll ≥ `crit_threshold` (20 by default) is a critical; a natural 1 always misses. On a miss, show `MISS` and stop; no knockback is applied. On a hit, roll the weapon dice (doubled on a critical). |
| 2. **Weapon** | same | Add the ability modifier and the weapon's `damage_bonus`, and tag the damage type (`physical`, `fire`, `toxic`, `arcane`). |
| 3. **Passives** | `apply_damage`, via `effect_resolver.collect_modifiers` / `apply_stat_modifiers` | Apply the attacker's `damage_bonus`, `melee_damage_bonus` and `ranged_damage_bonus`. Stat order is fixed by 1B: every add, then every multiply, then set. |
| 4. **Statuses** | `apply_damage` | Apply the attacker's outgoing modifiers (proposed `weakened` ×0.75), then the target's incoming ones (proposed `vulnerable` ×1.25 and `marked` +2), then `damage_taken_mult`. |
| 5. **Armour** | `apply_damage` | Subtract flat damage reduction (enemy `dr`), but never below 1. Apply the type multiplier: resist ×0.5, weak ×1.5, immune ×0. Then the `shielded` pool absorbs damage before HP. |
| 6. **Finalise** | `apply_damage` | Round down. The minimum is 1 on a hit unless the target is immune. Change HP, emit the signals, then run `on_hit`, `on_kill` and `on_damage_taken` effects, then knockback. |

- **Knockback step — Implemented (2D)** in `Combat._apply_knockback`, after the signals and `_feedback()`, on a surviving target only. It reads `context.knockback` in px; a melee hit without one uses `feel.knockback.default_melee` (20 px), +5 % per positive STR mod. The direction is `context.direction`, otherwise away from `context.origin` or the crawler. Enemies go through `Enemies.apply_knockback`, which applies `knockback_resist`, stops at walls and interrupts interruptible wind-ups. Bosses take at most ×0.25 (`feel.knockback.boss_mult`, or `boss_knockback_mult` on the definition): the effective factor is min(1 − resist, cap). The crawler is pushed through `Enemies.push`. Enemy strike knockback now enters through `hit_player(..., extra)` and the same step. Deviations: the push is applied instantly rather than over 0.12 s. A wall slam deals no damage. A push stops at obstacles and at the room edge, so it can never carry an actor through a doorway, whether the door is locked or not.
- **Proposed `context` keys:** `critical`, `source` and `index` exist today. v1 adds `damage_type`, `slot` (`melee`/`ranged`), `attacker` and `breakdown`, an array of `{step, delta}` that floating numbers and telemetry can read.
- **AC vs armour:** AC decides **whether** a hit lands, and armour DR decides **how much** gets through. Both exist on purpose.
- **Status ticks and `damage` effects** (1B: auto-hit, no AC) enter at step 4 with `context.source = "status:<id>"` or `"effect:<id>"`.

*Implemented (2B + 2C):* step 1–2 in `hit_enemy` / `hit_player` with the weapon's numbers from `Loadout.attack_profile()` (step 3's passive damage and attack bonuses are already inside the profile, so they are not added again in `apply_damage`). Enemy side of `apply_damage`: phase-roar invulnerability, `Enemies.mitigate()` (resistances, front guard, DR, 2C), ward and shield pools (2C), then the `shielded` status (2B); after the HP change: `Events.enemy_damaged`, `on_hit` (only for player attacks, `source == "player"`), death, `room_cleared`, then `on_kill` (credited for `player`, `status:` and `effect:` sources). Player side: dodge i-frames (which `evasive` sets) ignore the hit, `damage_taken_mult`, `shielded` absorbs, HP changes (status ticks do not start the 0.8 s hit i-frames), then the context `status` is applied (enemy attacks and hazards such as spore puddles, firebombs and floods) and `on_damage_taken` fires. Context keys added by 2B: `weapon_id`, `knockback` (px; applied by 2D's finalise step), `direction` (`knockback_direction` is kept as an alias), `effects` (the weapon's effect ids), `status`, `triggers` (false suppresses item triggers), plus `effect`/`status`/`applied_by` on effect and DoT damage. **Not yet:** `weakened` / `vulnerable` / `marked` (not in the data), `crit_threshold`, and the `breakdown` array.

## 7. Status effects

**Implemented as data (Wave 1B, `effects.json`):** see [CONTENT_RULES.md §4](CONTENT_RULES.md#4-statuses) for the full stacking rules.

*Implemented on actors (2B, [`status_system.gd`](../../game/scripts/status_system.gd)):* the crawler's map is `RunState.statuses` and each enemy's is `enemy["statuses"]`; `ItemSystem` ticks both every frame through `EffectResolver.tick_statuses`. Periodic damage goes through `combat.apply_damage` (`source = "status:<id>"`, damage type from the status tag: fire, toxic, else physical, so enemy resistances and DR apply). `slowed` / `hasted` scale the crawler's speed and each enemy's `speed` for its AI step; `hasted` also shortens both attack cooldowns. `stunned` blocks the crawler's movement and attacks and puts an enemy's AI into its 2C `stunned` state (interrupting a wind-up). `shielded` absorbs before HP on both sides. `evasive` holds the crawler's dodge i-frames, and every dodge applies it for the i-frame window (then `on_dodge` fires). `concealed` places a decoy where it was used: enemies path to it and their strikes land on it (projectiles already fired can still hit). Every rule below is implemented except the proposed statuses themselves. Markers are coloured pips above HP bars (`room_renderer.gd` `draw_status_markers()`), and the HUD lists the crawler's statuses with their time left.

| Status | Behaviour (1B defaults) |
| --- | --- |
| `burning` | 2 × stacks damage / 1.0 s, 3 s, stacks to 3 |
| `poisoned` | 1 × stacks / 1.0 s, 5 s, stacks to 5 |
| `bleeding` | 1 × stacks / 0.5 s, 3 s, stacks to 5 |
| `slowed` | move speed × 0.6, 1.5 s, refresh |
| `stunned` | cannot act, 0.6 s, cannot be chained |
| `shielded` | absorbs a 6-damage pool, 5 s |
| `hasted` | move speed × 1.3, attack cooldowns × 0.85, 3 s |
| `evasive` | invulnerable, 0.3 s (dodge i-frames) |
| `concealed` | untargetable, 3 s (decoy) |

**Proposed additions** (for enemies and hazards in 2C/2E; add them to `effects.json` in the same format):

| Status | Effect | Default | Stacking |
| --- | --- | --- | --- |
| `vulnerable` | incoming damage × 1.25 | 4 s | refresh |
| `weakened` | outgoing damage × 0.75 | 5 s | refresh |
| `marked` | +2 flat incoming damage | 6 s | refresh |
| `rooted` | cannot move, can attack | 1.5 s | refresh |

**Rules on top of 1B:**

- **Bosses** are immune to `stunned` and `rooted`, and `slowed` lasts half as long on them.
- **Elites** take half the duration of `stunned`.
- Each actor carries at most 6 distinct statuses.
- WIS reduces the duration of harmful statuses on the crawler by 10 % per positive modifier, to a minimum of 50 %.
- **Hazards** apply statuses through the same `apply_status` path, with `source = "hazard:<id>"`.
- The status icon row sits above the actor's HP bar.

## 8. Hit feedback

| Cue | Default | Notes |
| --- | --- | --- |
| Hit-stop | 40 ms normal hit, 70 ms crit, 90 ms kill | global time-scale freeze; at most 120 ms of hit-stop within any 0.5 s window |
| Flash | target sprite goes white for 0.06 s | the crawler flashes red when hit |
| Damage numbers | float up 12 px over 0.6 s; white normal, yellow crit, grey `MISS`, red on the crawler, green heal | numbers within 0.1 s on the same target merge |
| Screen shake | crawler hit 2 px / 0.15 s, crit 1 px / 0.08 s, boss slam 4 px / 0.25 s | translation only, never rotation |
| Death burst | 6–10 pixel particles in the enemy palette, 0.3 s | |
| Room clear | doors-open sound + 0.4 s gold border pulse | |

Accessibility (3C): *Reduced flash* turns flashes into outlines, and *Screen shake* is a 0–100 % slider. Hit-stop stays on, because it carries timing information.

**Implemented in Wave 2D:** `scripts/fx.gd` holds the state (pure, no RNG). Combat owns `combat.fx` and calls `_feedback()` in the finalise step. Game freezes the simulation while `combat.hitstop` runs and simulates only the remainder of the frame that ends it. `room_renderer.gd` draws the cues in self-contained functions (`_draw_fx`, `_flash_modulation`, `_crawler_modulation`, `_draw_dodge_trail`, `feel_shake`). Values and deviations:

- **Hit-stop.** Only hits by the crawler stop time: 40 ms for a hit, 70 ms for a crit, 90 ms for a kill. A boss phase change gives 90 ms, the crawler being hit 50 ms, and a room clear 120 ms. Requests take the longest, not the sum, and stay within the 120 ms per 0.5 s budget; only the room clear is forced past it. DoT never stops time.
- **Flash.** 0.08 s. Enemies go HDR-white and the crawler red. The crawler also blinks during hit and dodge i-frames.
- **Damage numbers.** Gated by `settings.show_damage_numbers`. A crit is larger and yellow, `MISS` is grey, DoT (`source = "status:*"`) is small, the crawler's numbers are red and heals green. Numbers on one target merge within 0.1 s.
- **Shake.** Hits 0.6 px / 0.06 s, crits and kills 1 px / 0.08 s, crawler damage 2 px / 0.15 s, boss phase changes and grace start 4 px / 0.25 s. It is scaled by `settings.screen_shake` and added to the grace shake as a renderer offset.
- **Death bursts.** 8 squares, 0.3 s, in the elite tint (else bone, red for bosses).
- **Room clear.** The 120 ms hit-stop, a ~1.1 s "ROOM CLEAR" HUD banner with the gold border pulse, doors fading open over 0.5 s, and an announcer `room_cleared` line. There is no sound yet (audio is Wave 3).

## 9. D-07 — Door lock and room persistence

**Implemented in Wave 2D** (`scripts/door_lock.gd`, a child node of Game; tunables in `feel.door_lock`). The lock emits `Events.doors_locked(room_id)` and `doors_unlocked(room_id, reason)`, where `reason` is `cleared`, `grace` or `failsafe`. `_enter_neighbor` refuses while the doors are sealed, and the HUD prompt reads *Sealed until clear*. Sealed doors are drawn with a red tint, an iron bar and a gold lock, and they fade open. Deviations:

- **Inside.** The crawler counts as "inside" when it is ≥ 24 px from *every linked doorway*, not from every wall, so hugging a far wall cannot keep the doors open.
- **Grace.** The grace unlock always wins. If grace ends by stabilising while hostiles live, the doors seal again.
- **Failsafe path test.** It uses plain grid connectivity, which is the enemy pathfinder's fallback, from the crawler's cell to each hostile's cell or a cell next to it. It runs every 0.25 s while sealed.
- **Failsafe despawn.** It emits no `enemy_killed` and no `room_cleared`, so no XP, clear grant or achievement is awarded. A despawned boss still sets `boss_defeated`, so the floor cannot softlock. The despawn is logged with `push_warning` and the `failsafe_despawns` telemetry counter.

**Proposed default (D-07):** doors lock until the room is cleared in rooms that contain hostiles, and never in safe rooms.

- **Locking kinds:** `normal`, `elite`, `boss`, and `trap` when it contains non-trap hostiles. **Never-locking kinds:** `start`, `guild_hall`, `exit`, `treasure`, `shrine`.
- **When doors lock:** 0.5 s after entry, once the crawler is ≥ 24 px inside the room. This stops door-camping without trapping a player who steps straight back out.
- **Dormancy:** enemies are dormant for 0.6 s after entry. They neither move nor attack, and their wind-up starts after this.
- **Unlock:** when the last non-trap hostile dies. Summons count as hostiles until their summoner and they are all dead.
- **Grace period:** all doors unlock as soon as the clock reaches 0 ([COLLAPSE_SYSTEM.md §6](COLLAPSE_SYSTEM.md#6-zero-clock-outcome--d-05)).
- **Failsafe:** if, for 15 s, no remaining hostile has a navigation path to the crawler and no damage has been dealt in either direction, those hostiles despawn, with no XP. This is logged as a generator bug.
- **Persistence:** cleared rooms stay cleared for the floor, as implemented. Because of the lock, a fight is never half-finished on revisit, except when it was abandoned during grace. Dropped loot persists.

## 10. Enemy telegraph rule

**Implemented in Wave 2C** for every enemy attack (data fields `wind_up`, `recovery` and `telegraph` ∈ `arc | line | circle | dash`; see [ENEMY_TIERS.md §8](ENEMY_TIERS.md#8-data-schema-enemiesjson-schema_version-2-implemented)). Room-entry dormancy (§9) is implemented too; the door lock followed in Wave 2D.

**Rule:** every enemy attack has a visible wind-up of at least **0.35 s at band I**. Validation tests enforce the per-band minimum ([ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band)): 0.35 / 0.30 / 0.28 / 0.25 / 0.22 s for bands I–V. Boss heavy attacks and any area attack need **≥ 0.5 s** at every band.

- **Visible means two cues:** (1) the sprite tints or pulses (50 % blend to the attack colour), **and** (2) a shape cue that matches the hitbox:
  - melee: an arc or circle outline at reach;
  - ranged: a 1 px aim line;
  - charge: a lane rectangle;
  - area: a ground circle that fills up.
- **Direction lock:** melee attacks and charges track the crawler for the first 60 % of the wind-up, then lock. Ranged attacks lock their aim at 80 %.
- **Resolution at the end of the wind-up:** a melee attack checks its hitbox against the crawler's position *at that moment*. Stepping out of range or dodging makes it whiff. This replaces the prototype's instant range check.
- **Recovery:** ≥ 0.25 s after every attack, during which the enemy cannot attack again. This is the punish window.
- **Data:** each `attacks[]` entry gains `windup_s`, `recovery_s` and `telegraph` (`arc` | `circle` | `line` | `lane` | `area`).

## 11. RPG progression and skills

- **Keep the d20 core:** six abilities, modifier = floor((score − 10) / 2), proficiency +2 rising every 4 levels, 5e-style cumulative XP thresholds, HP 10 + CON mod plus max(1, 6 + CON mod) per level. All of this is implemented in `rpg_rules.gd`, and the state is held in `RunState`.
- **Level-up (implemented, Wave 2F):** **2 free stat points** (cap 20) **and 1 skill point** (`skills.points_per_level`), in the same overlay (`character_menu.gd` mode `level_up`, `skill_system.gd`).
  - The overlay lists **every** skill with its rank X/Y, kind, cost, description and the next rank's effects; a rank-up is enabled when `unlock_level ≤ level`, its prerequisites (skill *and* rank) are met, its rank is below `max_rank`, and its `cost` ≤ banked points. Everything else is greyed out with the reason (`SkillSystem.can_learn`).
  - **Confirm** needs every stat point staged and every skill point spent; **Save for later** banks the skill points instead (they are spent on the pause menu's **Skills** page). A player with nothing learnable can always confirm.
  - Skills follow the [CONTENT_RULES.md §6](CONTENT_RULES.md#6-items-itemsjson-and-skills-skillsjson) model: `cost`, `unlock_level`, `max_rank`, `prerequisites`, and ranks that replace each other (`RunState.skills` holds `{"id", "rank"}`; `Loadout.current()` carries only the current rank's effects).
  - A pick emits `Events.skill_learned(id, rank)`; ItemSystem recomputes passive stats in response. A use emits `Events.skill_used(id, rank)`. Telemetry counts `skills_learned` and `skills_used`.
  - **Deviation:** the overlay shows the whole tree instead of 3 rank-ups drawn with `RunState.rng` (the starter tree has 8 skills, so a draw would hide most of it, and keeping the RNG out of the menu leaves the combat dice untouched). Skill points persist across floors and reset per run. F9 (`debug_level_up`) grants the skill point too.
- **What each ability does** (INT, WIS and CHA are "reserved" in the prototype UI and are activated here):

  | Ability | Effect |
  | --- | --- |
  | STR | Melee to-hit and damage; +5 % knockback per positive mod |
  | DEX | Ranged to-hit and damage; AC |
  | CON | HP |
  | INT | Skill and effect magnitude +10 % per positive mod |
  | WIS | Stamina regen +10 % per positive mod; shorter harmful statuses (§7) |
  | CHA | Guild-hall prices −10 % per positive mod; +1 roll on the boss loot box at mod ≥ +3 |

- **Active skills** (`kind: active`, with `cooldown` and `stamina_cost`) are bound to 2 slots (`use_skill_1` Z / LT, `use_skill_2` X / gamepad X; `skills.slots`). Passive skills are always on. *Implemented (2F):* a newly learned active takes the first free slot; the Skills page rebinds them. Using one checks `blocks_actions` (stunned), the slot's cooldown and `RunState.spend_stamina(stamina_cost)`, then runs the current rank's `on_use` effects through `EffectRunner.fire_skill()`, starts the rank's `cooldown` (a rank may override it) and counts `skills_used`. Cooldowns tick only while RUNNING and clear at every floor start. `cooldown_reduction` with `stat: skills` shortens them (Panic Mode's kill refund) and `stat: dodge` shortens the dodge gap. `skl_sidestep` is also a 40 px / 0.18 s dash (`skills.dashes`), through `player.start_dash()` + `combat.on_player_dodged()`, so `on_dodge` fires and its `evasive` status doubles as the dash's i-frames. `skl_mandatory_hype` slows enemies within 80 px, hastes the crawler and (rank 2) shields for 5. The HUD shows both slots with a cooldown sweep and greys a slot whose stamina cost is not affordable.
- **INT scaling (implemented, 2F):** every skill effect carries `magnitude_mult` = 1 + `skills.int_magnitude_per_mod` (0.1) per positive INT modifier (`Loadout.skill_magnitude_mult`, applied by `EffectResolver.scale_magnitude` in `collect_modifiers`). `add`, `heal`, `damage`, `cooldown_reduction` and positive status magnitudes multiply; `multiply` operations scale their distance from 1 (×0.9 → ×0.88 at INT 14); `set` and `grant_ticks` never scale. Item effects are not scaled.
- **Expected progression (guardrail):**

  | End of floor | 1 | 2 | 3 | 4 | 5 | 6 |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | Crawler level | 3 | 4 | 4–5 | 5 | 6 | 7 |
  | Max HP (CON 14 → 16) | ≈ 28 | ≈ 36 | ≈ 45 | ≈ 50 | ≈ 58 | ≈ 67 |

  The XP values that produce these levels are in [ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band).

## 12. D-09 — Inventory and resources

**Proposed default (D-09):** **1 melee + 1 ranged + 1 active item + unlimited passives + 6 consumable stack slots**, and a single **stamina** resource. Mana is deferred. Inventory lives in `RunState.inventory`, and pickups emit `Events.item_picked_up` and `Events.item_used`. The item fields are defined in [CONTENT_RULES.md §6](CONTENT_RULES.md#6-items-itemsjson-and-skills-skillsjson).

| Slot | Count | Rules |
| --- | ---: | --- |
| Melee weapon | 1 | Picking up another swaps it (with `interact`), and the old weapon drops where the crawler stands |
| Ranged weapon | 1 | Same swap rule |
| Active item | 1 | Swap rule. Recharges by its `cooldown` and `cooldown_unit` (`seconds`, `rooms_cleared` or `floors`), with `charges` uses per recharge. Clock-touching actives never use `seconds` (1B rule). HUD shows the recharge |
| Passives | unlimited | Owned permanently; copies up to `stack_max` |
| Consumables | 6 slots | Each slot holds one item id, stacked to its `stack_max`. When all slots are full, picking up a new id prompts a swap |
| Stamina | 100 | Dodge 35; skills use their `stamina_cost`; regen per §3 |

- `swap_weapon` (bound in 1A) has no job under this default, because both weapon slots are always equipped. It is reserved for a possible spare-weapon slot (open question 8).
- Picking up an item never pauses the game. Its tooltip appears at 1.5× scale while the crawler stands on it.

**Implemented (Wave 2B), with deviations:**

- The inventory is the dictionary `RunState.inventory`, managed by `scripts/inventory.gd`: `melee`, `ranged`, `active` plus `active_state`, `passives` and `consumables` as `[{id, count}]` lists, the `selected` belt slot, `credits` and `effect_cooldowns`. Inventory changes emit `Events.inventory_changed`.
- Weapon and active swaps need `interact`. The old item drops at the crawler's feet as a pickup.
- Actives recharge in all three units (`seconds`, `rooms_cleared`, `floors`). `charges` is honoured, and the HUD shows a recharge arc.
- The belt holds 6 slots. `C` (D-pad down) uses the selected slot, and `V` (D-pad right) moves to the next one. When the belt is full, a new id waits on the floor until `interact` swaps it for the selected slot.
- Passives and consumables are collected on contact. Weapons, actives and loot boxes need `interact`.
- **Credits** are the run currency: they come from kills (XP × 0.1, minimum 1) and room clears, and are spent at the guild-hall `shop`.
- The HUD has a loadout panel (weapons, active, belt, credits, statuses) and the 1.5× floor tooltip. The pause menu has an Inventory page.
- Stamina is Wave 2D's pool (§3). A dodge also applies the `evasive` status for its i-frame window and fires loadout `on_dodge` effects.
- **Deviation:** `swap_weapon` stays unused.
- **Deviation:** a passive already at `stack_max` stays on the floor instead of being picked up.

## 13. Companions — D-10

**Status: prototype implemented behind `companion.enabled` (Wave 3E).** The flag in `game/data/prototype_rules.json` is `false` by default, so the vertical slice ships with no companion, as D-10 proposed. Developers turn it on with the flag or the F8 key (`debug_toggle_companion`, keyboard only, for the session). Code: `game/scripts/companion.gd` (node), `companion_ai.gd` (pure AI), `companions.gd` (loader and validator), `game/data/companions.json` (schema v1). Tests: `game/tests/companion_test.gd`.

The one companion is the **Scrap Hound** (`cmp_scrap_hound`), an original, scrappy dungeon-bred hound. It has 16 HP (+3 per crawler level above 1), AC 13 and a speed of 118 px/s, against the crawler's 105.

Rules as built:

- **Follow.** It stays within `follow_distance` (28 px) of the crawler. Beyond 1.8 × that, or after a fight, it returns at 1.35 × speed. It uses the obstacle collision the crawler uses (axis sliding), with a grid path when it has no line of sight.
- **Leash.** It teleports beside the crawler (behind the crawler's aim, on a free cell in line of sight) in three cases: on every room entry, when it is more than `leash_distance` (170 px) away, or when it has made no progress for `stuck_seconds` (1.5 s).
- **Target selection.** It considers living enemies within `engage_radius` (160 px) **of the crawler**, in this order:
  1. the crawler's last target (`Combat.last_player_target`, set by damage with source `"player"`);
  2. else its current target, kept until 32 px beyond the radius;
  3. else the enemy nearest the companion.
- **Independent attacks.** The bite uses the enemies.json v2 attack schema: melee, 14 px reach, 0.15 s wind-up, 0.9 s cooldown, 0.2 s recovery, d4 + DEX, proficiency from the crawler's level, 6 px knockback.
  - It rolls d20 against the enemy's AC and deals damage with the companion's **own RNG**, seeded `RunState.seed ^ depth` at each floor start. `RunState.rng` is never consumed.
  - Damage goes through `Combat.apply_damage(foe, n, {source: "companion"})`. XP, per-kill credits and the kill counters go to the crawler, and `companion_kills` telemetry counts the kill.
  - Item `on_hit` and `on_kill` triggers do **not** fire, and companion hits cause no hit-stop.
- **Survivability.**
  - **Retargeting** (`EnemySystem.update_companion_target`). Every non-boss enemy with a melee, dash or area attack may switch to the companion; `targets_companion` in a definition overrides this. The check runs while the enemy is idle, every `retarget_interval` (1 s). It switches when the companion is within `retarget_radius` (64 px), is nearer than the crawler, and a hash roll of (instance id, evaluation count, `seed ^ depth`) comes in under `retarget_chance` (0.3). The roll uses no RNG stream.
  - **Hits.** Enemy strikes on the companion and enemy bullets that touch it go through `Combat.hit_companion()` (d20 against its AC, companion RNG), then 0.4 s of i-frames.
  - **Downed.** At 0 HP it is downed: enemies return to the crawler, and the downed hound is carried along on room changes. It revives at 50 % HP after the crawler stands within 24 px for 2 s, or by itself after 25 s. Every floor start revives it at full HP.
- **Commands.** Hold `interact` for 0.4 s with no interaction prompt showing to toggle between **stay** and **follow**.
  - In **stay** it holds its position and only bites enemies already in reach.
  - A room entry resets it to follow.
- **Buffs.** While it is up, the crawler gets +1 to `pickup_radius` through `Loadout.player_stats()`.
- **Presentation.**
  - **Sprite:** a generated 24×24 placeholder with four facings and a downed frame, plus an HP bar, a wind-up arc and the revive ring.
  - **HUD:** an HP pip (PAL, STAY or DOWN).
  - **Events:** `companion_spawned`, `companion_downed`, `companion_revived` and `companion_killed_enemy`.
  - **Announcer:** original lines through `announcement_requested` with literal text, so `announcer.json` is unchanged.

Deviations from the earlier foundation notes:

- It is its own pure module (`companion_ai.gd`), not the enemy AI with `faction: "ally"`. It reuses that module's pathing, line of sight and attack schema, but follower behaviour shares little with the enemy state machine.
- When stuck it **teleports** beside the crawler after 1.5 s. The earlier note had it despawn after 5 s and respawn at the next room entry.
- It never blocks doors, the crawler's attacks never touch it (so there is no knockback from the crawler), and it costs no collapse ticks. All three hold.
- **Not built:**
  - statuses on the companion (`StatusSystem` targets stay `"player"` or an enemy);
  - ground hazards, puddles, death bursts and pulls hitting it;
  - enemy strikes cleaving both the crawler and the companion (a strike hits only its chosen target);
  - more than one companion;
  - equipment and skill interactions;
  - a settings or title-screen toggle (Wave 3C owns settings).

## 14. Open questions

1. Do d20 misses feel bad in real time? (Default: keep them. If a playtest shows frustration, try "glancing blows", where a miss by ≤ 3 deals half damage.)
2. Should stamina also gate sprinting? (Default: no sprint.)
3. Should melee be able to deflect projectiles (a timed active frame destroys an enemy projectile)? (Default: no in v1; candidate skill.)
4. Should wall-slam knockback deal damage? (Default: no; candidate passive.)
5. Should active items recharge by time or by room clear? (Default: time; content can opt into charges.)
6. Should gamepad aim assist ship? (Default: off; an 8° option is a later candidate.)
7. Should the level cap stay at 20 when the slice tops out at about 7? (Default: yes; no change needed.)
8. Should there be a spare weapon slot that `swap_weapon` cycles? (Default: no for the slice; keep the action reserved.)
