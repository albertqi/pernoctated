import Foundation

struct LearnPreset: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let pattern: String?
}

struct LearnPresets: Decodable {
    let presets: [LearnPreset]

    static func load() throws -> [LearnPreset] {
        guard let url = Bundle.main.url(forResource: "learn-presets", withExtension: "json") else {
            throw LexiconError.missingResources
        }
        let loaded = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).presets
        guard loaded.first?.id == "none", loaded.first?.pattern == nil,
              Set(loaded.map(\.id)).count == loaded.count else {
            throw LexiconError.missingResources
        }
        return loaded
    }
}

enum LearnQuizMode: String, CaseIterable, Identifiable {
    case yesNo = "Yes/No"
    case anagram = "Anagram"
    case hooks = "Hooks"
    var id: Self { self }
}

struct LearnQuizSetup: Identifiable, Hashable {
    let id = UUID()
    let lexicon: Lexicon
    let pattern: String
    let presetName: String
    var mode: LearnQuizMode = .anagram
}
