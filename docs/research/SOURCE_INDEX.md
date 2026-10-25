# Source Index — books, citations and spoilers

- **Status:** Proposed (D-11 default below). **Skeleton.** No sources have been catalogued yet, and no entries are invented here.
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 2 (define covered books, editions and spoiler policy; create the source index)
- **Decision covered:** D-11 (source-books scope, edition references, spoiler policy)
- **Related:** [Catalogue guide](CATALOG_GUIDE.md) · [Catalogue data](../../data/canon/README.md)

## 1. D-11 — Scope

**Proposed default (D-11):**

- **All published books in the main series are in scope.** Each researcher works through them in publication order, and research is never blocked on later books.
- **Citations are chapter-level** (§3).
- **Spoilers are tagged per record** (§4). The catalogue may contain spoilers by design; the tags let readers filter them.
- **Out of scope:** novellas, short stories, audiobook-only extras, interviews, social media and fan wikis. Fan wikis can help find a chapter, but they are never cited.

## 2. Editions

Fill in each row from the copy you actually read. Leave a row blank rather than guess. Book numbers follow series publication order, and the catalogue's `source_book` uses these numbers.

| Book # | Title (from your copy) | Edition / format used | Chapter scheme notes | Researcher(s) | Coverage status |
| ---: | --- | --- | --- | --- | --- |
| 1 | | | | | not started |
| 2 | | | | | not started |
| 3 | | | | | not started |
| 4 | | | | | not started |
| 5 | | | | | not started |
| 6 | | | | | not started |
| 7 | | | | | not started |
| … | (add a row for each further published book) | | | | |

**Coverage status values:** `not started`, `in progress (C<a>–C<b>)`, `first pass done`, `cross-checked`.

If two editions number chapters differently, record the mapping under *Chapter scheme notes*. Records always cite the edition named in this table.

## 3. Citation format

```
B<book>-<location>[: <scene label>]

location    = C<chapter number> | PRO | EPI | INT<n>
scene label = your own words, 80 characters or fewer, no quotation
```

| In prose and notes | In a catalogue record |
| --- | --- |
| `B2-C14` | `"source_book": 2, "source_chapter_or_scene": "C14"` |
| `B3-PRO: arrival scene` | `"source_book": 3, "source_chapter_or_scene": "PRO: arrival scene"` |

(These examples only demonstrate the format. They do not refer to real catalogue content.)

- Cite the **first** chapter where the fact is established. List later reinforcing chapters in `notes`.
- If you are unsure of the chapter, do not cite a range. Set `source_confidence: low` and `review_status: needs_source`.

## 4. Spoiler policy — D-11

| `spoiler_level` | Meaning | Default visibility in designer tools |
| --- | --- | --- |
| `none` | World facts and mechanics that need no plot knowledge | shown |
| `minor` | Small reveals: who someone is, an early twist | shown |
| `major` | Significant plot turns, character fates, faction reveals | hidden unless the reader opts in up to a book number |
| `ending` | A book's climax or ending | hidden unless the reader opts in up to a book number |

- **Inline tag** for Markdown discussion: `[spoiler:B<book>/<level>]` before the sentence, for example `[spoiler:B4/major] …`. Tools and readers treat everything up to the end of that paragraph as spoilered.
- **Game-facing material** (announcer lines, item text, enemy names) never contains spoilers, because it never contains book content (see the [catalogue guide](CATALOG_GUIDE.md#1-principles)).

## 5. Catalogued segments

Add a row when a segment is finished. Records live in [`catalogue.json`](../../data/canon/catalogue.json).

| Segment | Records | Researcher | Cross-checked by | Date |
| --- | ---: | --- | --- | --- |
| *(none yet)* | 0 | | | |

## 6. Open questions

1. Will each researcher use a single shared edition, or record their own (ebook or print)? (Default: each researcher records theirs in §2.)
2. Should audiobook-exclusive material ever count? (Default: no.)
3. Who owns the spoiler opt-in setting in designer tools? (Default: a per-reader `max_book` filter; no central setting.)
