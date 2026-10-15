PRAGMA foreign_keys = ON;

-- Names and SQLite types are shared with the official words tables where meaningful.
CREATE TABLE words (
    word TEXT NOT NULL CHECK(length(word) BETWEEN 2 AND 15 AND word NOT GLOB '*[^A-Z]*'),
    length INTEGER NOT NULL CHECK(length = length(word)),
    alphagram TEXT NOT NULL,
    num_anagrams INTEGER NOT NULL CHECK(num_anagrams > 0),
    num_unique_letters INTEGER NOT NULL CHECK(num_unique_letters BETWEEN 1 AND length),
    num_vowels INTEGER NOT NULL CHECK(num_vowels BETWEEN 0 AND length),
    point_value INTEGER NOT NULL CHECK(point_value > 0)
);
CREATE UNIQUE INDEX word_index ON words(word);
CREATE INDEX word_length_index ON words(length);
CREATE INDEX alphagram_index ON words(alphagram);

CREATE TABLE feasibility (
    word TEXT PRIMARY KEY REFERENCES words(word),
    mean_log_probability REAL NOT NULL,
    valid_word_percentile REAL NOT NULL CHECK(valid_word_percentile BETWEEN 25 AND 100),
    source_word TEXT NOT NULL,
    edit_operation TEXT NOT NULL CHECK(edit_operation IN ('substitute', 'insert', 'delete', 'transpose')),
    edit_distance INTEGER NOT NULL CHECK(edit_distance = 1)
);
CREATE INDEX feasibility_rank_index ON feasibility(mean_log_probability DESC, word);

CREATE TABLE length_statistics (
    length INTEGER PRIMARY KEY CHECK(length BETWEEN 2 AND 15),
    valid_word_count INTEGER NOT NULL,
    minimum_mean_log_probability REAL NOT NULL,
    candidate_attempts INTEGER NOT NULL,
    feasible_attempts INTEGER NOT NULL,
    selected_word_count INTEGER NOT NULL
);

-- The generated database has its own schema version, not Zyzzyva's schema version.
CREATE TABLE db_version (version INTEGER);
CREATE TABLE lexicon_date (date DATE);
CREATE TABLE lexicon_file (file TEXT);
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
