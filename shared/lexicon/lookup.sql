SELECT word, definition, point_value
FROM words
WHERE word = ?1
LIMIT 1;
