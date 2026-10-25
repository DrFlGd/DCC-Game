# data/canon: source-checked catalogue

- **Status:** Accepted structure; **catalogue empty**. The only record is `example_item_shape_only`, which shows the record shape and is not a canon entry.
- **Last updated:** 2026-10-25
- **Guide:** [CATALOG_GUIDE.md](../../docs/research/CATALOG_GUIDE.md) · **Sources and spoiler policy:** [SOURCE_INDEX.md](../../docs/research/SOURCE_INDEX.md)

This folder holds **observations from the books**: what the source establishes, cited to book and chapter. It is research data. It is **not** game content and is never loaded by the game. Gameplay definitions live in `game/data/` and the content files from Wave 1B.

## Files

| File | Purpose |
| --- | --- |
| [`schema.json`](schema.json) | JSON Schema (draft 2020-12) for the catalogue file and each record |
| [`catalogue.json`](catalogue.json) | The catalogue: `{ "schema_version": 1, "records": [...] }` |

## Minimum record fields (from the roadmap, Phase 2)

| Field | Purpose |
| --- | --- |
| `id`, `name`, `category` | Stable lookup key (`<category>_<slug>`) and classification |
| `source_book`, `source_chapter_or_scene` | Verifiable provenance (book number; `C12`, `PRO`, `EPI`, `INT1`, optionally `: scene label`) |
| `spoiler_level`, `source_confidence` | `none`/`minor`/`major`/`ending`; `high`/`medium`/`low` |
| `participants`, `context` | Who is involved and under what conditions |
| `observed_behavior` | What the story establishes, in the researcher's own words |
| `gameplay_candidate` | A proposed mechanic, or `null` |
| `adaptation_type` | `canon`, `adapted` or `original` |
| `tags`, `notes`, `review_status` | Search, follow-up and quality control |

Optional fields: `floor_or_depth`, `combat_role`, `status_effects`, `gameplay_suitability`, `related_ids`, `reviewed_by` and `last_reviewed`.

## Rules

1. **Never fabricate.** Every record comes from a passage the researcher has read in the edition listed in [SOURCE_INDEX.md](../../docs/research/SOURCE_INDEX.md). If you can't cite it, don't add it, or mark it `needs_source` and leave it out of designer filters.
2. **No long quotations.** Summarise in your own words. A short identifying phrase is the most a record may quote.
3. Records whose `id` starts with `example_` are ignored by every tool, and their `review_status` must be `example`.
4. A record with `review_status: reviewed` must have `reviewed_by` and `last_reviewed`.

## Validate

```sh
python3 -c "import json,jsonschema; jsonschema.validate(json.load(open('data/canon/catalogue.json')), json.load(open('data/canon/schema.json'))); print('ok')"
```

(Needs the `jsonschema` package. A CI step can be added once real records exist.)
