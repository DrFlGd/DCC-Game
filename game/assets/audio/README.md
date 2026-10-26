# DCC Game — audio assets (generated placeholders)

Every file here is synthesised by [`tools/gen_sfx.py`](../../../tools/gen_sfx.py) from oscillators, filtered noise and envelopes; nothing is sampled or downloaded. Regenerate from the repository root with

```bash
python3 tools/gen_sfx.py            # all 38 files, deterministic
python3 tools/gen_sfx.py --only melee_hit level_up
```

(Python 3 standard library only.) Then let Godot reimport (`godot --headless --path game --editor --quit`, which `game/tests/run_all.sh` does first). The `.import` files are committed alongside the WAVs; the `.godot/` cache is not.

| Folder | Contents | Format |
| --- | --- | --- |
| `sfx/` | 35 one-shots: ui_move / ui_confirm / ui_back, melee_swing / melee_hit, ranged_fire / enemy_fire / ranged_hit, player_hurt / player_dodge / player_death / player_heal, enemy_hurt / enemy_death / boss_death, pickup_item / pickup_credits / item_use, chest_open / loot_box, door_lock / door_unlock, level_up / xp_tick, ticks_gain / ticks_loss / grace_warning, hazard_telegraph / hazard_hit, floor_cleared / run_victory / run_defeat, announcer_blip, shop_buy, skill_use | 22050 Hz, 16-bit PCM mono, 0.03–2.25 s, peak -6 dBFS |
| `ambient/` | `crypt_drone` (sub drone, filtered wind, drips), `boss_drone` (lower drone, 75 BPM heartbeat) | 8 s seamless loops with a RIFF `smpl` forward loop |
| `music/` | `crypt_theme`: A-minor chiptune arpeggio over bass, hats and a soft pad | 16 s seamless loop, mixed at -12 dB by `data/audio.json` |

Which sound plays when, and how loud, is decided by [`game/data/audio.json`](../../data/audio.json), not by the files (see the Audio section of [`game/README.md`](../../README.md)).

**Quality note.** These are placeholder sounds meant to make events legible during playtests. Replacing any file with a produced sound of the same name needs no code; a different name is one line in `audio.json`.

**License.** Generated in-repo by the project's own script, with no third-party samples. The WAVs and the generator are released under the project's license and may also be treated as CC0 (public domain) if that is more convenient.
