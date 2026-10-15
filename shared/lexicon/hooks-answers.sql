-- ?1 is the base word; ?2 is 1 for front hooks and 0 for back hooks.
-- Exact indexed membership, not spelling heuristics or generated negatives.
WITH RECURSIVE letters(n, letter) AS (
    SELECT 1, 'A'
    UNION ALL
    SELECT n + 1, substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ', n + 1, 1)
    FROM letters WHERE n < 26
)
SELECT letters.letter, words.word, words.definition
FROM letters
JOIN words ON words.word = CASE WHEN ?2 = 1 THEN letters.letter || ?1 ELSE ?1 || letters.letter END
WHERE words.length BETWEEN 2 AND 15
ORDER BY letters.letter;
