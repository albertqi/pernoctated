import Foundation

enum HookSide: String, Sendable {
    case front, back
    var instruction: String { "Find all \(rawValue) hooks" }
    func display(_ word: String) -> String { self == .front ? "_" + word : word + "_" }
}

struct HookQuestion: Identifiable, Sendable {
    let word: String
    let side: HookSide
    var id: String { word }
}

struct HookAnswer: Identifiable, Sendable {
    let letter: String
    let word: String
    let definition: String?
    var id: String { letter }
    var displayDefinition: String {
        definition.flatMap { $0.isEmpty ? nil : $0 } ?? "No definition is available in this lexicon."
    }
}

enum HooksPhase { case loading, answering, review, completed, empty, failed }
