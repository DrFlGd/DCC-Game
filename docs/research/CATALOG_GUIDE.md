# Catalogue Guide — researching the books

- **Status:** Accepted (process and schema). The catalogue is empty; research has not started.
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 2 (research workflow, minimum record), backlog task 8
- **Related:** [Source index and spoiler policy](SOURCE_INDEX.md) · [Catalogue data and schema](../../data/canon/README.md) · [Enemy tiers](../design/ENEMY_TIERS.md) · [Game design §9 (IP scope)](../design/GAME_DESIGN.md#9-scope-and-ip--d-12)

The catalogue answers one question for designers: *what does the source actually establish?* It records cited observations so that designers can filter them into item, ability and enemy candidates without re-reading the books. It is not game content, and it never ships with a build.

## 1. Principles

1. **Observation is separate from adaptation.** `observed_behavior` says what the book shows. `gameplay_candidate` says what we might build. Keep them in separate fields and never blend them.
2. **Every claim has a location.** Cite book number and chapter ([SOURCE_INDEX.md §3](SOURCE_INDEX.md#3-citation-format)). An uncited record cannot be `canon`.
3. **Use your own words.** Summarise in 1–3 sentences. Do not paste passages; a short identifying phrase is the most you may quote.
4. **No fabrication.** Unsure means `source_confidence: low` and `review_status: needs_source`. An unread chapter means no record.
5. **The game uses original expression.** The catalogue can name characters and things from the books because it is research. Game data, UI text and announcer lines never reuse them. An `adapted` mechanic gets a new name and new presentation in the content data.

## 2. Workflow

| Step | Who | Output |
| --- | --- | --- |
| 1. Pick a segment | Research lead | A chapter range from SOURCE_INDEX, marked *in progress* there |
| 2. Read and note | Researcher | Draft records (`review_status: draft`) |
| 3. Self-check | Researcher | Schema-valid file ([validate](../../data/canon/README.md#validate)); every record cited |
| 4. Cross-check | A second person with the same edition | Status set to `reviewed` (with `reviewed_by` and `last_reviewed`) or `disputed`, with a note |
| 5. Tag for design | Designer | `gameplay_candidate`, `gameplay_suitability`, `combat_role` |
| 6. Audit (each 50 records) | Research lead | Duplicates merged, contradictions noted, spoilers checked |

Commit after each segment, using a message like `docs(canon): B<n> C<a>-C<b> first pass`.

## 3. Field-by-field rules

| Field | Rule |
| --- | --- |
| `id` | `<category>_<slug>`, in lowercase snake case. It never changes after review; rename via `related_ids` plus a note. |
| `name` | The name as the source gives it, or a neutral descriptor if unnamed. |
| `category` | `encounter`, `enemy`, `weapon`, `item`, `spell`, `skill`, `companion_action`, `environment`, `system_rule`, `achievement` or `other`. A record has one category; link others through `related_ids`. |
| `source_book` | The book number from SOURCE_INDEX §2. |
| `source_chapter_or_scene` | `C<n>`, `PRO`, `EPI` or `INT<n>`, optionally followed by `: ` and a scene label in your own words of 80 characters or fewer. Use the first chapter where the thing is established, and add later ones in `notes`. |
| `spoiler_level` | See [SOURCE_INDEX.md §4](SOURCE_INDEX.md#4-spoiler-policy--d-11). |
| `source_confidence` | `high` = stated explicitly; `medium` = strongly implied, or spread across scenes; `low` = ambiguous, or from memory pending a check. |
| `participants` | Characters or groups involved, as the source names them. |
| `context` | Circumstances: the situation and any preconditions. |
| `observed_behavior` | What happens or what the thing does, in ≤ 600 characters of your own words. No numbers that the book does not give. |
| `gameplay_candidate` | Optional idea, or `null`. Mark uncertainty ("could become a…"). |
| `adaptation_type` | `canon` = the candidate mirrors the observation faithfully; `adapted` = changed for balance or format (say how in `notes`); `original` = the record exists only to document that a similar-looking game idea is *not* sourced. |
| `tags` | Free lowercase tags, using prefixes where helpful: `status:poison`, `biome:water`, `role:summoner`. |
| `review_status` | `draft` → `in_review` → `reviewed` (or `disputed` / `needs_source`). `example` only for `example_` ids. |

## 4. Filtering for designers

Queries designers will run (a small script or `jq` is enough):

- **Enemy candidates:** `category == "enemy"`, `review_status == "reviewed"`, `gameplay_suitability in [high, medium]`, grouped by `combat_role`.
- **Item and ability candidates:** `category in [weapon, item, spell, skill]`, with tags containing `status:*`.
- **Spoiler-safe view:** `spoiler_level in [none, minor]`, or `source_book ≤` the reader's chosen book.

When a candidate is built, its content record (in the Wave 1B content data) stores `source_ref: "<canon id>"` and `adaptation_type`. Content rules are documented separately in `docs/design/CONTENT_RULES.md`.

## 5. Quality bar

- Every record validates against [`schema.json`](../../data/canon/schema.json).
- At most 10 % of non-example records are `needs_source` at any audit.
- No two reviewed records describe the same observation; merge them and keep the older id.
- Contradictions between books are recorded as separate records cross-linked by `related_ids`, with a note. Do not resolve them by guessing.

## 6. Open questions

1. Should records ever cite page numbers? (Default: no. Chapters are stable across editions and formats.)
2. Should a CI job validate `data/canon/catalogue.json`? (Default: yes, once the first real record lands.)
3. Should canon research also cover author interviews or supplementary material? (Default: no; published books only, see D-11.)
