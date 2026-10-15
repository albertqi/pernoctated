# Invalid lexicons for Learn

Generated negative-word datasets for Learn's Yes/No quiz. The app bundles both databases and queries the selected edition read-only using `../lexicon/yes-no-words.sql`.

| Database | Words | Length 2 | Length 3 | Each length 4-15 |
| --- | ---: | ---: | ---: | ---: |
| `../../lexicons/nwl2023-invalid.db` | 60,953 | 108 | 845 | 5,000 |
| `../../lexicons/csw24-invalid.db` | 60,975 | 98 | 877 | 5,000 |

Each database excludes every word in its corresponding official lexicon. Validity is edition-specific; a negative for one edition may be valid in the other. Entries use uppercase ASCII A-Z and have 2-15 letters. There are no duplicates.

## Feasibility metric

1. Train a character model on the corresponding official lexicon, including word-start/end boundaries. Interpolate context lengths 0, 1, 2, and 3 with weights 0.05, 0.10, 0.25, and 0.60. Each conditional probability uses additive smoothing alpha 0.05 over 26 letters plus the end marker. Score a candidate with mean natural log probability, including the end marker.
2. Generate candidates by one substitution, insertion, deletion, or adjacent transposition from an official valid word. Repeated letters are treated individually. Exhaust the short-word mutations for lengths 2 and 3. Longer words use deterministic sampling, including common letters, vowel substitutions, and letter doubling. A stable per-source-word seed makes regeneration reproducible with the recorded generator/Python version.
3. Exclude official valid words before scoring. Require every internal bigram and trigram to occur somewhere in the training corpus, and reject runs of three identical letters. Require the score to be at or above the 25th percentile of valid words of the candidate's length.
4. Retain at most 5,000 highest-scoring distinct candidates at each length. Short lengths have fewer candidates that satisfy the criteria. Score/word ordering resolves ties deterministically. These are curated samples, not an exhaustive list of invalid strings or all possible edits.

Examples of generated NWL2023 negatives include `PRINESSES` (from PRINCESSES), `CONVERATIONS` (from CONVERSATIONS), `CONCIOUSNESSES` (from CONSCIOUSNESSES), and `INTERMALIZATION` (from INTERNALIZATION). They have plausible spelling patterns and are absent from NWL2023.

The score measures spelling plausibility, not a probability that the word is valid. `valid_word_percentile` compares the candidate's model score with valid words of the same length. It is not a correctness/confidence score. For future sampling, stratify by length and percentile instead of always showing the highest-ranked morphological endings.

## Schema

`schema.sql` is the source of truth. The `words` table retains official column names and SQLite types for `word`, `length`, `alphagram`, `num_anagrams`, `num_unique_letters`, `num_vowels`, and `point_value`. Word/length indexes retain their official names. An additional alphagram index supports grouping.

`num_anagrams` counts entries sharing an alphagram **within this invalid database**, not across the valid lexicon or all possible invalid strings. Vowels are A/E/I/O/U, excluding Y, matching the official databases. Base points use standard Scrabble letter values.

Definitions are omitted because these are invalid words. Official playability/probability ranks, combination counts, lexicon symbols, and hook fields are also omitted: importing those fields would imply official data or valid-word relationships that these generated strings do not have.

Separate tables:

- `feasibility`: spelling score, valid-word percentile, source valid word, edit operation, and edit distance (always one). The source word belongs to the corresponding official lexicon. It is provenance, not the only possible related word.
- `length_statistics`: valid baseline size, minimum allowed score, candidate edit attempts, feasible attempts, and selected count. Attempt counts may include duplicate candidates.
- `metadata`: source filename/date/SHA-256, generator version/SHA-256, Python version, generation date, and scoring parameters. Values are JSON-encoded.
- `db_version`, `lexicon_date`, and `lexicon_file`: familiar table names, with this generated format's own schema version 1 and generation date. These are not official Zyzzyva lexicons, and schema version 1 does not assert Zyzzyva import compatibility. SQLite `user_version` is also 1.

## Generation and verification

From the repository root:

```sh
python3 shared/invalid-lexicons/build_invalid_lexicons.py --date 2026-10-05
```

The generator refuses to overwrite existing output databases. `--lexicon nwl2023` or `--lexicon csw24` builds just one edition; `--maximum-per-length` changes the per-length cap. Source databases always use SQLite URI `mode=ro` and `PRAGMA query_only=ON`. No source modifications, migrations, or indexes are performed.

Before publishing each new database, the generator opens it read-only, attaches the official source read-only, and checks all rows with an exact SQL join. It also performs full SQLite integrity/foreign-key checks and independently recomputes lengths, alphagrams, anagram counts, distinct-letter/vowel counts, points, scores, thresholds, and one-edit provenance. Source SHA-256 is checked before and after generation. New databases are published atomically without replacement only after verification succeeds.

The final read-only audit is recorded in `verification.json`. Both databases have zero intersections with their official counterparts, cover all lengths 2-15, and pass `integrity_check` and `foreign_key_check`. Official source hashes remain unchanged.
