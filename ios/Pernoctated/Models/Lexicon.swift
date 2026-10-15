import Foundation

struct Lexicon: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let databaseFile: String
    let invalidDatabaseFile: String
    let wordCount: Int
    let sha256: String
}

struct LexiconCatalog: Decodable, Sendable {
    let schemaVersion: Int
    let defaultLexiconID: String
    let lookupQuery: String
    let inputRules: InputRules
    let lexicons: [Lexicon]

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw LexiconError.missingResources
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 4,
              !catalog.lexicons.isEmpty,
              catalog.lexicons.contains(where: { $0.id == catalog.defaultLexiconID }),
              catalog.inputRules.minimumLength > 0,
              catalog.inputRules.maximumLines > 0,
              catalog.inputRules.maximumLength >= catalog.inputRules.minimumLength else {
            throw LexiconError.missingResources
        }
        return catalog
    }
}

struct InputRules: Decodable, Sendable {
    let maximumLines: Int
    let minimumLength: Int
    let maximumLength: Int
    let trimCodePoints: [UInt32]

    private var trimming: CharacterSet {
        CharacterSet(charactersIn: String(String.UnicodeScalarView(
            trimCodePoints.compactMap(Unicode.Scalar.init)
        )))
    }

    /// Validate a native text edit before UIKit applies it, preserving cursor and undo behavior.
    func validateEditorChange(in text: String, range: NSRange, replacement: String) throws {
        guard let swiftRange = Range(range, in: text) else { throw InputError.invalidEdit }
        let proposed = text.replacingCharacters(in: swiftRange, with: replacement)
        try validateLineCount(proposed)
        if replacement.contains(where: \.isNewline) {
            // Existing blank lines left by deletion elsewhere should not block this edit.
            let prefix = text[..<swiftRange.lowerBound]
            let linePrefix = prefix.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
            let suffix = text[swiftRange.upperBound...]
            let lineSuffix = suffix.firstIndex(where: \.isNewline).map { suffix[...$0] } ?? suffix[...]
            let affected = String(linePrefix) + replacement + String(lineSuffix)
            let lines = affected.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            guard lines.dropLast().allSatisfy({
                !String($0).trimmingCharacters(in: trimming).isEmpty
            }) else { throw InputError.emptyLine }
        }
    }

    private func validateLineCount(_ input: String) throws {
        let lineCount = input.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
        guard lineCount <= maximumLines else { throw InputError.maximumLines(maximumLines) }
    }

    func parsePlay(_ input: String) throws -> [SubmittedWord] {
        // Also enforce the limit for callers that do not use the native editor.
        try validateLineCount(input)
        let entries = input.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated().compactMap { index, line -> SubmittedWord? in
                let trimmed = String(line).trimmingCharacters(in: trimming)
                guard !trimmed.isEmpty else { return nil }
                do {
                    return SubmittedWord(id: index, word: try normalize(trimmed), inputIssue: nil)
                } catch {
                    // ASCII-only uppercasing also gives consistently displayed invalid entries,
                    // without turning Unicode ligatures or sharp S into different words.
                    let displayWord = String(String.UnicodeScalarView(trimmed.unicodeScalars.map {
                        (97...122).contains($0.value) ? Unicode.Scalar($0.value - 32)! : $0
                    }))
                    return SubmittedWord(id: index, word: displayWord, inputIssue: error.localizedDescription)
                }
            }
        guard !entries.isEmpty else { throw InputError.empty }
        return entries
    }

    func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: trimming)
        guard !trimmed.isEmpty else { throw InputError.empty }
        let bytes = Array(trimmed.utf8)
        guard bytes.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else {
            throw InputError.lettersOnly
        }
        guard (minimumLength...maximumLength).contains(bytes.count) else {
            throw InputError.length(minimumLength, maximumLength)
        }
        return String(decoding: bytes.map { (97...122).contains($0) ? $0 - 32 : $0 }, as: UTF8.self)
    }
}

enum InputError: LocalizedError {
    case empty
    case emptyLine
    case maximumLines(Int)
    case invalidEdit
    case lettersOnly
    case length(Int, Int)

    var errorDescription: String? {
        switch self {
        case .empty: "Enter at least one word, one per line."
        case .emptyLine: "Enter a character on each line before starting another."
        case let .maximumLines(maximum): "A play can have at most \(maximum) lines."
        case .invalidEdit: "That edit could not be applied. Please try again."
        case .lettersOnly: "Use letters A-Z only, with one word per line."
        case let .length(minimum, maximum): "Words must contain \(minimum)-\(maximum) letters."
        }
    }
}

enum LexiconError: LocalizedError {
    case missingResources
    case databaseUnavailable
    case lookupFailed

    var errorDescription: String? {
        switch self {
        case .missingResources: "The lexicon resources could not be loaded. Please reinstall the app."
        case .databaseUnavailable: "This lexicon could not be opened. Please try again or reinstall the app."
        case .lookupFailed: "The play could not be checked. Please try again."
        }
    }
}

struct SubmittedWord: Sendable {
    let id: Int
    let word: String
    let inputIssue: String?
}

struct WordResult: Hashable, Identifiable, Sendable {
    // The source-line ID preserves duplicate words as separate entries.
    let id: Int
    let word: String
    let definition: String?
    let basePoints: Int?
    let inputIssue: String?
    // Validity is based on row existence, not whether a definition is nonempty.
    let isValid: Bool
}

struct PlayResult: Hashable, Identifiable, Sendable {
    let id = UUID()
    let lexicon: Lexicon
    let words: [WordResult]

    var isValid: Bool { !words.isEmpty && words.allSatisfy(\.isValid) }
    var invalidWords: [WordResult] { words.filter { !$0.isValid } }
}
