# Combat and RPG — rules v1

- **Status:** Proposed. The d20 core, six stats, XP/levels, level-up allocation and the basic melee and ranged attacks are **implemented**. Everything labelled *Proposed default* is the target for Wave 2D (feel), 2B (inventory) and 2F (skills).
- **Last updated:** 2026-10-25
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
| Melee visual | Arc of radius 30 px, ±0.7 rad (≈ ±40°), shown for 0.17 s. **Narrower than the hit cone** | renderer; `player.gd` `MELEE_FLASH` |
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
| `move_up/down/left/right` | WASD / arrows | Left stick, D-pad | 1A |
| `aim_up/down/left/right` | (mouse position) | Right stick | 1A |
| `fire` | LMB (hold repeats) | RT | 1A |
| `melee` | Space (hold repeats) | RB | 1A |
| `dodge` | Shift | B | 1A (bound; action implemented in 2D) |
| `use_item` (active item) | Q | LB | 1A (bound) |
| `swap_weapon` | Tab | Y | 1A (bound; reserved, see §12) |
| `interact` (pick up, shrine, service) | E | A | 1A (bound) |
| `map` | M | Back/View | 1A (bound; full map in 2E) |
| `pause` | Esc | Start/Menu | 1A |
| `restart_seed` / `new_seed` / `debug_level_up` | R / N / F9 | — | 1A. Proposed: R and N only on the summary screen or in debug builds, to avoid accidental restarts |
| `use_skill_1`, `use_skill_2` (active skills, §11) | Z / X | LT / X | proposed (2F) |
| `use_consumable_1..6` | 1–6 | left-stick click uses the selected slot; right-stick click cycles slots | proposed (2B) |

Gamepad aim keeps the last direction when the stick is released (deadzone 0.25). Aim assist is off; an optional 8° magnetism setting is an open question.

## 3. Movement, dodge and stamina

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

- **Proposed `context` keys:** `critical`, `source` and `index` exist today. v1 adds `damage_type`, `slot` (`melee`/`ranged`), `attacker` and `breakdown`, an array of `{step, delta}` that floating numbers and telemetry can read.
- **AC vs armour:** AC decides **whether** a hit lands, and armour DR decides **how much** gets through. Both exist on purpose.
- **Status ticks and `damage` effects** (1B: auto-hit, no AC) enter at step 4 with `context.source = "status:<id>"` or `"effect:<id>"`.

## 7. Status effects

**Implemented as data (Wave 1B, `effects.json`):** see [CONTENT_RULES.md §4](CONTENT_RULES.md#4-statuses) for the full stacking rules. Actors do not carry a status map yet; 2B adds one.

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

## 9. D-07 — Door lock and room persistence

**Proposed default (D-07):** doors lock until the room is cleared in rooms that contain hostiles, and never in safe rooms.

- **Locking kinds:** `normal`, `elite`, `boss`, and `trap` when it contains non-trap hostiles. **Never-locking kinds:** `start`, `guild_hall`, `exit`, `treasure`, `shrine`.
- **When doors lock:** 0.5 s after entry, once the crawler is ≥ 24 px inside the room. This stops door-camping without trapping a player who steps straight back out.
- **Dormancy:** enemies are dormant for 0.6 s after entry. They neither move nor attack, and their wind-up starts after this.
- **Unlock:** when the last non-trap hostile dies. Summons count as hostiles until their summoner and they are all dead.
- **Grace period:** all doors unlock as soon as the clock reaches 0 ([COLLAPSE_SYSTEM.md §6](COLLAPSE_SYSTEM.md#6-zero-clock-outcome--d-05)).
- **Failsafe:** if, for 15 s, no remaining hostile has a navigation path to the crawler and no damage has been dealt in either direction, those hostiles despawn, with no XP. This is logged as a generator bug.
- **Persistence:** cleared rooms stay cleared for the floor, as implemented. Because of the lock, a fight is never half-finished on revisit, except when it was abandoned during grace. Dropped loot persists.

## 10. Enemy telegraph rule

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
- **Level-up (Proposed default):** **2 free stat points** (implemented, cap 20) **and 1 skill point**, in the same overlay (2F).
  - After the stats are confirmed, the overlay offers up to **3 eligible rank-ups** drawn with `RunState.rng`. A rank-up is eligible when `unlock_level ≤ level`, its prerequisites are met, its rank is below `max_rank`, and its `cost` ≤ banked points.
  - The player takes one, or banks the point. There is no reroll in the slice.
  - Skills follow the [CONTENT_RULES.md §6](CONTENT_RULES.md#6-items-itemsjson-and-skills-skillsjson) model: `cost`, `unlock_level`, `max_rank`, `prerequisites`, and ranks that replace each other.
  - A pick emits `Events.skill_learned`.
- **What each ability does** (INT, WIS and CHA are "reserved" in the prototype UI and are activated here):

  | Ability | Effect |
  | --- | --- |
  | STR | Melee to-hit and damage; +5 % knockback per positive mod |
  | DEX | Ranged to-hit and damage; AC |
  | CON | HP |
  | INT | Skill and effect magnitude +10 % per positive mod |
  | WIS | Stamina regen +10 % per positive mod; shorter harmful statuses (§7) |
  | CHA | Guild-hall prices −10 % per positive mod; +1 roll on the boss loot box at mod ≥ +3 |

- **Active skills** (`kind: active`, with `cooldown` and `stamina_cost`) are bound to 2 slots (`use_skill_1`, `use_skill_2`). Passive skills are always on.
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

## 13. Companions — D-10

**Proposed default (D-10):** no companions in the vertical slice. A single follower prototype goes behind a flag in Wave 3E. Foundations to keep now:

- Companions are actors that use the enemy AI module with `faction: "ally"`.
- Targeting picks the nearest hostile within 160 px of the crawler.
- They follow within 48 px.
- They never block doors.
- They are immune to knockback from the crawler.
- They do not consume collapse ticks.
- They despawn with no penalty if they cannot path for 5 s, and respawn at the next room entry.

## 14. Open questions

1. Do d20 misses feel bad in real time? (Default: keep them. If a playtest shows frustration, try "glancing blows", where a miss by ≤ 3 deals half damage.)
2. Should stamina also gate sprinting? (Default: no sprint.)
3. Should melee be able to deflect projectiles (a timed active frame destroys an enemy projectile)? (Default: no in v1; candidate skill.)
4. Should wall-slam knockback deal damage? (Default: no; candidate passive.)
5. Should active items recharge by time or by room clear? (Default: time; content can opt into charges.)
6. Should gamepad aim assist ship? (Default: off; an 8° option is a later candidate.)
7. Should the level cap stay at 20 when the slice tops out at about 7? (Default: yes; no change needed.)
8. Should there be a spare weapon slot that `swap_weapon` cycles? (Default: no for the slice; keep the action reserved.)
