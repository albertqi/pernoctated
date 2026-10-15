import Foundation
import Observation

@MainActor
@Observable
final class LearnSetupViewModel {
    let catalog: LexiconCatalog?
    let presets: [LearnPreset]
    var selectedLexiconID: String
    var selectedPresetID = "none"
    var customPattern = ""
    var mode: LearnQuizMode = .anagram
    var startedSetup: LearnQuizSetup?
    let resourceError: String?

    init() {
        do {
            let catalog = try LexiconCatalog.load()
            let presets = try LearnPresets.load()
            self.catalog = catalog
            self.presets = presets
            selectedLexiconID = catalog.defaultLexiconID
            resourceError = nil
        } catch {
            catalog = nil
            presets = []
            selectedLexiconID = ""
            resourceError = error.localizedDescription
        }
    }

    var selectedLexicon: Lexicon? { catalog?.lexicons.first { $0.id == selectedLexiconID } }
    var selectedPreset: LearnPreset? { presets.first { $0.id == selectedPresetID } }
    var isCustomPattern: Bool { selectedPreset?.pattern == nil }
    var displayedPattern: String { selectedPreset?.pattern ?? customPattern }

    // Normalize ASCII only; Unicode letters must not silently become a different rack.
    var normalizedPattern: String {
        let trimmed = displayedPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.map {
            (97...122).contains($0.value) ? Unicode.Scalar($0.value - 32)! : $0
        }))
    }

    var patternError: String? {
        guard let rules = catalog?.inputRules else { return resourceError }
        do {
            _ = try AnagramPattern(normalizedPattern, minimumWordLength: rules.minimumLength, maximumWordLength: rules.maximumLength)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var canStart: Bool { selectedLexicon != nil && patternError == nil && resourceError == nil }

    func startQuiz() {
        guard canStart, let lexicon = selectedLexicon else { return }
        startedSetup = LearnQuizSetup(lexicon: lexicon, pattern: normalizedPattern, presetName: selectedPreset?.name ?? "None", mode: mode)
    }
}
