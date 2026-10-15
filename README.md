# Pernoctated

Offline native iOS play validation for NWL2023 and CSW24. Enter up to eight lines, one word per line, then tap **Check play**. Newlines require a character on the preceding line; empty or whitespace-only lines cannot start another line. The same restrictions apply to paste, without truncating input. A play is valid only if every nonempty line is valid. Valid plays show all words, definitions, and base points; invalid plays show only invalid entries. Order and duplicates are preserved, and **Clear** empties the scrollable editor.

The bottom tabs are **Judge** and **Learn**, in that order. Judge contains the play checker. Learn lets you choose a lexicon, preset, custom pattern, and quiz mode. Presets autofill and disable the pattern field; None enables custom entry and restores any previous custom pattern. Both Anagram and Yes/No can start.

Anagram shuffles matching alphagrams into a deck with no repetition. Tap rack tiles to form a word; the last tile automatically submits. Correct words stay visible with definitions. Shuffle reorders remaining tiles, automatic submission preserves that rack order, and Reset returns every tile to alphabetical order. Next opens a two-column review (correct left, missed right); Next again opens the next round. The final review leads to a completion summary.

Yes/No shuffles every matching valid word and every matching generated invalid word together, without repeats or balancing the two categories. Swipe the card left for Invalid or right for Valid; accessible buttons offer the same choices. Answering advances to the next word. The banner shows the previous answer in green if correct or red if incorrect, and includes the definition whenever that answered word is valid. Feedback stays until the next answer. The counter tracks the current word; the final answer shows completion and the score.

Open `ios/Pernoctated.xcodeproj` in Xcode, select Pernoctated and an iPhone simulator, and Run. Requires iOS 17 or newer. For a physical device, select your signing team in Xcode.

## Architecture

Small MVVM using SwiftUI and Observation, with no third-party dependencies:

- `ContentView` owns the Judge/Learn tab container, with independent navigation in each tab. `JudgeView` handles multiline entry, Clear, word-list selection, and navigation. It uses a compact header and a scrolling native `PlayTextEditor` (`UITextView`), with Check play kept above the keyboard. The editor validates Return/paste before applying edits. `PlayResultView` displays an immutable whole-play result in a scrollable list.
- `LearnSetupViewModel` owns preset selection, custom pattern preservation, pattern validation, and the immutable quiz setup, including mode. `AnagramQuizViewModel` owns the rack deck and tile interaction; `YesNoQuizViewModel` owns the word deck, persistent feedback, and score. SQLite work runs in the repository actor. Presets and all quiz SQL queries are bundled directly from `shared/lexicon/` for reuse by native Android.
- `PlayCheckViewModel` owns line parsing, loading/error states, selection persistence, clearing, and the result. It runs on the main actor. `PlayResult` derives validity from all word results, including malformed entries.
- `LexiconRepository` is a separate actor that opens bundled SQLite databases with `SQLITE_OPEN_READONLY`, verifies the read-only connection/statement, and caches a prepared lookup per lexicon. SQLite work does not run on the UI actor. Queries use the existing unique word index and bind input parameters.
- `shared/lexicon/` contains the SQL, catalog, exact input rules, and Kotlin integration contract. Both database resources and shared resources are referenced directly by Xcode and copied into the build, without modifying the originals.

The indexed SQLite repository supplies Judge validity, definitions, and base points without loading every word into memory. It checks the entire play using a cached prepared statement and publishes a result only when all lookups succeed. Learn builds its matching deck off the UI thread. MVVM keeps each quiz's state and transitions separate without requiring a framework.

## Source data

The official `lexicons/nwl2023.db` and `lexicons/csw24.db` provide valid words. The outdated text file is ignored. Source SHA-256 values and word counts are in `shared/lexicon/catalog.json`. The app performs no database migrations, updates, or writes. Native Android can reuse these resources through its own Kotlin repository; see `shared/lexicon/README.md`.

Generated `lexicons/nwl2023-invalid.db` and `lexicons/csw24-invalid.db` are bundled and supply plausible negatives for Yes/No. Each is attached read-only to its corresponding official database; metadata verifies the edition pairing, and the shared query defensively excludes any valid overlap. Generation, scoring, schema choices, and verification are documented in `shared/invalid-lexicons/README.md`.

## Build

```sh
xcodebuild -project ios/Pernoctated.xcodeproj -scheme Pernoctated \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PernoctatedDerivedData CODE_SIGNING_ALLOWED=NO build
```

No test files or test target are added.

## Yes/No verification

Debug and Release simulator builds pass. Interactive iPhone 17 Pro Max (iOS 26.3) checks cover both swipe directions, correct and incorrect answers for valid and invalid words, definitions after either answer to a valid word, retained feedback while the next card appears, counters, and completion. A temporary executable outside the repository runs the actual Swift source on Simulator: both complete two-letter decks (215 NWL2023 / 225 CSW24 words) pass exact union/definition checks, all answer outcomes, no repetition, stale-action rejection, wildcard/multiplicity filtering, edition-specific CH, empty/error states, and Anagram regression. All four source databases remain unchanged and match bundled copies.

Rack interaction verification on Simulator also passed: selecting E in AET leaves A / blank / T; dragging onto occupied/empty slots and between rows reorders without submitting; out-of-rack drops cancel; returning selected tiles and automatic submission preserve the dragged order; and Reset restores all 15 tiles, including repeated letters, in alphagram order. The rack uses a direct drag gesture, with a floating tile preview and VoiceOver Move left/Move right actions.

## Learn setup verification

The Debug simulator build passed. Interactive checks on iPhone 17 Pro Max (iOS 26.3) verified setup controls; automatic tile submission; correct, invalid, and duplicate guesses; definitions; shuffled-rack restoration; alphabetical Reset; two-column review; round advancement from 1/79 to 2/79; completion and return to setup; and the 15-tile layout. A temporary verification executable outside the repository ran the actual model/repository/view-model source on Simulator. Both lexicons passed wildcard filtering, exact definitions, repeated letters, partial shuffle, tile return, reset, no-match handling, reviews, and full two-letter decks (79 NWL2023 / 93 CSW24 alphagrams) with no repetitions and correct completion totals.

## Multiline verification

- Debug and Release simulator builds succeed with Swift 6 concurrency checking.
- The app installs and launches on the iPhone 17 Pro Max simulator running iOS 26.3.
- A temporary verification executable outside the repository compiled the actual model, repository, and view-model source for the simulator. It passed all-valid, mixed-validity, and wholly invalid plays; exact definitions and points; malformed lines; blank lines; CRLF and Unicode line breaks; duplicate preservation; empty-play rejection; Clear and error reset; repeated checks; lexicon switching; and missing-resource handling.
- `HELLO`, `QUIZ`, and `QI` returned 8, 22, and 11 base points. `CH` and `PERNOCTATED` passed in CSW24 with 7 and 16 points and failed in NWL2023. The subsequent eight-line cap also applies at submission.
- Both source database SHA-256 values match their pre-build values and the copied app resources. Both source databases pass SQLite `quick_check` when opened read-only.
- Interactive UI verification passed in Simulator: Return is rejected on empty/whitespace-only lines, the ninth line and over-limit paste are rejected atomically, valid eight-word plays show every definition and point value, mixed plays show only invalid words, navigation remains responsive, and Clear empties the editor.
