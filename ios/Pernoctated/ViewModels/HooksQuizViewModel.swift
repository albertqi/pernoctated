import Foundation
import Observation

@MainActor
@Observable
final class HooksQuizViewModel {
    let setup: LearnQuizSetup
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private(set) var phase: HooksPhase = .loading
    private(set) var questions: [HookQuestion] = []
    private(set) var questionIndex = 0
    private(set) var answers: [HookAnswer] = []
    private(set) var selected: Set<String> = []
    private(set) var correctCount = 0
    private(set) var failureMessage: String?
    @ObservationIgnored private let repository = LexiconRepository()
    @ObservationIgnored private var didLoad = false

    init(setup: LearnQuizSetup) { self.setup = setup }

    var question: HookQuestion? { questions.indices.contains(questionIndex) ? questions[questionIndex] : nil }
    var counter: String { "\(min(questionIndex + 1, questions.count))/\(questions.count)" }
    var answerLetters: Set<String> { Set(answers.map(\.letter)) }
    var isCorrect: Bool { selected == answerLetters }
    var missed: [HookAnswer] { answers.filter { !selected.contains($0.letter) } }
    var wrongLetters: [String] { selected.subtracting(answerLetters).sorted() }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        if !questions.isEmpty { await loadRound(); return }
        phase = .loading
        do {
            let rules = try LexiconCatalog.load().inputRules
            let pattern = try AnagramPattern(setup.pattern, minimumWordLength: rules.minimumLength, maximumWordLength: rules.maximumLength)
            let deck = try await repository.hookQuestions(lexicon: setup.lexicon, pattern: pattern)
            try Task.checkCancellation()
            questions = deck
            questionIndex = 0
            correctCount = 0
            if deck.isEmpty { phase = .empty } else { await loadRound() }
        } catch is CancellationError {
            didLoad = false
        } catch {
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func loadRound() async {
        phase = .loading
        selected = []
        answers = []
        failureMessage = nil
        guard let question else { return }
        do {
            let loaded = try await repository.hookAnswers(lexicon: setup.lexicon, question: question)
            try Task.checkCancellation()
            answers = loaded
            phase = .answering
        } catch is CancellationError {
            // The same word/direction can be retried after tab/navigation cancellation.
            didLoad = false
        } catch {
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }

    func toggle(_ letter: String) {
        guard phase == .answering, letters.contains(letter) else { return }
        if !selected.insert(letter).inserted { selected.remove(letter) }
    }

    func check() {
        guard phase == .answering else { return }
        if isCorrect { correctCount += 1 }
        phase = .review
    }

    func next() async {
        guard phase == .review else { return }
        if questionIndex + 1 == questions.count { phase = .completed } else {
            questionIndex += 1
            await loadRound()
        }
    }

    func retry() async {
        guard phase == .failed else { return }
        if questions.isEmpty { didLoad = false; await load() } else { await loadRound() }
    }
}
