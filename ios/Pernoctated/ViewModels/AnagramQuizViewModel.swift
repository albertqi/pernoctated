import Foundation
import Observation

@MainActor
@Observable
final class AnagramQuizViewModel {
    let setup: LearnQuizSetup
    private(set) var phase: AnagramPhase = .loading
    private(set) var racks: [String] = []
    private(set) var roundIndex = 0
    private(set) var answers: [AnagramAnswer] = []
    private(set) var guessed: [AnagramAnswer] = []
    private(set) var rackOrder: [LetterTile] = []
    private(set) var selected: [LetterTile] = []
    private(set) var feedback: String?
    private(set) var lastGuessWasValid = false
    private(set) var failureMessage: String?
    private(set) var totalGuessed = 0
    private(set) var totalAnswers = 0
    @ObservationIgnored private let repository = LexiconRepository()
    @ObservationIgnored private var didLoad = false

    init(setup: LearnQuizSetup) { self.setup = setup }

    var alphagram: String { racks.indices.contains(roundIndex) ? racks[roundIndex] : "" }
    var counter: String { "\(min(roundIndex + 1, racks.count))/\(racks.count)" }
    var remainingTiles: [LetterTile] { rackOrder.filter { !selected.contains($0) } }
    var formedWord: String { selected.map(\.letter).joined() }
    var missed: [AnagramAnswer] { answers.filter { !guessed.contains($0) } }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        phase = .loading
        do {
            let rules = try LexiconCatalog.load().inputRules
            let pattern = try AnagramPattern(setup.pattern, minimumWordLength: rules.minimumLength, maximumWordLength: rules.maximumLength)
            racks = try await repository.anagramRacks(lexicon: setup.lexicon, pattern: pattern).shuffled()
            try Task.checkCancellation()
            guard !racks.isEmpty else { phase = .empty; return }
            await loadRound()
        } catch is CancellationError {
            didLoad = false
        } catch {
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func loadRound() async {
        phase = .loading
        feedback = nil
        selected = []
        guessed = []
        do {
            answers = try await repository.anagramAnswers(lexicon: setup.lexicon, alphagram: alphagram)
            try Task.checkCancellation()
            guard !answers.isEmpty else { throw LexiconError.lookupFailed }
            rackOrder = alphagram.enumerated().map { LetterTile(id: $0.offset, letter: String($0.element)) }
            phase = .answering
        } catch is CancellationError {
            didLoad = false
        } catch {
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }

    func selectTile(_ tile: LetterTile) {
        guard phase == .answering, remainingTiles.contains(tile) else { return }
        feedback = nil
        selected.append(tile)
        if selected.count == rackOrder.count { submit() }
    }

    func returnTile(_ tile: LetterTile) {
        guard phase == .answering else { return }
        selected.removeAll { $0.id == tile.id }
        feedback = nil
    }

    /// Move one tile to a rack slot. Selected tiles retain their identity and leave gaps.
    func moveRackTile(_ tile: LetterTile, toSlot destination: Int) {
        guard phase == .answering, !selected.contains(tile),
              let source = rackOrder.firstIndex(of: tile),
              rackOrder.indices.contains(destination), source != destination else { return }
        rackOrder.remove(at: source)
        rackOrder.insert(tile, at: destination)
    }

    func shuffle() {
        guard phase == .answering else { return }
        // Only reorder unselected tile slots; used tiles retain their restoration positions.
        let remainingIDs = Set(remainingTiles.map(\.id))
        var shuffled = remainingTiles.shuffled().makeIterator()
        rackOrder = rackOrder.map { remainingIDs.contains($0.id) ? shuffled.next()! : $0 }
    }

    func reset() {
        guard phase == .answering else { return }
        selected = []
        rackOrder.sort { $0.id < $1.id }
        feedback = nil
    }

    private func submit() {
        let word = formedWord
        if let answer = answers.first(where: { $0.word == word }) {
            lastGuessWasValid = true
            if guessed.contains(answer) {
                feedback = "\(word) — already found."
            } else {
                guessed.append(answer)
                feedback = "\(word) — valid!"
            }
        } else {
            lastGuessWasValid = false
            feedback = "\(word) — not valid in \(setup.lexicon.name)."
        }
        // Keep rackOrder intact, including any prior shuffle.
        selected = []
    }

    func next() async {
        switch phase {
        case .answering:
            selected = []
            feedback = nil
            totalGuessed += guessed.count
            totalAnswers += answers.count
            phase = .review
        case .review:
            if roundIndex + 1 == racks.count {
                phase = .completed
            } else {
                roundIndex += 1
                await loadRound()
            }
        default: break
        }
    }

    func retry() async {
        didLoad = false
        roundIndex = 0
        totalGuessed = 0
        totalAnswers = 0
        await load()
    }
}
