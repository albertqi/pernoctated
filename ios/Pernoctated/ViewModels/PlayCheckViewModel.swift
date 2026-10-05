import Foundation
import Observation

@MainActor
@Observable
final class PlayCheckViewModel {
    var input = "" {
        didSet { inputError = nil }
    }
    var selectedLexiconID: String {
        didSet { UserDefaults.standard.set(selectedLexiconID, forKey: "selectedLexiconID") }
    }
    var result: PlayResult?
    var serviceError: String?
    private(set) var inputError: String?
    private(set) var isChecking = false
    let catalog: LexiconCatalog?

    @ObservationIgnored private let repository = LexiconRepository()

    init() {
        do {
            let loaded = try LexiconCatalog.load()
            catalog = loaded
            let savedID = UserDefaults.standard.string(forKey: "selectedLexiconID")
            selectedLexiconID = loaded.lexicons.first(where: { $0.id == savedID })?.id ?? loaded.defaultLexiconID
        } catch {
            catalog = nil
            selectedLexiconID = ""
            serviceError = LexiconError.missingResources.localizedDescription
        }
    }

    var selectedLexicon: Lexicon? {
        catalog?.lexicons.first { $0.id == selectedLexiconID }
    }

    func reportInputError(_ error: Error) {
        inputError = error.localizedDescription
    }

    func clearInput() {
        guard !isChecking else { return }
        input = ""
        result = nil
        serviceError = nil
    }

    func checkPlay() async {
        guard !isChecking, let catalog, let lexicon = selectedLexicon else { return }
        result = nil
        serviceError = nil
        let entries: [SubmittedWord]
        do {
            entries = try catalog.inputRules.parsePlay(input)
        } catch {
            inputError = error.localizedDescription
            return
        }
        inputError = nil
        isChecking = true
        defer { isChecking = false }
        do {
            result = try await repository.lookupPlay(entries: entries, lexicon: lexicon, queryFile: catalog.lookupQuery)
        } catch {
            serviceError = error.localizedDescription
        }
    }
}
