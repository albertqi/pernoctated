import Foundation
import SQLite3

/// A dedicated actor keeps SQLite access serialized and off the main actor.
actor LexiconRepository {
    private var connections: [String: ReadOnlyLexicon] = [:]

    func lookupPlay(entries: [SubmittedWord], lexicon: Lexicon, queryFile: String) throws -> PlayResult {
        guard !entries.isEmpty else { throw InputError.empty }
        let connection: ReadOnlyLexicon
        if let existing = connections[lexicon.id] {
            connection = existing
        } else {
            let opened = try ReadOnlyLexicon(lexicon: lexicon, queryFile: queryFile)
            connections[lexicon.id] = opened
            connection = opened
        }
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

    init(lexicon: Lexicon, queryFile: String) throws {
        guard let databaseURL = Bundle.main.url(forResource: lexicon.databaseFile, withExtension: nil),
              let queryURL = Bundle.main.url(forResource: queryFile, withExtension: nil) else {
            throw LexiconError.missingResources
        }
        let sql = try String(contentsOf: queryURL, encoding: .utf8)
        var openedDatabase: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
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
