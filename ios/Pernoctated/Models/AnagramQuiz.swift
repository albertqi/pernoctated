import Foundation

/// An unordered rack: letters are required, ? consumes one letter, * consumes any extras.
struct AnagramPattern: Sendable {
    let minimumLength: Int
    let maximumLength: Int
    private let required: [UInt8: Int]
    private let fixedSlots: Int
    private let allowsExtras: Bool

    init(_ pattern: String, minimumWordLength: Int, maximumWordLength: Int) throws {
        guard !pattern.isEmpty else { throw AnagramError.pattern("Enter a pattern or choose a preset.") }
        let bytes = Array(pattern.utf8)
        guard bytes.allSatisfy({ (65...90).contains($0) || $0 == 63 || $0 == 42 }) else {
            throw AnagramError.pattern("Use letters A-Z, ? for one letter, or * for extra letters.")
        }
        guard bytes.filter({ $0 == 42 }).count <= 1 else {
            throw AnagramError.pattern("Use at most one * in a pattern.")
        }
        fixedSlots = bytes.filter { $0 != 42 }.count
        allowsExtras = bytes.contains(42)
        guard fixedSlots <= maximumWordLength else {
            throw AnagramError.pattern("Use at most \(maximumWordLength) letters and ? symbols.")
        }
        guard allowsExtras || fixedSlots >= minimumWordLength else {
            throw AnagramError.pattern("Use at least \(minimumWordLength) letters or ? symbols, or add *.")
        }
        minimumLength = max(minimumWordLength, fixedSlots)
        maximumLength = allowsExtras ? maximumWordLength : fixedSlots
        required = Dictionary(bytes.filter { (65...90).contains($0) }.map { ($0, 1) }, uniquingKeysWith: +)
    }

    func matches(_ alphagram: String) -> Bool {
        let letters = Array(alphagram.utf8)
        guard (minimumLength...maximumLength).contains(letters.count) else { return false }
        let counts = Dictionary(letters.map { ($0, 1) }, uniquingKeysWith: +)
        return required.allSatisfy { counts[$0.key, default: 0] >= $0.value }
    }
}

enum AnagramError: LocalizedError {
    case pattern(String)
    var errorDescription: String? {
        switch self { case .pattern(let message): message }
    }
}

struct AnagramAnswer: Identifiable, Hashable, Sendable {
    let word: String
    let definition: String?
    var id: String { word }
    var displayDefinition: String {
        definition.flatMap { $0.isEmpty ? nil : $0 } ?? "No definition is available in this lexicon."
    }
}

struct LetterTile: Identifiable, Hashable {
    let id: Int
    let letter: String
}

enum AnagramPhase {
    case loading, answering, review, completed, empty, failed
}
