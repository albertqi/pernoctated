SELECT word, alphagram
FROM words
WHERE length BETWEEN ?1 AND ?2
ORDER BY word;
