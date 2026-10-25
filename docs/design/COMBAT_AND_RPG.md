# Combat and RPG — rules v1

- **Status:** Proposed. The d20 core, six stats, XP/levels, level-up allocation and the basic melee and ranged attacks are **implemented**. Everything labelled *Proposed default* is the target for Wave 2D (feel), 2B (inventory) and 2F (skills).
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 1C and 1D
- **Decisions covered:** D-02 (aim input), D-07 (door lock), D-09 (inventory and resources), D-10 (companions), D-14 (melee ruleset)
- **Related:** [Game design](GAME_DESIGN.md) · [Enemy tiers](ENEMY_TIERS.md) · [Encounter rules](ENCOUNTER_RULES.md) · [Prototype spec](ROOM_ENEMY_RPG_PROTOTYPE.md) · [`rpg_rules.gd`](../../game/scripts/rpg_rules.gd)

Units: world pixels (px), where 16 px is one tile, and seconds (s). The room interior is 384×384 px.

## 1. Current prototype behaviour (main @ 9bb993d)

| Thing | Value | Source |
| --- | --- | --- |
| Player move speed | 105 px/s, 8-way keys, normalised diagonal | `prototype_rules.json` `player_speed` |
| Player collision radius | 5.5 px | `main.gd` `PLAYER_RADIUS` |
| Aim | Mouse, continuous, via the inverse layout transform. Facing snaps to 8 sprite directions | `main.gd` |
| Ranged | Hold LMB. Cooldown 0.28 s; projectile 215 px/s, life 2.0 s (≈ 430 px); stopped by obstacle cells. Hit = d20 + DEX mod + proficiency vs AC; damage d6 + DEX mod | `_fire`, `_update_projectiles` |
| Melee | Hold Space. Cooldown 0.50 s. Hits every enemy within 32 px + its radius whose direction has a dot product > 0.45 with the aim (≈ ±63°). Resolves instantly, with no LOS check. d20 + STR mod + proficiency; d6 + STR mod | `_melee` |
| Melee visual | Arc of radius 30 px, ±0.7 rad (≈ ±40°), shown for 0.17 s. **Narrower than the hit cone** | `_draw_combat` |
| Player i-frames after being hit | 0.8 s | `_hit_player` |
| Crits | Natural 20 doubles the damage dice; natural 1 always misses | `rpg_rules.gd` |
| Enemy attacks | No wind-up. When the cooldown is 0, the target is in range and LOS is clear, a melee attack resolves instantly and a ranged attack spawns its projectile instantly. The initial cooldown is a random 0.2–0.8 s | `_update_enemies` |
| Enemy projectiles | Speed from data (spitting rat 117.5 px/s), life 2.8 s; `twin_shot` fires two at ±0.15 rad | `main.gd` |
| HP | 10 + CON mod at level 1; + max(1, 6 + CON mod) per level | `rpg_rules.gd` |
| AC | 10 + DEX mod (12 at start) | `rpg_rules.gd` |
| Level-up | 2 points per level, cap 20, a modal overlay that cannot be skipped | `character_menu.gd` |

Single-target DPS before hit chance: ranged ≈ 19.6 (5.5 / 0.28), melee ≈ 11 (5.5 / 0.50). **The prototype favours ranged by about 1.8×.** v1 fixes this in §4 and §5.

## 2. Input — D-02

**Proposed default (D-02):** mouse aim on desktop now, with right-stick aim added in Wave 3C. All gameplay input goes through Input Map actions (1A). No code may read raw keycodes.

| Action | Keyboard / mouse (now) | Gamepad (3C) |
| --- | --- | --- |
| `move_*` | WASD / arrows | Left stick (deadzone 0.2) |
| aim | Mouse position | Right stick (deadzone 0.25; keeps the last direction when released) |
| `attack_ranged` | LMB (hold repeats) | RT |
| `attack_melee` | RMB (hold repeats); alt **F** | RB |
| `dodge` | **Space**; alt Shift | A |
| `use_active` | Q | Y |
| `use_skill_1..2` (active skills, §11) | Z / X | LB / B |
| `use_consumable_1..6` | 1–6 | D-pad left/right cycles, D-pad down uses |
| `interact` (pick up, swap, shrine) | E | X |
| `open_map` | M; alt Tab | Back/View |
| `pause` | Esc | Start/Menu |

**Change from the prototype:** melee moves from Space to RMB, and Space becomes dodge. R and N (restart) are only available in debug builds and on the summary screen. F9 (grant XP) stays debug-only. Aim assist is off; an optional 8° magnetism setting is an open question for gamepad.

## 3. Movement, dodge and stamina

- **Move:** 105 px/s. Movement speed while attacking: arc 60 %, thrust 40 %, spin 50 %, ranged 85 %.
- **Dodge roll (Proposed default):** travels 48 px (3 tiles) over 0.25 s in the movement direction, or the aim direction when standing still.
  - **I-frames** for the first 0.20 s, then 0.10 s of recovery during which the crawler cannot dodge or attack.
  - Passes through enemies but not obstacles; it slides along walls.
  - A dodge can cancel attack *recovery* but not *wind-up* or *active* frames.
  - It cannot pass through a locked door.
- **Stamina pool:** 100, used only by dodge and skills, never by basic attacks.
  - Dodge costs 35.
  - Regeneration is 30/s after a 0.6 s delay since the last spend, with WIS scaling (§11).
  - Starting from full, the crawler can chain 2 dodges back to back, and a third dodge becomes available ≈ 0.75 s after the second.
- **Hit i-frames:** stay at 0.8 s after the crawler takes damage, and are shown as the existing white ring plus a sprite blink.

## 4. Melee — D-14

**Proposed default (D-14):** melee attacks are **directionally aimed, weapon-specific patterns** (arc, thrust, spin). Each swing has wind-up, active and recovery frames. A swing can hit several targets, applies knockback and is gated by its cooldown. Stamina is reserved for dodge and skills.

### 4.1 Patterns

| Field | **Arc** (blades, axes; starting weapon) | **Thrust** (spears, rapiers) | **Spin** (flails, heavy) |
| --- | --- | --- | --- |
| Hit shape | Sector centred on aim | Capsule along aim | Circle around the crawler |
| Reach | 30 px + target radius | 44 px long, 10 px wide | 26 px radius + target radius |
| Angle | 120° total (±60°) | — | 360° |
| Wind-up / active / recovery | 0.08 / 0.10 / 0.18 s | 0.12 / 0.08 / 0.20 s | 0.20 / 0.15 / 0.30 s |
| Cooldown (start to start) | 0.42 s | 0.55 s | 0.90 s |
| Max targets per swing | 3 (nearest first) | 2 (pierce, in order along the line) | unlimited |
| Knockback | 40 px, away from the crawler | 60 px, along the aim | 50 px, radial |
| Starting damage die | d8 + STR | d10 + STR | d8 + STR |
| Aim behaviour | Follows the aim until active begins | Locks at the start of wind-up | n/a |

### 4.2 Rules

- **Active frames:** during the active window, the hit shape is tested every physics tick against enemy circles. Each enemy can be hit at most **once per swing** (per-swing hit registry).
- **Line of sight:** a target only counts if the segment from the crawler to the target centre is not blocked by an obstacle cell. The same `has_line_of_sight` helper already serves enemies. This is new; the prototype ignores LOS.
- **Hold to repeat:** holding `attack_melee` swings again as soon as the cooldown allows. This matches the prototype.
- **Knockback:** an impulse applied over 0.12 s with linear decay. Obstacles stop it with no wall-slam damage in v1. It is scaled by the target's `knockback_resist` (0 = full, 1 = immune): chasers 0, tanks 0.75, elites +0.25, bosses 1. Knockback never pushes an actor through a door portal.
- **Visual = hitbox:** the drawn arc, line or circle must match the hit shape exactly. This fixes the prototype's mismatch between a ±40° drawing and a ±63° hit cone.
- **Balance target:** single-target melee DPS should be ≈ 1.1–1.3× ranged DPS at equal stats and tier, to pay for the risk. Multi-target and knockback are the melee identity.
- **Weapon data fields** (recommended names; the Wave 1B content schema is authoritative where it differs): `pattern`, `reach_px`, `arc_degrees`, `width_px`, `windup_s`, `active_s`, `recovery_s`, `cooldown_s`, `max_targets`, `knockback_px`, `damage_die`, `damage_bonus`, `scaling_stat`, `damage_type`, `on_hit_effects[]`.

## 5. Ranged attacks

- **Starting ranged weapon:** d6 + DEX, **cooldown 0.40 s** (prototype: 0.28 s), projectile 215 px/s, range 430 px (life 2.0 s), radius 2.5 px, pierce 0, spread 0.
- **Ranged weapon fields:** `projectile_speed`, `range_px`, `cooldown_s`, `count`, `spread_degrees`, `pierce`, `damage_die`, `damage_bonus`, `scaling_stat`, `damage_type`, `on_hit_effects[]`.
- **Collision:** projectiles are removed on obstacle cells (as implemented). Each projectile hits once, unless `pierce > 0`, in which case it can hit up to `pierce + 1` distinct targets.
- **Hostile projectile guardrails** (per band, [ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band)): maximum speed 140 / 160 / 180 / 200 / 230 px/s. Drawn radius ≥ 2.5 px with a contrasting outline. At most 12 hostile projectiles alive in the room at band I, rising to 24 at band V.
- **Dodging projectiles:** the crawler's 105 px/s lateral speed must always be enough to sidestep a single aimed shot fired from ≥ 120 px. That is why a projectile's band cap is no more than about 2.2× the crawler's speed.

## 6. Hit resolution and damage pipeline

The pipeline is a pure function in `combat.gd` (1A). Every step adds a line to a `breakdown` array that is emitted with `Events.damage_dealt(source, target, amount, breakdown)` so that the floating numbers, telemetry and announcer can read it.

1. **Base: attack roll.** Roll d20 + attack bonus (ability mod + proficiency + weapon to-hit) against the target's AC. A natural 1 always misses and a natural 20 is a critical. On a miss, show `MISS` and stop; no knockback is applied. On a hit, roll the weapon dice (doubled on a critical).
2. **Weapon:** add the scaling-stat modifier and the weapon's flat `damage_bonus`, and tag the damage type (`physical`, `fire`, `cold`, `poison`, `arcane`).
3. **Passives:** add the attacker's flat bonuses first, then multiply by `(1 + Σ percentage bonuses)`. Percentages are summed, not multiplied.
4. **Statuses:** apply the attacker's outgoing modifiers (Weakened ×0.75), then the target's incoming ones (Vulnerable ×1.25, Marked +2 flat).
5. **Armour:** subtract the target's flat damage reduction (DR). DR can never reduce a hit below 1. Then apply the type multiplier: resist ×0.5, weak ×1.5, immune ×0.
6. **Finalise:** round down. The minimum is 1 on a hit, unless the target is immune. Apply the damage, then on-hit effects, then knockback.

AC decides **whether** a hit lands, and armour DR decides **how much** gets through. Both exist on purpose. Status ticks (bleed, poison, burn) skip steps 1–3 and use only 4–6.

## 7. Status effects

| Status | Effect | Duration | Stacking | Notes |
| --- | --- | --- | --- | --- |
| Bleed | 1 dmg / 1.0 s | 4 s | stacks to 3 (each stack ticks separately) | physical; new stacks refresh the duration |
| Poison | 1 dmg / 1.5 s; healing −50 % | 6 s | refresh, no stacks | |
| Burn | 2 dmg / 1.0 s | 3 s | refresh | water hazard tiles cleanse it |
| Chill | move speed −30 % | 3 s | refresh; 3 applications in 4 s → Frozen | |
| Frozen | cannot act | 1.0 s | then 4 s immune | bosses immune |
| Stun | cannot act | 0.6 s | diminishing: 2nd application within 5 s at 50 %, 3rd immune | elites at 50 %; bosses immune |
| Root | cannot move, can attack | 1.5 s | refresh | |
| Weakened | outgoing damage ×0.75 | 5 s | refresh | |
| Vulnerable | incoming damage ×1.25 | 4 s | refresh | |
| Marked | +2 flat incoming damage | 6 s | refresh | |
| Haste (buff) | move +20 %, cooldowns −10 % | 5 s | refresh | |
| Shielded (buff) | absorbs N damage before HP | until broken or 8 s | the highest N wins | |
| Regen (buff) | +1 HP / 1.0 s | 5 s | refresh | |

General rules: at most 6 distinct statuses per actor. The status's applier decides its magnitude. WIS reduces the duration of harmful statuses on the crawler by 10 % per positive modifier, to a minimum of 50 %. The status icon row sits above the actor's HP bar.

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

- **Keep the d20 core:** six abilities, modifier = floor((score − 10) / 2), proficiency +2 rising every 4 levels, 5e-style cumulative XP thresholds, HP 10 + CON mod plus max(1, 6 + CON mod) per level. All of this is implemented.
- **Level-up (Proposed default):** **2 free stat points** (implemented, cap 20), **plus one skill pick**. The skill pick offers 3 random skills whose prerequisites are met, and the player takes one. Each skill can be taken up to 3 ranks. There is no reroll in the slice. Points are allocated first, then the skill is picked, in the same overlay (2F).
- **What each ability does** (INT, WIS and CHA are "reserved" in the prototype UI and are activated here):

  | Ability | Effect |
  | --- | --- |
  | STR | Melee to-hit and damage; +5 % knockback per positive mod |
  | DEX | Ranged to-hit and damage; AC |
  | CON | HP |
  | INT | Skill damage and magnitude +10 % per positive mod |
  | WIS | Stamina regen +10 % per positive mod; shorter harmful statuses (§7) |
  | CHA | Guild-hall prices −10 % per positive mod; boss loot box offers 4 choices at mod ≥ +3 |

- **Skills** are data records in the effect model from Wave 1B: trigger → condition → target → magnitude/duration → stacking → cooldown/cost. They come in two categories:
  - *active*: bound to slots on keys Z and X, cost stamina, 2 slots;
  - *passive*: always on.
  The slice needs 6 or more skills; the content data owns them.
- **Expected progression (guardrail):**

  | End of floor | 1 | 2 | 3 | 4 | 5 | 6 |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | Crawler level | 3 | 4 | 4–5 | 5 | 6 | 7 |
  | Max HP (CON 14 → 16) | ≈ 28 | ≈ 36 | ≈ 45 | ≈ 50 | ≈ 58 | ≈ 67 |

  The XP values that produce these levels are in [ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band).

## 12. D-09 — Inventory and resources

**Proposed default (D-09):** **1 melee + 1 ranged + 1 active item + unlimited passives + 6 consumable stack slots**, and a single **stamina** resource. Mana is deferred.

| Slot | Count | Rules |
| --- | ---: | --- |
| Melee weapon | 1 | Picking up another swaps it (with `interact`), and the old weapon drops where the crawler stands |
| Ranged weapon | 1 | Same swap rule |
| Active item | 1 | Swap rule. `cooldown_s` by default, or `charges_per_clear` (recharges on room clear) if the record says so. HUD shows a radial cooldown |
| Passives | unlimited | Picked up permanently. Duplicates stack only if the record allows it |
| Consumables | 6 slots | Each slot holds one item type with a stack of 3 (or the record's `max_stack`). When all slots are full, picking up a new type prompts a swap |
| Stamina | 100 | Dodge 35; skills 20–50; regen per §3 |

Picking up an item never pauses the game. Its tooltip appears at 1.5× scale while the crawler stands on it.

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
