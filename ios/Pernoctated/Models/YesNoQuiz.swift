import Foundation

struct YesNoQuestion: Identifiable, Hashable, Sendable {
    let word: String
    let isValid: Bool
    let definition: String?
    var id: String { word }

    var displayDefinition: String {
        definition.flatMap { $0.isEmpty ? nil : $0 } ?? "No definition is available in this lexicon."
    }
}

struct YesNoFeedback: Identifiable {
    let question: YesNoQuestion
    let markedValid: Bool
    let questionNumber: Int
    var id: String { question.id }
    var isCorrect: Bool { markedValid == question.isValid }
}

enum YesNoPhase {
    case loading, answering, completed, empty, failed
}
