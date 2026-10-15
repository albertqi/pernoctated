import SwiftUI

struct HooksQuizView: View {
    @State private var model: HooksQuizViewModel
    @Environment(\.dismiss) private var dismiss

    init(setup: LearnQuizSetup) { _model = State(initialValue: HooksQuizViewModel(setup: setup)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(model.setup.lexicon.name).foregroundStyle(.secondary)
                    Spacer()
                    if !model.questions.isEmpty {
                        Text(model.counter).monospacedDigit()
                            .accessibilityLabel("Word \(model.questionIndex + 1) of \(model.questions.count)")
                            .accessibilityIdentifier("hooks-counter")
                    }
                }
                .font(.subheadline.weight(.semibold))
                switch model.phase {
                case .loading:
                    ProgressView("Loading hooks…").frame(maxWidth: .infinity, minHeight: 200)
                case .answering, .review:
                    if let question = model.question {
                        VStack(spacing: 12) {
                            Text(question.side.instruction).font(.headline)
                                .accessibilityIdentifier("hooks-direction")
                            Text(question.side.display(question.word))
                                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                                .lineLimit(1).minimumScaleFactor(0.35)
                                .accessibilityLabel("\(question.word), \(question.side.rawValue) hooks")
                                .accessibilityIdentifier("hooks-word")
                            Text(model.selected.isEmpty ? "No letters selected" : model.selected.sorted().joined(separator: "  "))
                                .font(.subheadline.monospaced())
                                .accessibilityIdentifier("hooks-selection")
                            if model.phase == .answering {
                                Text("Tap letters to select or deselect. Select none if there are no hooks.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(16)
                        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if model.phase == .review { reviewSummary }
                    letterGrid
                    if model.phase == .review { answerList }
                case .completed:
                    ContentUnavailableView("Quiz complete", systemImage: "checkmark.seal",
                                           description: Text("You found every hook with no incorrect selections on \(model.correctCount) of \(model.questions.count) words."))
                case .empty:
                    ContentUnavailableView("No matching words", systemImage: "magnifyingglass",
                                           description: Text("No valid words in \(model.setup.lexicon.name) match \(model.setup.pattern). Try another pattern."))
                case .failed:
                    ContentUnavailableView("Unable to load hooks", systemImage: "exclamationmark.triangle",
                                           description: Text(model.failureMessage ?? "Please try again."))
                }
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .id(model.questionIndex)
        .background(AppStyle.paper)
        .navigationTitle("Hooks").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                switch model.phase {
                case .answering:
                    Button("Check") { model.check() }
                        .accessibilityIdentifier("hooks-check")
                case .review:
                    Button("Next") { Task { await model.next() } }
                        .accessibilityIdentifier("hooks-next")
                case .failed:
                    Button("Try again") { Task { await model.retry() } }
                        .accessibilityIdentifier("hooks-retry")
                    Button("Back to setup") { dismiss() }
                case .completed, .empty:
                    Button("Back to setup") { dismiss() }
                        .accessibilityIdentifier("hooks-back-setup")
                case .loading: EmptyView()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(AppStyle.paper)
        }
    }

    private var reviewSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.isCorrect ? "Correct" : "Not quite", systemImage: model.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline).accessibilityIdentifier("hooks-verdict")
            if model.answers.isEmpty { Text("This word has no \(model.question?.side.rawValue ?? "") hooks.") }
            if !model.wrongLetters.isEmpty { Text("Incorrect: " + model.wrongLetters.joined(separator: ", ")) }
            if !model.missed.isEmpty { Text("Missed: " + model.missed.map(\.letter).joined(separator: ", ")) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .foregroundStyle(.white)
        .background(model.isCorrect ? Color(red: 0.10, green: 0.42, blue: 0.23) : Color(red: 0.68, green: 0.13, blue: 0.15),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var letterGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 4), count: 6), spacing: 6) {
            ForEach(model.letters, id: \.self) { letter in
                Group {
                    if model.phase == .answering {
                        Button { model.toggle(letter) } label: { letterTile(letter) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(letter), \(model.selected.contains(letter) ? "selected" : "not selected")")
                            .accessibilityAddTraits(model.selected.contains(letter) ? [.isSelected] : [])
                            .accessibilityIdentifier("hook-letter-\(letter)")
                    } else {
                        letterTile(letter)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(letter), \(tileStatus(letter))")
                            .accessibilityIdentifier("hook-letter-\(letter)")
                    }
                }
            }
        }
    }

    private func letterTile(_ letter: String) -> some View {
        VStack(spacing: 2) {
            Text(letter).font(.title3.monospaced().weight(.semibold))
            if model.phase == .review {
                Text(tileStatus(letter)).font(.system(size: 9, weight: .semibold))
            } else {
                Image(systemName: model.selected.contains(letter) ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .foregroundStyle(tileForeground(letter))
        .background(tileBackground(letter), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isMissed(letter) ? Color.orange : Color.secondary.opacity(0.25), lineWidth: isMissed(letter) ? 2 : 1)
        }
        .contentShape(Rectangle())
    }

    private func isMissed(_ letter: String) -> Bool {
        model.phase == .review && model.answerLetters.contains(letter) && !model.selected.contains(letter)
    }

    private func tileStatus(_ letter: String) -> String {
        if model.selected.contains(letter) { return model.answerLetters.contains(letter) ? "Correct" : "Wrong" }
        return model.answerLetters.contains(letter) ? "Missed" : "—"
    }

    private func tileBackground(_ letter: String) -> Color {
        guard model.selected.contains(letter) else { return AppStyle.card }
        if model.phase == .answering { return AppStyle.accent }
        return model.answerLetters.contains(letter) ? Color(red: 0.10, green: 0.42, blue: 0.23) : Color(red: 0.68, green: 0.13, blue: 0.15)
    }

    private func tileForeground(_ letter: String) -> Color { model.selected.contains(letter) ? .white : .primary }

    private var answerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.answers.isEmpty { Text("Hook words").font(.headline) }
            ForEach(model.answers) { answer in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(answer.word) · \(model.selected.contains(answer.letter) ? "Correct" : "Missed")",
                          systemImage: model.selected.contains(answer.letter) ? "checkmark.circle.fill" : "minus.circle")
                        .font(.headline)
                    Text(answer.displayDefinition).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("hook-answer-\(answer.letter)")
            }
        }
    }
}
