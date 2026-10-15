import Foundation
import SQLite3

/// A dedicated actor keeps SQLite access serialized and off the main actor.
actor LexiconRepository {
    private var connections: [String: ReadOnlyLexicon] = [:]

    private func connection(for lexicon: Lexicon, queryFile: String = "lookup.sql") throws -> ReadOnlyLexicon {
        if let existing = connections[lexicon.id] { return existing }
        let opened = try ReadOnlyLexicon(lexicon: lexicon, queryFile: queryFile)
        connections[lexicon.id] = opened
        return opened
    }

    func anagramRacks(lexicon: Lexicon, pattern: AnagramPattern) throws -> [String] {
        try connection(for: lexicon).anagramRacks(pattern: pattern)
    }

    func anagramAnswers(lexicon: Lexicon, alphagram: String) throws -> [AnagramAnswer] {
        try connection(for: lexicon).anagramAnswers(alphagram: alphagram)
    }

    func yesNoQuestions(lexicon: Lexicon, pattern: AnagramPattern) throws -> [YesNoQuestion] {
        do {
            return try connection(for: lexicon).yesNoQuestions(lexicon: lexicon, pattern: pattern).shuffled()
        } catch {
            connections[lexicon.id] = nil
            throw error
        }
    }

    func lookupPlay(entries: [SubmittedWord], lexicon: Lexicon, queryFile: String) throws -> PlayResult {
        guard !entries.isEmpty else { throw InputError.empty }
        let connection = try connection(for: lexicon, queryFile: queryFile)
        do {
            let words = try entries.map { entry in
                try Task.checkCancellation()
                if let issue = entry.inputIssue {
                    return WordResult(id: entry.id, word: entry.word, definition: nil, basePoints: nil,
                                      inputIssue: issue, isValid: false)
                }
                return try connection.lookup(entry: entry)
            }
            return PlayResult(lexicon: lexicon, words: words)
        } catch {
            connections[lexicon.id] = nil
            throw error
        }
    }
}

/// Owned exclusively by LexiconRepository; never passed between actors.
private final class ReadOnlyLexicon {
    private var database: OpaquePointer?
    private var statement: OpaquePointer?
    private var invalidAttached = false

    init(lexicon: Lexicon, queryFile: String) throws {
        guard let databaseURL = Bundle.main.url(forResource: lexicon.databaseFile, withExtension: nil),
              let queryURL = Bundle.main.url(forResource: queryFile, withExtension: nil) else {
            throw LexiconError.missingResources
        }
        let sql = try String(contentsOf: queryURL, encoding: .utf8)
        var openedDatabase: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(openedDatabase)
            throw LexiconError.databaseUnavailable
        }
        guard sqlite3_db_readonly(openedDatabase, "main") == 1 else {
            sqlite3_close(openedDatabase)
            throw LexiconError.databaseUnavailable
        }
        var preparedStatement: OpaquePointer?
        guard sqlite3_prepare_v2(openedDatabase, sql, -1, &preparedStatement, nil) == SQLITE_OK,
              sqlite3_stmt_readonly(preparedStatement) == 1,
              sqlite3_bind_parameter_count(preparedStatement) == 1,
              sqlite3_column_count(preparedStatement) == 3 else {
            sqlite3_finalize(preparedStatement)
            sqlite3_close(openedDatabase)
            throw LexiconError.lookupFailed
        }
        database = openedDatabase
        statement = preparedStatement
    }

    deinit {
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    private func prepareQuery(_ name: String, columns: Int) throws -> OpaquePointer {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sql") else {
            throw LexiconError.missingResources
        }
        let sql = try String(contentsOf: url, encoding: .utf8)
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK,
              let query, sqlite3_stmt_readonly(query) == 1,
              sqlite3_bind_parameter_count(query) == 2,
              sqlite3_column_count(query) == columns else {
            sqlite3_finalize(query)
            throw LexiconError.lookupFailed
        }
        return query
    }

    private func attachInvalidDatabase(lexicon: Lexicon) throws {
        guard !invalidAttached else { return }
        guard let url = Bundle.main.url(forResource: lexicon.invalidDatabaseFile, withExtension: nil) else {
            throw LexiconError.missingResources
        }
        var attach: OpaquePointer?
        defer { sqlite3_finalize(attach) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_prepare_v2(database, "ATTACH DATABASE ?1 AS invalid", -1, &attach, nil) == SQLITE_OK,
              sqlite3_bind_text(attach, 1, url.absoluteString + "?mode=ro", -1, transient) == SQLITE_OK,
              sqlite3_step(attach) == SQLITE_DONE,
              sqlite3_db_readonly(database, "invalid") == 1 else {
            throw LexiconError.databaseUnavailable
        }
        // Pair the generated negatives with the exact official source snapshot.
        var metadata: OpaquePointer?
        defer { sqlite3_finalize(metadata) }
        guard sqlite3_prepare_v2(database, "SELECT value FROM invalid.metadata WHERE key = 'source_sha256'", -1, &metadata, nil) == SQLITE_OK,
              sqlite3_step(metadata) == SQLITE_ROW,
              let bytes = sqlite3_column_text(metadata, 0),
              let data = String(cString: bytes).data(using: .utf8),
              (try? JSONDecoder().decode(String.self, from: data)) == lexicon.sha256 else {
            throw LexiconError.databaseUnavailable
        }
        invalidAttached = true
    }

    func yesNoQuestions(lexicon: Lexicon, pattern: AnagramPattern) throws -> [YesNoQuestion] {
        try attachInvalidDatabase(lexicon: lexicon)
        let query = try prepareQuery("yes-no-words", columns: 4)
        defer { sqlite3_finalize(query) }
        guard sqlite3_bind_int(query, 1, Int32(pattern.minimumLength)) == SQLITE_OK,
              sqlite3_bind_int(query, 2, Int32(pattern.maximumLength)) == SQLITE_OK else {
            throw LexiconError.lookupFailed
        }
        var questions: [YesNoQuestion] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(query) {
            case SQLITE_ROW:
                guard let word = sqlite3_column_text(query, 0),
                      let alphagram = sqlite3_column_text(query, 1),
                      sqlite3_column_type(query, 2) == SQLITE_INTEGER else {
                    throw LexiconError.lookupFailed
                }
                guard pattern.matches(String(cString: alphagram)) else { continue }
                let validity = sqlite3_column_int(query, 2)
                guard validity == 0 || validity == 1 else { throw LexiconError.lookupFailed }
                questions.append(YesNoQuestion(word: String(cString: word), isValid: validity == 1,
                                              definition: sqlite3_column_text(query, 3).map { String(cString: $0) }))
            case SQLITE_DONE: return questions
            default: throw LexiconError.lookupFailed
            }
        }
    }

    func anagramRacks(pattern: AnagramPattern) throws -> [String] {
        let query = try prepareQuery("anagram-racks", columns: 1)
        defer { sqlite3_finalize(query) }
        guard sqlite3_bind_int(query, 1, Int32(pattern.minimumLength)) == SQLITE_OK,
              sqlite3_bind_int(query, 2, Int32(pattern.maximumLength)) == SQLITE_OK else {
            throw LexiconError.lookupFailed
        }
        var racks: [String] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(query) {
            case SQLITE_ROW:
                guard let bytes = sqlite3_column_text(query, 0) else { throw LexiconError.lookupFailed }
                let rack = String(cString: bytes)
                if pattern.matches(rack) { racks.append(rack) }
            case SQLITE_DONE: return racks
            default: throw LexiconError.lookupFailed
            }
        }
    }

    func anagramAnswers(alphagram: String) throws -> [AnagramAnswer] {
        let query = try prepareQuery("anagram-answers", columns: 2)
        defer { sqlite3_finalize(query) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_int(query, 1, Int32(alphagram.utf8.count)) == SQLITE_OK,
              sqlite3_bind_text(query, 2, alphagram, -1, transient) == SQLITE_OK else {
            throw LexiconError.lookupFailed
        }
        var answers: [AnagramAnswer] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(query) {
            case SQLITE_ROW:
                guard let bytes = sqlite3_column_text(query, 0) else { throw LexiconError.lookupFailed }
                answers.append(AnagramAnswer(word: String(cString: bytes),
                                             definition: sqlite3_column_text(query, 1).map { String(cString: $0) }))
            case SQLITE_DONE: return answers
            default: throw LexiconError.lookupFailed
            }
        }
    }

    func lookup(entry: SubmittedWord) throws -> WordResult {
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, entry.word, -1, transient) == SQLITE_OK else {
            throw LexiconError.lookupFailed
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let wordBytes = sqlite3_column_text(statement, 0),
                  sqlite3_column_type(statement, 2) == SQLITE_INTEGER else {
                throw LexiconError.lookupFailed
            }
            let definition = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let basePoints = Int(sqlite3_column_int64(statement, 2))
            return WordResult(id: entry.id, word: String(cString: wordBytes), definition: definition,
                              basePoints: basePoints, inputIssue: nil, isValid: true)
        case SQLITE_DONE:
            return WordResult(id: entry.id, word: entry.word, definition: nil, basePoints: nil,
                              inputIssue: nil, isValid: false)
        default:
            throw LexiconError.lookupFailed
        }
    }
}
