# Shared lexicon contract

This folder is the platform-independent source for the iOS app and a future native Kotlin Android app. The iOS target bundles `catalog.json` and `lookup.sql` directly from here. Do not maintain copies inside platform source folders.

## Resources and lookup

- `catalog.json` identifies each official database and corresponding invalid database filename, source SHA-256, word count, default lexicon, and input rules.
- `lookup.sql` is the actual query executed by iOS. Bind each normalized word to parameter 1. Its columns are `word`, `definition`, and `point_value`. One row means valid; zero rows means not valid. A database error must never become a "not valid" result. The catalog schema version is 4.
- The official database sources live in `../../lexicons/`. Both have `words(word, definition, point_value, ...)` and a unique `word_index`. No migration, index creation, extraction, or database edits are needed.
- Xcode copies the two official and two generated invalid `.db` files into the application bundle. The outdated `.txt` file is not read or packaged.
- Open packaged databases with SQLite read-only flags. Keep connections/statements in a serialized repository, reuse them for lookups, and do disk work off the UI thread.

## Identical input behavior on both platforms

1. Split input into lines at Unicode newlines (LF, CR, VT, FF, NEL, U+2028, U+2029). Treat CRLF as a single line break. The editor and submission parser enforce `inputRules.maximumLines` (8). Count a trailing empty line too: at most seven line breaks are allowed. Soft wrapping does not create a new logical line.
2. Trim each line using the leading/trailing Unicode scalar values enumerated in `inputRules.trimCodePoints`. Ignore empty/whitespace-only lines. If no entries remain, show an input error, never a valid verdict.
3. Preserve input order and duplicates. Use source line indices as entry IDs so repeated words remain distinct.
4. For each entry, reject all characters except ASCII `A-Z` and `a-z` **before** uppercasing. Do not transliterate, remove punctuation, or turn Unicode letters such as `ß` into ASCII words. Reject lengths outside the inclusive catalog bounds (2-15). Record these entries as invalid, with a reason, and continue checking all other entries.
5. Uppercase ASCII `a-z` with the fixed 32-code-point offset. This avoids locale-dependent results (for example Turkish `i`). Only ASCII characters are uppercased in invalid-entry display text too; Unicode characters remain unchanged.
6. Query every eligible entry in the selected lexicon with the bound word. Return the canonical `word`, complete `definition`, and integer `point_value` unchanged. Reset/clear statement bindings between entries. Do not stop at the first invalid word.
7. The whole play is valid only when it is nonempty and **every** entry is valid. If valid, display every word with its definition and base points. If invalid, display **only** the invalid entries, in order. Do not display definitions or points for valid entries in a failed play.
8. `point_value` is the sum of the word's standard letter values. It is not a board score: blanks, letter/word multipliers, and bingo bonuses are not included.
9. Snapshot the selected lexicon with the result so the displayed verdict, definitions, and points always refer to the same edition. Clear empties the complete input and resets any previous result/error.

## Editing contract

Validate the full proposed text replacement before applying it, using the selection range and replacement string. Reject edits that would exceed eight lines. If the replacement includes a newline, require every affected line before a line break to contain at least one non-whitespace character. A single-character line may start a new line even though that word cannot pass word validation yet. Do not require the final line to be filled, so Return can start the next word. A Return at the beginning of a line or next to an existing line break must not create a blank line.

Apply the same checks to paste and selected-text replacement. Reject the whole invalid edit with a message; do not discard extra words or silently truncate. Allow ordinary character deletion and newline removal, even if removing the last character leaves an existing line empty. An unrelated blank line left by deletion must not block Return after a filled line elsewhere. Existing empty lines are ignored when judging.

On iOS, `PlayTextEditor` uses `UITextViewDelegate.shouldChangeTextIn` to validate before UIKit changes its text, keeping native caret, selection, paste, and undo behavior. For Kotlin, use the same proposed-edit rules in the native text field's edit filter/transformation.

## Android integration

Use Gradle assets source directories or a copy task to package this JSON/SQL and the four databases. Android's `SQLiteDatabase` needs a filesystem path, so copy each packaged database to app-private storage on first use (or when its resource version changes), then open that copy with `OPEN_READONLY`. Keep the source assets intact. Use the shared lookup SQL with `rawQuery(sql, arrayOf(word))`, read all three returned columns, close cursors, and run the play's lookups on `Dispatchers.IO`. Implement the small input adapter and all-valid aggregation from the rules above using scalar/character codes. Kotlin + Jetpack Compose can own the UI and view model independently of SwiftUI.

No C++ bridge or cross-platform UI runtime is necessary for this query.

## Learn setup contract

`learn-presets.json` supplies the ordered presets to both platforms. None must be first and has a null pattern. A non-null preset pattern autofills a disabled, gray field. None enables custom entry; selecting a preset preserves the prior custom text so returning to None restores it.

Learn patterns describe unordered letter racks: ASCII letters are required tiles, `?` is exactly one unknown tile, and `*` is any number of extra tiles. Thus `??` selects all 2 letter words, `TISANE?` selects all anagrams using TISANE plus one letter, and `J*` selects words containing J anywhere. Pattern letter order does not constrain positions.

Trim surrounding whitespace, uppercase ASCII letters, and accept only ASCII A-Z, `?`, and at most one `*`. Fixed slots (letters and `?`) must fit the lexicon's maximum word length. Without `*`, there must be at least the minimum word length in slots. An empty pattern cannot start. Both modes can start. Starting snapshots the selected lexicon, preset name, normalized pattern, and mode for the quiz.

## Anagram quiz contract

1. `anagram-racks.sql` returns distinct alphagrams between two bound lengths. Without `*`, both lengths equal the fixed-slot count. With `*`, use max(minimum word length, fixed-slot count) through maximum word length. Retain a rack only if its letter multiplicities cover every required literal letter. Question marks are already accounted for by fixed-slot length. No wildcard tile appears in the quiz: the actual alphagram supplies all letters.
2. Randomly shuffle the distinct matching rack list once. Each rack appears exactly once. The counter is the one-based round index over total matching alphagrams. No matches is an empty-state message, not a quiz or a valid result.
3. `anagram-answers.sql` binds the alphagram's length and the alphagram itself, using the existing length index. Retrieve every full-length anagram and its definition before enabling tiles. Both queries use read-only connections/statements; cancellation and database errors never become invalid guesses.
4. Give each original tile its own stable ID, including repeated letters. Initially rack order is alphagram order. Render every rack slot, replacing selected tiles with blank space; selecting or returning tiles must not shift any other rack tile or collapse grid rows. Tapping a rack tile appends it to the chosen sequence. Tapping a chosen tile returns that tile to its rack position. Dragging an unchosen tile onto a rack slot removes it from its original slot and inserts it at the destination, shifting intervening slots (including blank slots). Drops outside the rack do nothing. The selected sequence and tile identities remain intact. Shuffle permutes only unchosen tile positions in the full restoration order. Reset empties the chosen sequence and restores the original alphabetical order.
5. The last tile automatically submits the sequence. Exact word membership in the round's answer set means correct. Append each correct word once with its definition; show feedback for invalid/duplicate attempts. After every submission, return all tiles in the current restoration order, preserving shuffle and drag reordering. Correct guesses remain visible until the next alphagram.
6. Next freezes the round and displays correct guesses on the left and the complementary missed answers on the right, both with definitions. Next from review advances one round, clears guesses, and restores alphabetical order for the new rack. After the last review, show totals and a return-to-setup button. Switching tabs retains the quiz state.

## Yes/No quiz contract

1. Open the official database as `main`, and attach its catalog `invalidDatabaseFile` as `invalid` using a bound file URI with `mode=ro`. Check both connections are read-only. Decode `invalid.metadata`'s JSON `source_sha256` value and require it to match the selected official catalog hash. A missing or mismatched resource is a load error, never an empty deck or invalid verdict. An Android adapter must preserve these read-only/pairing guarantees.
2. `yes-no-words.sql` binds the same minimum/maximum lengths as the Anagram contract. It returns `word`, `alphagram`, integer `is_valid` (1 or 0), and `definition` (null for invalid words). It unions all official words with generated negatives, excluding any negative present in the official lexicon. Apply the same required-letter multiplicity filter to both categories. A pattern has unordered rack semantics in both quiz modes.
3. Shuffle the complete matching union once. Every distinct matching word appears once, with equal probability at any position; do not balance categories or filter by feasibility score. This uses all matching entries in the generated database, not all possible invalid strings. Do database/filter/shuffle work off the UI thread.
4. Swipe left to mark Invalid or right to mark Valid. iOS requires at least 60 points horizontally and horizontal distance greater than 1.3 times vertical distance; small/vertical gestures do not answer. Accessible buttons/actions have the same behavior. Bind an answer to the displayed word's ID so stale actions cannot advance the following card.
5. Record correctness, previous word, chosen answer, and answer number, then advance immediately. The banner is green for correct and red for incorrect. Include the official definition whenever the answered word is valid, independent of correctness; invalid words have no definition. Keep that feedback visible unchanged until the next answer. Do not expose the current unanswered word's validity or definition.
6. The counter is the one-based current word index over the deck size. After the last answer, retain its feedback and show the final score plus Back to setup. Handle no matches and database failures separately, with retry for failures. Tab switching retains the deck, position, and feedback.
