-- Both databases are attached read-only; ?1 and ?2 are inclusive word lengths.
-- Defensively exclude an invalid row if it ever overlaps the selected valid lexicon.
SELECT word, alphagram, 1 AS is_valid, definition
FROM main.words
WHERE length BETWEEN ?1 AND ?2
UNION ALL
SELECT i.word, i.alphagram, 0 AS is_valid, NULL AS definition
FROM invalid.words AS i
WHERE i.length BETWEEN ?1 AND ?2
  AND NOT EXISTS (SELECT 1 FROM main.words AS v WHERE v.word = i.word)
ORDER BY word;
