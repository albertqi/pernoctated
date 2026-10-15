#!/usr/bin/env python3
"""Create reproducible, verified negative lexicons. Standard library only; source DBs read-only."""

from __future__ import annotations

import argparse
import bisect
import collections
import functools
import hashlib
import heapq
import itertools
import json
import math
import os
from pathlib import Path
import random
import sqlite3
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
COMMON_LETTERS = "EEEEEEEEAAAARRRRIIIIOOOOTTTTNNNNSSSSLLLLCCDDPPMMHHGGUUBBFFYYWWKVXZJQ"
POINTS = dict(zip(ALPHABET, (1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10)))
METHOD = "single-edit-character-model-v1"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def readonly(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro")
    connection.execute("PRAGMA query_only = ON")
    return connection


class CharacterModel:
    """Interpolated order-0..3 character model with boundaries and additive smoothing."""

    def __init__(self, words: list[str]) -> None:
        self.counts: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
        self.bigrams: set[str] = set()
        self.trigrams: set[str] = set()
        for word in words:
            self.bigrams.update(word[i:i + 2] for i in range(len(word) - 1))
            self.trigrams.update(word[i:i + 3] for i in range(len(word) - 2))
            text = "^^^" + word + "$"
            for index in range(3, len(text)):
                for order in range(4):
                    context = text[index - order:index] if order else ""
                    self.counts[context][text[index]] += 1
        self.totals = {context: sum(counts.values()) for context, counts in self.counts.items()}

    @functools.lru_cache(maxsize=600_000)
    def transition(self, context: str, letter: str) -> float:
        probability = 0.0
        for order, weight in enumerate((0.05, 0.10, 0.25, 0.60)):
            suffix = context[-order:] if order else ""
            counts = self.counts.get(suffix)
            count = counts.get(letter, 0) if counts else 0
            # 26 letters plus the end marker. Backoff remains defined for unseen contexts.
            probability += weight * (count + 0.05) / (self.totals.get(suffix, 0) + 27 * 0.05)
        return math.log(probability)

    @functools.lru_cache(maxsize=150_000)
    def score(self, word: str) -> float:
        text = "^^^" + word + "$"
        return sum(self.transition(text[i - 3:i], text[i]) for i in range(3, len(text))) / (len(word) + 1)

    def common_sequences(self, word: str) -> bool:
        # Suppress obvious noise (e.g. AAAA/QXZ), even if a unigram frequency is high.
        return (not any(word[i] == word[i + 1] == word[i + 2] for i in range(len(word) - 2))
                and all(word[i:i + 2] in self.bigrams for i in range(len(word) - 1))
                and all(word[i:i + 3] in self.trigrams for i in range(len(word) - 2)))


def mutations(word: str, target_length: int, lexicon: str):
    """Exhaust short racks; use deterministic spelling variations for longer words."""
    size = len(word)
    rng = random.Random(f"{METHOD}:{lexicon}:{word}:{target_length}")
    exhaustive = target_length <= 3
    if target_length == size:
        positions = range(size) if exhaustive else [rng.randrange(size) for _ in range(8)]
        for position in positions:
            letters = ALPHABET if exhaustive else (rng.choice(COMMON_LETTERS),
                                                   rng.choice("AEIOU") if word[position] in "AEIOU" else rng.choice(COMMON_LETTERS))
            for letter in letters:
                if letter != word[position]:
                    yield word[:position] + letter + word[position + 1:], "substitute"
        positions = range(size - 1) if exhaustive else [rng.randrange(size - 1) for _ in range(3)]
        for position in positions:
            if word[position] != word[position + 1]:
                yield word[:position] + word[position + 1] + word[position] + word[position + 2:], "transpose"
    elif target_length == size + 1:
        positions = range(size + 1) if exhaustive else [rng.randrange(size + 1) for _ in range(5)]
        for position in positions:
            letters = ALPHABET if exhaustive else (rng.choice(COMMON_LETTERS), word[min(position, size - 1)])
            for letter in letters:
                yield word[:position] + letter + word[position:], "insert"
    elif target_length == size - 1:
        positions = range(size) if exhaustive else [rng.randrange(size) for _ in range(5)]
        for position in positions:
            yield word[:position] + word[position + 1:], "delete"


def one_edit(source: str, word: str, operation: str) -> bool:
    """Independent provenance verification; includes an adjacent transposition as one edit."""
    if operation == "substitute":
        return len(source) == len(word) and sum(a != b for a, b in zip(source, word)) == 1
    if operation == "insert":
        return len(word) == len(source) + 1 and any(word[:i] + word[i + 1:] == source for i in range(len(word)))
    if operation == "delete":
        return len(source) == len(word) + 1 and any(source[:i] + source[i + 1:] == word for i in range(len(source)))
    if operation == "transpose":
        return len(word) == len(source) and source != word and any(
            source[:i] + source[i + 1] + source[i] + source[i + 2:] == word for i in range(len(source) - 1))
    return False


def verify(output: Path, source: Path, model: CharacterModel, valid: set[str]) -> dict:
    with readonly(output) as connection:
        connection.execute("ATTACH DATABASE ? AS valid", (source.resolve().as_uri() + "?mode=ro",))
        if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise RuntimeError("Generated database failed integrity_check")
        if connection.execute("PRAGMA foreign_key_check").fetchall():
            raise RuntimeError("Generated database failed foreign_key_check")
        overlap = connection.execute("SELECT count(*) FROM words n JOIN valid.words v ON n.word = v.word").fetchone()[0]
        if overlap:
            raise RuntimeError(f"Generated database contains {overlap} valid words")
        rows = connection.execute("""SELECT w.*, f.mean_log_probability, f.valid_word_percentile,
                                   f.source_word, f.edit_operation, f.edit_distance
                                   FROM words w JOIN feasibility f ON w.word = f.word ORDER BY w.word""").fetchall()
        total = connection.execute("SELECT count(*) FROM words").fetchone()[0]
        if total != len(rows) or total != connection.execute("SELECT count(*) FROM feasibility").fetchone()[0]:
            raise RuntimeError("Incomplete feasibility provenance")
        anagrams = collections.Counter(row[2] for row in rows)
        thresholds = dict(connection.execute("SELECT length, minimum_mean_log_probability FROM length_statistics"))
        for word, length, alphagram, count, unique, vowels, points, score, percentile, seed, operation, distance in rows:
            assert word.isascii() and word.isalpha() and word.isupper() and 2 <= len(word) <= 15
            assert length == len(word) and alphagram == "".join(sorted(word))
            assert count == anagrams[alphagram] and unique == len(set(word))
            assert vowels == sum(letter in "AEIOU" for letter in word)
            assert points == sum(POINTS[letter] for letter in word)
            assert seed in valid and word not in valid and one_edit(seed, word, operation) and distance == 1
            assert model.common_sequences(word) and 25 <= percentile <= 100
            assert math.isclose(score, model.score(word), abs_tol=1e-10) and score >= thresholds[length] - 1e-10
        counts = dict(connection.execute("SELECT length, count(*) FROM words GROUP BY length"))
        for length, selected_count in connection.execute("SELECT length, selected_word_count FROM length_statistics"):
            assert counts.get(length, 0) == selected_count
        return {"word_count": total, "counts_by_length": counts, "valid_overlap": overlap,
                "integrity_check": "ok", "foreign_key_check": "ok",
                "all_rows_recomputed": True, "all_provenance_verified": True}


def build(lexicon: str, cap: int, build_date: str) -> dict:
    source = ROOT / "lexicons" / f"{lexicon}.db"
    output = ROOT / "lexicons" / f"{lexicon}-invalid.db"
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite existing database: {output}")
    source_hash = sha256(source)
    with readonly(source) as connection:
        if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise RuntimeError("Source database failed quick_check")
        words = [row[0] for row in connection.execute("SELECT word FROM words WHERE length BETWEEN 2 AND 15 ORDER BY word")]
        source_date = connection.execute("SELECT date FROM lexicon_date").fetchone()[0]
    assert words and all(w.isascii() and w.isalpha() and w.isupper() for w in words)
    valid = set(words)
    by_length: dict[int, list[str]] = collections.defaultdict(list)
    for word in words:
        by_length[len(word)].append(word)
    print(f"{lexicon}: training spelling model on {len(words):,} valid words", flush=True)
    model = CharacterModel(words)
    selections = []
    statistics = []
    for length in range(2, 16):
        baseline = sorted(model.score(word) for word in by_length[length])
        threshold = baseline[math.ceil(len(baseline) * 0.25) - 1]
        heap = []
        kept = set()
        attempts = 0
        feasible = 0
        for source_length in (length - 1, length, length + 1):
            for seed in by_length.get(source_length, []):
                for word, operation in mutations(seed, length, lexicon):
                    attempts += 1
                    if word in valid or word in kept or not model.common_sequences(word):
                        continue
                    score = model.score(word)
                    percentile = 100 * bisect.bisect_right(baseline, score) / len(baseline)
                    if score < threshold or percentile < 25:
                        continue
                    feasible += 1
                    # Score and lexical tie break make selection deterministic.
                    entry = (score, word, seed, operation, percentile)
                    if len(heap) < cap:
                        heapq.heappush(heap, entry)
                        kept.add(word)
                    elif (score, word) > heap[0][:2]:
                        removed = heapq.heapreplace(heap, entry)
                        kept.remove(removed[1])
                        kept.add(word)
        if not heap:
            raise RuntimeError(f"No feasible negatives at length {length}")
        selections.extend(heap)
        statistics.append((length, len(baseline), threshold, attempts, feasible, len(heap)))
        print(f"{lexicon}: length {length:2} — {len(heap):,} selected / {attempts:,} edits examined", flush=True)
        model.score.cache_clear()
    anagrams = collections.Counter("".join(sorted(entry[1])) for entry in selections)
    metadata = {
        "lexicon": lexicon + "-invalid",
        "schema_version": 1,
        "generator_version": METHOD,
        "generator_sha256": sha256(Path(__file__)),
        "python_version": sys.version.split()[0],
        "source_database": source.name,
        "source_sha256": source_hash,
        "source_lexicon_date": source_date,
        "generated_date": build_date,
        "maximum_per_length": cap,
        "minimum_valid_word_percentile": 25,
        "smoothing_alpha": 0.05,
        "ngram_weights_order_0_to_3": [0.05, 0.10, 0.25, 0.60],
        "vowels": "AEIOU (Y is excluded, matching the official databases)",
        "num_anagrams_semantics": "Number of rows in this INVALID database sharing the same alphagram",
        "validity_verified_against": source.name,
    }
    handle, temporary = tempfile.mkstemp(prefix=f".{lexicon}-invalid-", suffix=".db", dir=output.parent)
    os.close(handle)
    temporary_path = Path(temporary)
    try:
        with sqlite3.connect(temporary_path) as connection:
            connection.executescript(Path(__file__).with_name("schema.sql").read_text())
            connection.execute("PRAGMA user_version = 1")
            for score, word, seed, operation, percentile in sorted(selections, key=lambda entry: entry[1]):
                alphagram = "".join(sorted(word))
                connection.execute("INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?)",
                                   (word, len(word), alphagram, anagrams[alphagram], len(set(word)),
                                    sum(letter in "AEIOU" for letter in word), sum(POINTS[letter] for letter in word)))
                connection.execute("INSERT INTO feasibility VALUES (?, ?, ?, ?, ?, 1)",
                                   (word, score, percentile, seed, operation))
            connection.executemany("INSERT INTO length_statistics VALUES (?, ?, ?, ?, ?, ?)", statistics)
            connection.executemany("INSERT INTO metadata VALUES (?, ?)",
                                   [(key, json.dumps(value, sort_keys=True)) for key, value in metadata.items()])
            connection.execute("INSERT INTO db_version VALUES (1)")
            connection.execute("INSERT INTO lexicon_date VALUES (?)", (build_date,))
            connection.execute("INSERT INTO lexicon_file VALUES (?)", (output.name,))
        report = verify(temporary_path, source, model, valid)
        if sha256(source) != source_hash:
            raise RuntimeError("Source database hash changed")
        # Atomic publication without replacement. Existing files are never overwritten.
        os.link(temporary_path, output)
        report.update({"database": output.name, "sha256": sha256(output), "source_sha256": source_hash,
                       "source_unchanged": True, "generation": metadata})
        print(f"{lexicon}: VERIFIED {report['word_count']:,} invalid words; valid overlap = 0", flush=True)
        return report
    finally:
        temporary_path.unlink(missing_ok=True)
        model.score.cache_clear()
        model.transition.cache_clear()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lexicon", choices=("nwl2023", "csw24"), action="append")
    parser.add_argument("--maximum-per-length", type=int, default=5000)
    parser.add_argument("--date", required=True, help="Generation date, YYYY-MM-DD")
    args = parser.parse_args()
    if args.maximum_per_length < 1:
        parser.error("maximum-per-length must be positive")
    from datetime import date
    date.fromisoformat(args.date)
    lexicons = args.lexicon or ["nwl2023", "csw24"]
    if len(set(lexicons)) != len(lexicons):
        parser.error("lexicon cannot be repeated")
    for lexicon in lexicons:
        if (ROOT / "lexicons" / f"{lexicon}-invalid.db").exists():
            parser.error(f"{lexicon}-invalid.db already exists; existing databases will not be overwritten")
    reports = [build(lexicon, args.maximum_per_length, args.date) for lexicon in lexicons]
    print(json.dumps({"databases": reports}, indent=2, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
