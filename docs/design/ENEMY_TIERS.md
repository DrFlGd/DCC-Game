# Enemy Tiers — roles, bands and starter roster

- **Status:** **Implemented** (Wave 2C) in [`enemies.json`](../../game/data/enemies.json) schema v2 and [`enemy_system.gd`](../../game/scripts/enemy_system.gd), with the deviations listed in [§0](#0-implementation-status-wave-2c). The guardrails in §4 are enforced by `validate_catalogue()` at startup and in CI.
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 4 (taxonomy, tiers, roster)
- **Related:** [Content rules (statuses)](CONTENT_RULES.md#4-statuses) · [Encounter rules](ENCOUNTER_RULES.md) · [Combat and RPG](COMBAT_AND_RPG.md) · [Biomes](BIOMES_AND_TILESETS.md) · [Prototype spec](ROOM_ENEMY_RPG_PROTOTYPE.md)

Every enemy below is an **original design** (`adaptation_type: original`). The rat family already exists in the prototype. Names are working titles and do not refer to anything in the books. Units: px, s; the crawler moves at 105 px/s.

## 0. Implementation status (Wave 2C)

**Shipped roster** (base stats at the archetype's band; veteran scaling per §3 is applied at spawn):

| Id | Role | Band | Depths | Threat | HP / AC | Signature attack | Telegraph | XP |
| --- | --- | :---: | :---: | ---: | --- | --- | --- | ---: |
| `rat_scavenger` | chaser | I | 1–6 | 2 | 7 / 12 | bite d4, wind-up 0.35 | arc 100° | 25 |
| `spitting_rat` | ranged | I | 1–6 | 3 | 5 / 12 | twin spit d4 + 2 (toxic), 117.5 px/s, wind-up 0.45 | line | 50 |
| `hulking_rat` | tank (light) | I | 1–6 | 4 | 17 / 13 | hop-lunge 48 px dash (0.5) and claw d4 + 3 (0.40) | dash / arc 120° | 100 |
| `shellback_charger` | charger | II | 3–6 | 4 | 14 / 15 | ram: 120 px at 210 px/s, d8 + 2, 40 px knockback, wall stun 1.2 s (0.6) | dash | 90 |
| `spore_puffer` | zoner | II | 3–6 | 3 | 12 / 10 | spore burst: 32 px puddle, 2 dmg/s for 3 s, `poisoned` tag (0.6) | circle | 60 |
| `nest_mother` | summoner | II | 3–6 | 5 | 16 / 12 | squeal: 2 `rat_pup`, cap 4 alive (0.8) | circle | 120 |
| `bell_acolyte` | support | III | 5–6 | 4 | 10 / 13 | ward peal (ward 6 for 6 s) and mending toll (heal 4) in 80 px (0.6) | circle | 90 |
| `rubble_golem` | tank | III | 5–6 | 6 | 40 / 14, DR 2 | slam d10 + 3, radius 28, 40 px knockback (0.7) | circle | 150 |
| `lobber` (Cinder Lobber) | ranged (artillery) | III | 5–6 | 4 | 12 / 12 | firebomb d8 + 2 fire at the crawler's position, lands after 0.9 s (0.5) | circle | 100 |
| `rat_pup` | summon (chaser) | — | — | 0 | 3 / 10 | nip d3 (0.35) | arc 90° | 0 |
| `armored_brute` | boss | I | 1–2 (5–6 as Bulwark) | — | 42 / 15 (band III: 120) | maul d8 + 2 (0.5); phase 2 adds shoulder charge (0.7) | arc / dash | 250 |
| `sump_warden` | boss | II | 3–6 | — | 90 / 14 (band III: 140) | tide spray fan, flood pulse, drain call, undertow → slam | line / circle / arc | 450 |

**Elite modifiers:** `bulwark` (HP ×1.5 on top of elite HP, shield 8 that refills after 4 s without damage, knockback resist +0.25, AC +1, blue ring) and `volatile` (speed ×1.1; on death a 0.8 s telegraphed 32 px blast for 2d6 fire that also hits enemies, orange ring). Both add the elite base (HP ×1.75, damage ×1.15, XP ×2.5, threat ×2, name prefix).

**Deviations from the proposal below:**

- **Schema names** follow the Wave 2C brief: `boss: bool` instead of `rank`; `band` plus `min_depth`/`max_depth` instead of `min_band`/`max_band`; `wind_up`/`recovery` instead of `windup_s`/`recovery_s`; `resistances` instead of `resist`; telegraph shapes are `arc | line | circle | dash`. `biome_affinity {biome_id: weight}` landed in Wave 3B (optional per archetype; validated ≥ 0; see ENCOUNTER_RULES R11); `required_for_clear` is not implemented yet. See §8 for the shipped schema.
- **Not built in 2C:** the `dart_idol` trap actor, the band III spore lob, the `swift` and `splitting` modifiers, the shellback's frontal damage reduction while charging, and the `vulnerable` status after a wall hit (the charger is stunned; statuses on actors arrive with 2B). Status tags on attacks and hazards (`poisoned`, `burning`, `slowed`) are recorded but not applied until 2B adds actor statuses; hazards deal their flat damage now. Enemy puddles (spore burst, firebomb, flood pulse) and the volatile death burst are entries in the shared ground-hazard module [`hazards.gd`](../../game/scripts/hazards.gd) (kinds `puddle` and `volatile_burst`), spawned through `Combat.spawn_hazard(Hazards.make(...))`; enemy puddles add `status`, `damage_type` and an `interval` of the attack's `hazard.tick`.
- **Sump Warden simplifications:** Flood Pulse is a 56 px puddle centred on the crawler (1 damage per second for 6 s, tagged `slowed`) instead of a 12×12 quadrant; Drain Call summons at the four corner "drains"; Undertow pulls 32 px and chains into Slam; phase 3 swaps in a 7-shot spray and the `enrage` ability gives cooldowns ×0.8 and speed ×1.2 below 25 %.
- **Boss elites** (the depth 5–6 Bulwark brute) get the modifier's shield and resistances but not the elite HP/XP multipliers; their band HP comes from `hp_by_band`.
- **Guardrails** are validated at each archetype's base band. Veterans can fall slightly outside the XP-per-threat band (a band III rat scavenger earns 14 XP per point against a floor of 15).
- **Interrupts:** `Enemies.apply_knockback()` interrupts a wind-up whose attack is `interruptible` (the acolyte's casts); player weapons do not cause knockback yet.

## 1. Pre-2C roster (historical)

| Id | Role (v1) | Lvl | HP | AC | Speed | Attack | Cooldown | XP | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- |
| `rat_scavenger` | chaser | 1 | 7 | 12 | 43 | bite, melee, range 19, d4 + STR (+0) | 1.05 | 25 | chase, BFS |
| `spitting_rat` | ranged | 1 | 5 | 12 | 37 | spit, d4 + DEX (+2), 117.5 px/s, range 185 | 2.2 | 50 | kites at 105–136 px; `twin_shot` |
| `hulking_rat` | tank (light) | 2 | 17 | 13 | 28 | claw, melee, range 23, d6 + STR (+3) | 1.6 | 100 | `lunge`: speed ×1.35 within 72 px |
| `armored_brute` | boss | 3 | 42 | 15 | 31 | maul, melee, range 30, d8 + STR (+4) + 1 | 1.85 | 250 | the boss table adds 1 scavenger + 1 spitter |

**Observed issues the v1 rules fix (all fixed in Wave 2C):**

- No attack has a wind-up (see the telegraph rule in [COMBAT_AND_RPG.md §10](COMBAT_AND_RPG.md#10-enemy-telegraph-rule)).
- `twin_shot` aims at ±0.15 rad around the crawler. At the spitting rat's 105 px preferred range each shot passes about 16 px to the side, while the crawler's hit radius is 8.5 px. **A stationary crawler is never hit at that range.** v1 aims one shot directly at the crawler and leads the other by 0.25 rad in the crawler's direction of motion.
- Boss detection is hard-coded to the id `armored_brute` (`game.gd` `BOSS_DEFINITION` after Wave 1A). v1 adds a `rank` field (shipped as `boss: true`).
- The hulking rat's claw (max 9) and the brute's maul (max 13) exceed the band I damage guardrail (§4). Proposed retune: hulking claw d4 (max 7), brute `damage_bonus` −2 (max 10).

## 2. Role taxonomy

| Role | Job in a fight | Design rule | Expected counterplay |
| --- | --- | --- | --- |
| **Chaser** | Close the distance and pressure the crawler | Slower than the crawler (≤ 0.6× at band I); short reach | Kite, knock back, kill first in open rooms |
| **Ranged** | Punish standing still | Keeps a range band. Its shots must be dodgeable by moving sideways | Close the gap, use cover (obstacles block shots) |
| **Charger** | Punish lining up | Long telegraphed straight dash, then a vulnerable recovery | Sidestep late, bait it into obstacles |
| **Zoner** | Deny space | Stationary or slow; creates timed hazard areas | Fight outside its zone; strike between pulses |
| **Summoner** | Grow the fight over time | Summon cap; summons give 0 XP and die with the summoner | Dive the summoner |
| **Tank** | Absorb damage and hold space | High HP or DR, slow, knockback-resistant, has a weak side | Flank it, bait a slam, punish the recovery |
| **Support** | Buff allies | Weak alone; its wind-up can be interrupted | Focus it first; interrupt it |
| **Trap** | Room hazard actor | Fixed lane or area; not required to clear the room | Read the lane, time movement |
| **Elite** | Harder version of a normal enemy | Base archetype + modifier(s) (§6) | The base counter plus the modifier counter |
| **Miniboss** | Elite-room centrepiece (band IV+) | Single enemy with 2 attack patterns, no phases | Pattern learning |
| **Boss** | Floor objective | Phases, escorts, ≥ 0.5 s telegraphs on heavy attacks | Phase learning, positioning |

## 3. Bands and depths

Bands are design tiers, not claims about floors in the books. They are mapped to depths for the six-floor slice and beyond:

| Band | Name | Depths | New challenge (roadmap) | New roles introduced |
| --- | --- | --- | --- | --- |
| I | Introduction | 1–2 | One clear attack each, generous telegraphs | chaser, ranged, light tank, trap |
| II | Pressure | 3–4 | Mixed melee and ranged, positioning, basic statuses | charger, zoner, summoner |
| III | Synergy | 5–6 | Combinations, area denial, specialists | support, tank, artillery-ranged |
| IV | Punishment | 7–9 | Faster patterns, layered hazards, two elite modifiers | miniboss |
| V | Apex | 10+ | Multi-phase encounters everywhere | — |

**Veteran scaling** applies when an archetype appears above its `min_band`, for each band above it:

- HP ×1.25 (compounding);
- attack bonus +1;
- damage bonus +1;
- threat +1;
- XP ×1.5;
- telegraph = max(the archetype's wind-up × 0.9, the band minimum).

It never changes the attack pattern.

## 4. Stat guardrails per band

The guardrails apply to normal enemies at their band, after veteran scaling. **Reference crawler HP** is the expected max HP early in the band, from [COMBAT_AND_RPG.md §11](COMBAT_AND_RPG.md#11-rpg-progression-and-skills).

| Band | Ref. crawler HP | Enemy lvl | HP | AC | Atk bonus | Avg dmg / hit | Max non-crit hit | Min wind-up | Move speed | Hostile projectile max | XP per threat pt | Threat per enemy |
| :---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| I | 20 | 1–2 | 3–18 | 10–13 | +2…+5 | 2–6 | ≤ 7 | 0.35 s | 25–55 | 140 | 10–25 | 1–4 |
| II | 36 | 2–4 | 8–30 | 10–15 | +3…+6 | 3–8 | ≤ 12 | 0.30 s | 25–65 | 160 | 15–30 | 2–5 |
| III | 50 | 3–6 | 10–45 | 12–15 | +4…+7 | 4–10 | ≤ 17 | 0.28 s | 25–75 | 180 | 15–30 | 2–6 |
| IV | 70 | 5–9 | 20–70 | 13–16 | +5…+8 | 6–13 | ≤ 24 | 0.25 s | 30–85 | 200 | 20–40 | 3–8 |
| V | 95 | 8–13 | 35–110 | 14–17 | +7…+10 | 8–17 | ≤ 33 | 0.22 s | 30–95 | 230 | 30–50 | 4–10 |

**Further rules:**

- Elites: HP ×1.75, damage ×1.15.
- Bosses: max non-crit hit ≤ 50 % of the reference HP. Boss HP ranges: I 40–60, II 80–110, III 120–160.
- Only charges may exceed the crawler's speed, and only in a straight, telegraphed line (≤ 2.5× the crawler's speed).
- **Total incoming damage budget:** with every enemy of a standard room attacking on cooldown with no misses, the crawler must survive ≥ 6 s at the reference HP.

**XP pacing** (the target levels are 3 / 4 / 5 / 5 / 6 / 7 after floors 1–6): with about 9 / 9 / 11 / 12 / 14 / 15 combat rooms cleared and the [budget formula](ENCOUNTER_RULES.md#3-threat-budget-by-depth), an average of ≈ 16 XP per threat point in band I and ≈ 22 in bands II–III reaches those levels on the 5e-style thresholds.

## 5. Starter roster: normal archetypes

There are 10 archetypes: 9 normal ones plus a trap. The base stats are at `min_band`. *Loop* is the AI state cycle. All wind-ups meet §4.

| # | Id | Role | Band | Threat | HP / AC | Speed | Attack(s) | XP |
| ---: | --- | --- | :---: | ---: | --- | ---: | --- | ---: |
| 1 | `rat_scavenger` | chaser | I | 2 | 7 / 12 | 43 | bite d4, wind-up 0.35 | 25 |
| 2 | `spitting_rat` | ranged | I | 3 | 5 / 12 | 37 | twin spit d4 + 2, wind-up 0.45 | 50 |
| 3 | `hulking_rat` | tank (light) | I | 4 | 17 / 13 | 28 | claw d4 + 3, wind-up 0.40; hop-lunge | 100 |
| 4 | `shellback_charger` | charger | II | 4 | 14 / 15 | 32 (charge 210) | ram d8 + 2, wind-up 0.6 | 90 |
| 5 | `spore_puffer` | zoner | II | 3 | 12 / 10 | 0 | spore burst (`poisoned`), wind-up 0.6 | 60 |
| 6 | `nest_mother` | summoner | II | 5 | 16 / 12 | 30 | summons 2 `rat_pup`, wind-up 0.8 | 120 |
| 7 | `bell_acolyte` | support | III | 4 | 10 / 13 | 40 | ally Shield 6, wind-up 0.6 | 90 |
| 8 | `rubble_golem` | tank | III | 6 | 40 / 14, DR 2 | 26 | slam d10 + 3, wind-up 0.7 | 150 |
| 9 | `lobber` | ranged (artillery) | III | 4 | 12 / 12 | 34 | bomb d8 fire + `burning`, wind-up 0.5, flight 0.9 | 100 |
| 10 | `dart_idol` | trap | I–V | 2 | invulnerable (band II+ variant "cracked": 10 / 12) | 0 | dart d4, 140 px/s, wind-up 0.5 | 0 (cracked: 20) |
| — | `rat_pup` (summon) | chaser | — | 0 | 3 / 10 | 50 | nip d3, wind-up 0.35 | 0 |

### Behaviour loops, telegraphs and counterplay

1. **Rat scavenger:**
   - **Loop:** chase (BFS, repath 0.35 s) → within 19 px: bite wind-up 0.35 s (red tint, small arc) → resolve → 0.3 s recovery → cooldown 1.05 s.
   - **Counter:** kite it, knock it back, and kill it fast (7 HP).
2. **Spitting rat:**
   - **Loop:** kite to the 105–136 px band → wind-up 0.45 s (1 px aim line, violet glow; aim locks at 80 %) → two shots (one aimed, one leading by 0.25 rad) at 117.5 px/s → recovery 0.4 s → cooldown 2.2 s.
   - **Counter:** strafe against the lead direction, rush it, or put a pillar between you.
3. **Hulking rat:**
   - **Loop:** chase.
   - Within 72 px: **hop-lunge**, which replaces the old speed boost. Wind-up 0.5 s (crouch plus a 48 px lane), then a dash of 48 px at 2.5× speed, then a claw if it lands in reach.
   - Otherwise it claws with a 0.40 s wind-up.
   - **Counter:** sidestep the lane. It recovers for 0.6 s after a hop, which is the moment to punish it.
4. **Shellback charger:**
   - **Loop:** approach until it has LOS within 60–140 px → wind-up 0.6 s (scrapes the ground, 120 px lane rectangle; direction locks at 60 %) → charge 120 px at 210 px/s.
   - Hitting an obstacle or wall leaves it `stunned` and `vulnerable` (proposed status) for 1.2 s. Hitting the crawler deals d8 + 2 and 40 px of knockback.
   - **Counter:** sidestep late, and bait it into pillars. Its shell takes ×0.5 from the front 90° while it charges.
5. **Spore puffer:**
   - **Loop:** stationary. Every 4 s: swell wind-up 0.6 s (a yellow circle fills) → a spore cloud of radius 32 px around itself for 3 s (`poisoned` on contact).
   - Band III veterans also lob a spore at the crawler's position: a 16 px area telegraph for 0.7 s.
   - **Counter:** shoot it from outside 32 px, or melee it right after a burst.
6. **Nest mother:**
   - **Loop:** kite at about 120 px. Every 6 s: squeal wind-up 0.8 s (pulsing ring) → 2 pups appear next to her, with at most 4 alive. **The pups die when she dies.**
   - **Counter:** dive her; a spin attack clears pups.
7. **Bell acolyte:**
   - **Loop:** stays ≥ 90 px from the crawler, near allies. Every 5 s: ring wind-up 0.6 s (an expanding ripple ring of 80 px) → allies inside get `shielded` 6 for 6 s (band IV veterans give `hasted` instead). It has no attack of its own.
   - Any hit that causes knockback or a stun **interrupts** the ring.
   - **Counter:** kill it or interrupt it first.
8. **Rubble golem:**
   - **Loop:** slow chase. Within 28 px: slam wind-up 0.7 s (filled circle, radius 28) → d10 + 3 and 40 px of knockback → recovery 0.8 s.
   - Its front 120° takes ×0.5 from projectiles. Knockback resist 0.75; DR 2.
   - **Counter:** flank it, bait the slam, then punish the 0.8 s recovery.
9. **Lobber:**
   - **Loop:** kite at about 140 px, within 220 px. Every 3.0 s: arm-raise wind-up 0.5 s → lobs a bomb at the crawler's position at the moment of the throw. The ground circle (radius 22) appears at the throw, and the bomb lands 0.9 s later. It ignores LOS, because the lob arcs over obstacles.
   - **Counter:** keep moving and close the gap. It flees slowly (34 px/s).
10. **Dart idol:**
    - **Loop:** wall-mounted and facing into the room. Every 2.5 s: eye-glow wind-up 0.5 s plus a lane line across the room → one dart along the lane.
    - It is not required to clear the room. The "cracked" variant can be destroyed.
    - **Counter:** read the lane, and cross it between darts.

**New AI modes needed** (the validator currently accepts only `chase`, `kite` and `guard`): `charge`, `zone`, `summon`, `support`, `artillery`, `turret` and `boss_script`. Each needs code and a test; see the [prototype spec](ROOM_ENEMY_RPG_PROTOTYPE.md).

## 6. Elite modifiers

Base elite rules: HP ×1.75, damage ×1.15, XP ×2.5, threat ×2, a coloured outline and name prefix (for example "Volatile Rat Scavenger"), and a **guaranteed drop**. An elite has one modifier in bands II–III and up to two from band IV. Wind-ups never fall below the band minimum.

| Modifier | Effect | Telegraph / tell | Counter |
| --- | --- | --- | --- |
| **Volatile** (required) | On death, a 0.8 s pulse, then an explosion of radius 32 px for 2d6 that also hits enemies | Orange pulsing outline; a growing circle at death | Kill it at range, or dodge out; use it against groups |
| **Bulwark** (required) | HP ×1.5 on top of elite HP; `shielded` 8 that regenerates after 4 s without taking damage; knockback resist +0.25 | Blue outline; shield bubble | Sustained damage; don't let it rest |
| Swift (optional) | Move +25 %; cooldowns ×0.85 | Green outline, after-images | Keep spacing; dodge timing |
| Splitting (optional) | On death, splits into 2 non-elite copies at 40 % HP, worth 0 XP | Purple outline | Area damage, spin attacks |

## 7. Bosses

Both bosses are flagged `"boss": true` (implemented). Killing any boss-flagged enemy unseals the exit, replacing the id check. A phase change gives 1.0 s of invulnerability with a roar, plays the announcer line and clears hostile projectiles.

### 7.1 `armored_brute` (exists), band I, floors 1–2

- **Stats:** HP 42 (floor 2: ×1.25), AC 15, speed 31, radius 14, sprite 48×48.
- **Escort:** floor 1 has 1 scavenger + 1 spitting rat (current table). Floor 2 has 2 scavengers + 1 spitting rat.
- **Phase 1 (100–50 %):** chase. **Maul**: wind-up 0.5 s, a 120° arc outline at a reach of 30 px plus the target's radius, damage d8 + 2 (after the retune), recovery 0.6 s.
- **Phase 2 (< 50 %):** alternates Maul and **Shoulder Charge**: wind-up 0.7 s with a 96 px lane, then a charge at 200 px/s. Hitting a wall stuns it for 1.0 s and makes it `vulnerable`.
- **Counter:** stay outside 40 px between mauls, and bait the charge into pillars. The boss room keeps an open centre (24 obstacles, with clearance).

### 7.2 `sump_warden` (new), bands II–III, floors 3–6

- **Stats:** HP 90 (band II) / 140 (band III), AC 14, speed 24, radius 16, sprite 48×48, knockback-immune, `slowed`-immune.
- **Phase 1 (100–60 %):**
  - **Tide Spray** every 3 s: wind-up 0.5 s, then a fan of 5 projectiles over 60° at 130 px/s, d6 each. The gaps between projectiles are ≥ 14 px at 100 px range.
  - **Flood Pulse** every 9 s: wind-up 1.0 s, marking one 12×12-cell quadrant, which becomes shallow water (−25 % speed) for 6 s.
- **Phase 2 (60–25 %):**
  - Adds **Drain Call** every 8 s: wind-up 0.8 s, then 2 rat pups from the edge drains, with at most 4 alive.
  - Adds **Undertow**: a 0.8 s ring telegraph of radius 60 px, which pulls the crawler 32 px inward. Then a **Slam** (0.5 s wind-up, d10 + 3, arc 120°), then 0.8 s of recovery.
- **Phase 3 (< 25 %):** cooldowns ×0.8 (wind-ups unchanged); Tide Spray fires 7 projectiles.
- **Counter:** fight at mid range and dodge through the fan gaps, avoid the flooded quadrant, clear pups with area attacks, and punish the recovery after Slam.

**Boss pool by depth:**

| Depths | Boss |
| --- | --- |
| 1–2 | brute |
| 3–4 | sump warden (band II) |
| 5–6 | 50/50 sump warden (band III) or brute veteran (band III scaling + Bulwark) |

A third boss for floors 5–6 is an open question.

## 8. Data schema (`enemies.json`, schema_version 2, implemented)

Top level: `schema_version` (2), `sprite_sheets` (`id → {path, frame: [w, h], render: [w, h]}`), `bands` (`"1"…"5"` → the §4 guardrails), `encounters` (budgets, composition and spawn settings, see [ENCOUNTER_RULES.md](ENCOUNTER_RULES.md)), `elites` (`base` multipliers and `modifiers`) and `enemies`.

Per enemy:

| Field | Meaning |
| --- | --- |
| `name`, `level`, `hp`, `ac`, `xp`, `speed`, `collision_radius`, `scores` | as before |
| `role` | `chaser`, `ranged`, `charger`, `zoner`, `summoner`, `tank`, `support`, `elite`, `miniboss`, `boss` |
| `band`, `min_depth`, `max_depth` | base band (veteran scaling counts from it) and pool eligibility |
| `threat`, `weight`, `biome_affinity` | budget cost and pick weight; `biome_affinity {biome_id: multiplier}` (optional, 3B) scales the weight per biome; `summon_only: true` keeps an enemy out of the pool |
| `tags` | strings for content `target_tag` conditions (`beast`, `vermin`, `armored`, `construct`, `fungus`, `humanoid`, …); elites add `elite` and the modifier's tags |
| `boss` | data-driven boss flag: the exit unlocks when any `boss: true` enemy dies |
| `resistances` | multipliers by damage type (`physical`, `fire`, `toxic`, `arcane`) or status id (for 2B); 0 = immune |
| `knockback_resist` (0–1), `dr`, `front_guard {arc, multiplier, slot}` | defence |
| `hp_by_band`, `enrage_below` | boss HP per band; HP fraction where `enrage` applies |
| `sprite` | a `sprite_sheets` id or a `res://` path |
| `abilities[]` | `lunge`, `twin_shot`, `summon`, `dash`, `puddle`, `shield_allies`, `heal_allies`, `enrage` |
| `behavior` | `mode` (`chase`, `kite`, `guard`, `charge`, `zone`, `summon`, `support`), `pathfinding` (`grid_bfs`, `direct`, `stationary`), `preferred_distance`, `repath_seconds`, `detection_range`, `ally_radius` |
| `phases[]` (bosses only) | `{below, attacks[], announce}`; phase *i* applies below `below` × max HP |

Per attack: `id`, `type` (`melee`, `ranged`, `dash`, `area`, `puddle`, `summon`, `support`), `telegraph` (must match the type), `wind_up`, `recovery` (≥ 0.25 unless `then` chains a follow-up), `cooldown`, `range`, `min_range`, `ability`, `proficient`, `damage_die`, `damage_bonus`, `damage_type`, `knockback`, `requires_los` (default true), and type fields: `arc` (melee), `projectile_speed`/`count`/`spread` (ranged), `dash_distance`/`dash_speed`/`stun_on_wall` (dash), `aoe_radius`/`target` (`self` or `player`)/`pull` (area), `hazard {telegraph, duration, tick, damage, status}` (puddle), `summon {id, count, cap, at_edges}`, `effect`/`amount`/`duration`/`interruptible` (support), `then` and `follow_up_only`.

The validator rejects unknown roles, modes, pathfinding, abilities, attack types, telegraphs and resistance tags by name, and checks the §4 guardrails (wind-up minimum, ≥ 0.5 s for area and boss attacks, projectile speed, charge speed ≤ 2.5× the crawler, max non-crit hit, attack bonus, HP, AC, speed, threat and XP per threat point at the base band; boss HP and max hit ≤ 50 % of the reference HP).

## 9. Open questions

1. Should the rat family span every band through veteran scaling, or retire after band II? (Default: it may appear up to band III as filler at ≤ 30 % of a room's threat.)
2. Is a third boss needed for floors 5–6, so the slice doesn't repeat a boss? (Default: reuse with a veteran variant; a third boss is a 2C stretch goal.)
3. Should elites appear outside elite rooms? (Default: from band III, a 10 % chance per normal room, which upgrades one enemy.)
4. Should trap actors give XP when destroyed? (Default: the cracked variant gives 20; invulnerable idols give 0.)
5. Should enemy-on-enemy damage apply (Volatile, lobber bombs, hazards)? (Default: yes for explosions and hazards; projectiles never hit their own faction.)
