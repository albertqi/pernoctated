import Foundation
import Observation

@MainActor
@Observable
final class YesNoQuizViewModel {
    let setup: LearnQuizSetup
    private(set) var phase: YesNoPhase = .loading
    private(set) var questions: [YesNoQuestion] = []
    private(set) var questionIndex = 0
    private(set) var feedback: YesNoFeedback?
    private(set) var correctCount = 0
    private(set) var failureMessage: String?
    @ObservationIgnored private let repository = LexiconRepository()
    @ObservationIgnored private var didLoad = false

    init(setup: LearnQuizSetup) { self.setup = setup }

    var currentQuestion: YesNoQuestion? {
        phase == .answering && questions.indices.contains(questionIndex) ? questions[questionIndex] : nil
    }
    var counter: String { "\(min(questionIndex + 1, questions.count))/\(questions.count)" }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        phase = .loading
        do {
            let rules = try LexiconCatalog.load().inputRules
            let pattern = try AnagramPattern(setup.pattern, minimumWordLength: rules.minimumLength, maximumWordLength: rules.maximumLength)
            let loaded = try await repository.yesNoQuestions(lexicon: setup.lexicon, pattern: pattern)
            try Task.checkCancellation()
            questions = loaded
            questionIndex = 0
            correctCount = 0
            feedback = nil
            phase = loaded.isEmpty ? .empty : .answering
        } catch is CancellationError {
            didLoad = false
        } catch {
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// The expected ID makes stale/double actions unable to answer the next card.
    func answer(markedValid: Bool, questionID: String) {
        guard let question = currentQuestion, question.id == questionID else { return }
        let answered = YesNoFeedback(question: question, markedValid: markedValid, questionNumber: questionIndex + 1)
        feedback = answered
        if answered.isCorrect { correctCount += 1 }
        if questionIndex + 1 == questions.count {
            phase = .completed
        } else {
            questionIndex += 1
        }
    }

    func retry() async {
        didLoad = false
        await load()
    }
}
