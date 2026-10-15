SELECT word, definition
FROM words
WHERE length = ?1 AND alphagram = ?2
ORDER BY word;
