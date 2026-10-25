# Collapse System — clock v1

- **Status:** Proposed. The v0 per-room-type policy and door preview are **implemented** ([`collapse_policy.gd`](../../game/scripts/collapse_policy.gd), [`prototype_rules.json`](../../game/data/prototype_rules.json)). The v1 rules below are the target for Wave 2E.
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 1B, backlog task 2 ("specify collapse clock v0")
- **Decisions covered:** D-03 (charge rule), D-04 (unit and budget), D-05 (zero-clock outcome)
- **Related:** [Game design](GAME_DESIGN.md) · [Procedural generation](PROCEDURAL_GENERATION.md) · [Encounter rules](ENCOUNTER_RULES.md) · [ADR-001 tunability constraint](../decisions/ADR-001-engine-and-platform.md)

The collapse clock is the signature mechanic. It should tempt the player to explore *one more room* without ever punishing them for something they could not see. None of these values are claims about the books. They are tunable game defaults.

## 1. Principles

1. **No hidden costs.** The player sees every tick change before committing to it: the door preview for transitions, and a visible telegraph for in-room drains.
2. **Every floor is winnable by construction.** The budget is derived from the floor's mandatory route ([§4](#4-starting-budget-and-depth-scaling)), not rolled independently.
3. **Exploring must pay.** Side rooms hold most of the XP, loot and time sources. Hoarding ticks earns a little and never more than exploring would.
4. **Running out is dramatic, not instant.** A short grace period turns a mistake into a last dash ([§6](#6-zero-clock-outcome--d-05)).
5. **Everything is data.** Costs, grants, slack ratios and grace timings live in JSON. Behaviour lives in `collapse_policy.gd` and its successors.

## 2. Current prototype behaviour

- **Unit:** integer ticks. The clock only changes on room transitions; it never drains in real time. Pause and level-up overlays do not affect it.
- **Start:** `start_ticks` = 26 for a 22-room floor.
- **Charge:** `evaluate(before, kind, first_visit, room_id)` charges `first_entry_cost` on the first visit or `revisit_cost` on later visits, and adds `first_entry_grant` on the first visit only. The result is clamped at ≥ 0. Each call returns a ledger entry with `before`, `cost`, `grant`, `after`, `allowed`, `collapses` and `reason`, which is printed as `COLLAPSE LEDGER`.
- **Refusal:** `allowed` is false when `before < cost`. The transition is refused with the message *"Not enough collapse ticks for that doorway."*
- **Zero:** `collapses` is true when a paid transition leaves `after == 0`. The run ends at once with `collapsed`.
- **Door preview:** every linked door is labelled with the net change `grant − cost` (for example `E-2`, `S+3`). Guild-hall, boss and exit doors are tinted. The exit is tinted red until the boss dies.
- **Diagnostic:** `mandatory_budget_floor()` sums the first-entry net costs along the BFS routes start → boss → exit, plus 1. It is printed at run start and asserted to be > 0 in the smoke test. It is not enforced.

**Two prototype edge cases v1 removes:**

- *Exit collapse:* entering the exit with exactly its cost (1 tick) leaves `after == 0`. Because `collapses` is tested before the exit, the run is reported as **collapsed, not escaped**. The diagnostic's `+1` exists to cover this.
- *Soft-lock:* when every unvisited door costs more than the remaining ticks, transitions are refused but no fail state fires. Revisits are free, so the crawler can wander visited rooms forever. Only **R** or **N** ends the run.

## 3. Tick unit and triggers — D-03

**Proposed default (D-03):** a **tick** is an abstract integer unit. It is charged on the **first entry** to a room, and **revisits are free**. Room-type overrides and events can add or remove ticks. There is no real-time drain in v1.

| Trigger | v1 behaviour | Config key |
| --- | --- | --- |
| First entry | Charge `first_entry_cost`, then add `first_entry_grant` | `collapse.room_types.<kind>.*` |
| Revisit | Charge `revisit_cost` (default 0) | `collapse.default.revisit_cost` |
| Event: item, skill or shrine grant | `+n` ticks with ledger reason `source:<id>` | effect op `collapse.grant_ticks` |
| Event: in-room drain (trap plate, hazard) | `−n` ticks after a ≥ 0.5 s visible telegraph | effect op `collapse.drain_ticks` |
| Event: elite room cleared | `+1` tick (proposed) | `collapse.room_types.elite.clear_grant` |
| Event: room cleared (any) | `+clear_refund`, **default 0**, an experiment knob | `collapse.default.clear_refund` |
| Floor start | Set to the computed budget ([§4](#4-starting-budget-and-depth-scaling)) | `collapse.budget.*` |

**Transitions are never refused for lack of ticks in v1.** `allowed` stays true, apart from a sealed exit. The new value is clamped at 0. If it reaches 0, the grace period starts. This removes the soft-lock.

**Ledger v1:** the existing dictionary gains `source` (`transition` | `item:<id>` | `skill:<id>` | `room_clear` | `hazard:<id>` | `shrine`) and `modifiers` (`[{id, delta}]`). It is emitted as `Events.collapse_changed(entry)`, and RunState keeps the per-floor ledger for telemetry.

## 4. Starting budget and depth scaling

**Proposed default (D-04):**

```
start_ticks(floor) = mandatory_route_cost(floor) + slack(depth)
slack(depth)       = max(collapse.budget.min_slack, ceil(collapse.budget.slack_ratio × room_count(depth)))
                     min_slack = 8, slack_ratio = 0.45
```

`mandatory_route_cost` is the **minimum-cost** route start → boss → exit, using Dijkstra over first-entry costs with each room's net cost clamped to ≥ 0. Clamping keeps the estimate conservative when grants exist. The prototype uses BFS hop count; v1 switches to cost-weighted search. The start room is free and the exit cost is included. There is no `+1`, because exit resolution happens before collapse ([GAME_DESIGN.md §3.4](GAME_DESIGN.md#34-boss-and-exit)).

The generator's spine makes the boss `spine − 1` steps from the start, with the exit adjacent. So a typical route is `(spine − 2)` normal rooms + boss + exit = `2 × spine` ticks with the default costs.

| Depth | Rooms (D-06) | Spine | Typical mandatory | Slack | **Start ticks** | Optional first entries affordable (at 2) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 22 | 8 | 16 | 10 | **26** (= current) | 5 (+1–2 with the guild hall) |
| 2 | 26 | 9 | 18 | 12 | **30** | 6 |
| 3 | 30 | 11 | 22 | 14 | **36** | 7 |
| 4 | 34 | 12 | 24 | 16 | **40** | 8 |
| 5 | 40 | 14 | 28 | 18 | **46** | 9 |
| 6 | 44 | 15 | 30 | 20 | **50** | 10 |

Spine = `min(max(round(0.35 × rooms), 5), rooms − 3)`, as implemented in `floor_generator.gd`. Starting ticks never carry over between floors. Leftovers convert to XP at the intermission ([GAME_DESIGN.md §5](GAME_DESIGN.md#5-between-floors-the-intermission)).

Difficulty modes (later) scale `slack_ratio`: Relaxed 0.60, Standard 0.45, Brutal 0.30.

## 5. Room-type policy table

Values marked *implemented* match `prototype_rules.json` today. The others are proposed for the new room kinds and are added to the same `collapse.room_types` block.

| Kind | First entry cost | Revisit cost | First-entry grant | Other | Status |
| --- | ---: | ---: | ---: | --- | --- |
| `default` (fallback) | 2 | 0 | 0 | `clear_refund` 0 | implemented |
| `start` | 0 | 0 | 0 | — | implemented |
| `normal` | 2 (default) | 0 | 0 | — | implemented (via default) |
| `boss` | 3 | 0 | 0 | — | implemented |
| `guild_hall` | 0 | 0 | 3 | services may sell ticks ([§7](#7-time-granting-sources)) | implemented (grant); services proposed |
| `exit` | 1 | 0 | 0 | cost waived during grace; resolves before collapse | cost implemented; waiver proposed |
| `treasure` | 2 | 0 | 0 | — | proposed |
| `elite` | 3 | 0 | 0 | `clear_grant` +1 | proposed |
| `trap` | 1 | 0 | 0 | may contain telegraphed `drain_ticks` plates (−1 each, max 2 per room) | proposed |
| `shrine` | 1 | 0 | 0 | offers HP → ticks trade once ([§7](#7-time-granting-sources)) | proposed |

## 6. Zero-clock outcome — D-05

**Proposed default (D-05): a 10-second grace period with escalating hazards, then a hard collapse.**

When an event leaves the clock at 0, and that event is not the exit:

1. **Grace starts.** A large red countdown replaces the tick counter, the screen gets a dust vignette, and the announcer plays its `grace_started` line (priority).
2. **Doors unlock** in the current room even if hostiles are alive. Entering rooms during grace costs nothing, because the clock cannot go below 0. **First-entry grants still apply.**
3. **Hazards escalate** in whichever room the crawler occupies. Each hazard is a falling-debris marker: a circle of radius 14 px with a 0.8 s ground telegraph that deals 2 flat damage (no AC roll, avoidable with a dodge's i-frames). One marker per wave targets the crawler's position at spawn time. The rest land on random walkable cells.

   | Grace time left | Wave interval | Markers per wave | Extra |
   | --- | ---: | ---: | --- |
   | 10.0–7.0 s | 1.5 s | 1 | light shake (1 px) |
   | 7.0–3.5 s | 1.0 s | 2 | shake 2 px, rumble |
   | 3.5–0.0 s | 0.6 s | 3 | shake 3 px, vignette closes |

4. **Resolution:**
   - **Exit entered** (boss dead): floor success. The exit cost is waived.
   - **Ticks regained** (guild-hall grant, consumable, skill): grace ends and the floor is *stabilised*. A second grace on the same floor lasts **5 s**. A third zero on the same floor is an immediate collapse.
   - **Timer hits 0:** **hard collapse**. The run fails with cause `collapse`, the camera shakes and fades, and the summary follows.
5. Overlays (pause, level-up, reward pick) freeze the grace timer and the hazards, as they freeze all simulation.

Config: `collapse.grace.seconds` 10, `collapse.grace.repeat_seconds` 5, `collapse.grace.max_per_floor` 2, plus `collapse.grace.waves` (the table above).

### Alternatives considered

| Option | Behaviour | For | Against |
| --- | --- | --- | --- |
| A. Immediate collapse (prototype) | Run ends the moment ticks hit 0 | Simplest; very clear | Brutal; no recovery; combined with refusals it caused the soft-lock |
| **B. Grace + hazards (default)** | 10 s last dash, then collapse | Dramatic; rewards a near-exit gamble; keeps a fair fail state | Needs hazard code and tuning |
| C. Debt mode | Ticks go negative; each debt tick adds a hazard tier and −10 % max HP | Soft and continuous | Hard to read; can drag on; muddies "budget" |
| D. Fail-forward drop | Crawler falls to the next floor with −50 % HP and no boss loot | Never ends a run by clock alone | Removes the threat; skips content |
| E. HP drain | Lose 1 HP per second at zero until exit or death | Simple | Merges collapse into death; less distinct |

Revisit the choice if telemetry shows grace converting to success in more than 35 % of triggers (too lenient) or in fewer than 5 % (pointless).

## 7. Time-granting sources

Item and skill names are placeholders. The content data from Wave 1B owns the real records, which use these effect ops.

| Source | Effect op | Default magnitude | Limit |
| --- | --- | --- | --- |
| Guild hall, first entry | `first_entry_grant` | +3 | once per floor (implemented) |
| Guild hall service "shore up" | `collapse.grant_ticks` | +2 per purchase | 2 purchases per hall; price owned by 2E |
| Consumable ("shoring kit") | `collapse.grant_ticks` | +2 | stack size 3 |
| Passive ("surveyor" type) | `collapse.cost_modifier` | −1 on `trap`/`shrine` entries | room cost never below 1 for non-zero kinds |
| Skill ("steady nerves" type) | `collapse.grace_bonus_seconds` | +3 s grace | 1 rank |
| Skill ("efficient route" type) | `collapse.grant_ticks` on `room_cleared_flawless` | +1 | max 3 per floor |
| Shrine offering | `collapse.grant_ticks` for `hp_cost` | 25 % current HP → +3 | once per shrine |
| Elite room clear | `clear_grant` | +1 | per elite room |

**Global cap:** granted ticks per floor are capped at **50 % of `start_ticks`** (`collapse.max_granted_ratio` 0.5). Further grants are logged with reason `capped` and give 0, so that stacking sources cannot remove the pressure.

## 8. Door preview and HUD rules

- **Implemented:** a net-change label on every linked door, and tinting for guild-hall, boss and exit doors.
- **v1 additions:** the label turns red with a `!` when the transition would leave the clock at 0. The HUD tick counter turns amber at ≤ 6 and red at ≤ 3. In-room drains show their `−n` above the trap plate during the telegraph. The full map (M, from 2E) shows the cost of every scouted room.
- **Cost is information.** Because previews reveal the true cost, a kind's cost also signals its kind (a `−3` behind a door is a boss or elite room). This is intended. Never add a modifier that changes a cost after the preview was shown.

## 9. Generator feasibility requirements

The generator ([PROCEDURAL_GENERATION.md §6](PROCEDURAL_GENERATION.md#6-feasibility-checks)) and its tests must guarantee, for every seed:

1. A path start → boss → exit exists on the door graph (already tested for start → exit).
2. `start_ticks − mandatory_route_cost ≥ min_slack` (8). This holds by construction. Assert it anyway, so that a policy edit that breaks it fails CI.
3. No `elite`, `trap` or `shrine` room lies on the cheapest mandatory route, so that special rooms are optional.
4. The guild hall is not on the spine (as implemented), and the path from start to it costs ≤ 50 % of `start_ticks`.
5. The floor's grant total cannot exceed the cap ([§7](#7-time-granting-sources)).
6. A test that runs 200 seeds per depth (1–6) and reports min/median/max of `mandatory_route_cost` and `start_ticks`. Fail if any start budget exceeds 70 (UI readability), or if the route cost varies by more than ±40 % from the depth median.

## 10. Anti-patterns and safeguards

| Anti-pattern | Why it happens | Safeguard |
| --- | --- | --- |
| **Never exploring** (beeline start → boss → exit) | Exploration feels like pure loss | Side rooms hold XP, loot, the guild hall and treasure. Level targets assume about 60 % exploration. The efficiency bonus is capped at about one room's XP. Telemetry alarm: if the median rooms explored is below mandatory + 3, enable `clear_refund` = 1. |
| Exploring everything without tension | Slack too large or grants stack | `slack_ratio` 0.45 lets about 65 % of rooms be explored. The 50 % grant cap applies. |
| Unknowable punishment | Hidden or changed costs | Previews are exact. In-room drains are telegraphed. No retroactive modifiers. |
| Unwinnable seed | Random budget | The budget is derived from the route cost. CI sweeps run per depth. |
| Soft-lock | Refused transitions | Transitions are never refused. Zero leads to grace. |
| Grace farming | Repeated last dashes | Second grace is 5 s; third zero is an instant collapse. |
| Backtracking tedium | Free revisits, but slow walking | Revisits stay free. The full map shows routes. Fast travel between cleared rooms is an open question. |
| Door camping at a locked fight | Leaving to reset aggro | Doors lock 0.5 s after entry (D-07). Enemies persist with their damage. |

## 11. Worked examples (v1 defaults)

**Example 1: a typical floor 1.** 22 rooms, spine 8: the boss is room 7, the exit room 8 and the route is normal rooms 1–6. Mandatory = 6×2 + 3 + 1 = **16**. Slack = ceil(0.45×22) = **10**. Start = **26**.
Start 26 → rooms 1–3 (−6) = 20 → two side rooms (−4) = 16 → guild hall (0, +3) = 19 → back through visited rooms (free) → rooms 4–6 (−6) = 13 → boss (−3) = 10 → four more side rooms (−8) = 2 → exit (−1) = **1** left. Efficiency bonus +10 XP. Rooms explored: start + 6 + 2 + 1 + 1 + 4 + exit = 16 of 22.

**Example 2: arriving at the exit on the last tick.** Ticks 1, boss dead, exit cost 1. *Prototype:* `after == 0`, so the run is reported as **collapsed**. *v1:* exit resolves first, so the floor **succeeds** with 0 left. The run earns the "Exact Change" achievement.

**Example 3: over-explored before the boss.** Ticks 2, boss behind the next door (cost 3). *Prototype:* the transition is refused and the run soft-locks. *v1:* the player can (a) use a shoring kit (+2) → 4, then boss (−3) → 1, kill it, then exit (−1) → 0, a success; or (b) walk in with 2 → 0, which starts grace inside the boss room. Without a fast kill or a grant, the collapse follows in 10 s. The preview's red `!` warned about this before the door.

**Example 4: the grace dash.** Boss dead, 1 tick, the exit two rooms away through an unvisited normal room. Entering it costs 2 → clamp to 0 → grace 10 s. Doors unlock, and crossing 384 px at 105 px/s takes about 3.7 s. Entering the exit at about 4.5 s gives **success**.

**Example 5: floor 6.** 44 rooms, spine 15, mandatory = 13×2 + 3 + 1 = **30**, slack 20, start **50**. Grant cap 25. An elite room costs 3 and refunds 1, so its net cost is 2, the same as a normal room, but with a guaranteed drop ([ENCOUNTER_RULES.md §7](ENCOUNTER_RULES.md#7-rewards)).

## 12. Telemetry to tune

Recorded per floor in RunState and written by 2G: `depth`, `seed`, `room_count`, `mandatory_route_cost`, `start_ticks`, `ticks_spent_by_kind`, `ticks_granted_by_source`, `ticks_capped`, `rooms_entered`, `revisits`, `ticks_left_at_exit`, `grace_triggered`, `grace_outcome` (`exit` | `stabilised` | `collapse` | `death`), `grace_time_used`, `time_per_room_s`, and `first_zero_room_kind`.

**Tuning targets:** median ticks left at exit 2–6; grace triggered in 10–25 % of floors; grace success rate 5–35 %; median rooms explored 55–70 %.

## 13. Open questions

1. Should revisits cost 1 tick on deeper floors (≥ 7) to add backtracking pressure? (Default: no; 0 everywhere.)
2. Should there be any real-time drain, for example 1 tick per 90 s spent in one room? (Default: none. It conflicts with "explore deliberately".)
3. Should the boss room cost be refunded on a boss kill? (Default: no.)
4. Should door previews tint every special kind, or only boss, exit and guild hall as today? (Default: tint only boss, exit and guild hall. Other specials show their cost and a `?` on the map until visited; see [PROCEDURAL_GENERATION.md §7](PROCEDURAL_GENERATION.md#7-fog-minimap-and-the-full-map).)
5. Should grace hazards also damage enemies? (Default: yes, the same 2 damage. It adds chaos and helps the dash.)
6. Should difficulty modes change grace length as well as slack? (Default: slack only.)
