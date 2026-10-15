import SwiftUI

struct YesNoQuizView: View {
    @State private var model: YesNoQuizViewModel
    @GestureState private var swipeOffset = CGFloat.zero
    @Environment(\.dismiss) private var dismiss

    init(setup: LearnQuizSetup) {
        _model = State(initialValue: YesNoQuizViewModel(setup: setup))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(model.setup.lexicon.name).foregroundStyle(.secondary)
                    Spacer()
                    if !model.questions.isEmpty {
                        Text(model.counter)
                            .monospacedDigit()
                            .accessibilityLabel("Word \(model.questionIndex + 1) of \(model.questions.count)")
                            .accessibilityIdentifier("yes-no-counter")
                    }
                }
                .font(.subheadline.weight(.semibold))
                feedbackBanner
                switch model.phase {
                case .loading:
                    ProgressView("Loading words…").frame(maxWidth: .infinity, minHeight: 200)
                case .answering:
                    if let question = model.currentQuestion { questionCard(question) }
                case .completed:
                    ContentUnavailableView("Quiz complete", systemImage: "checkmark.seal",
                                           description: Text("You answered \(model.correctCount) of \(model.questions.count) correctly."))
                case .empty:
                    ContentUnavailableView("No matching words", systemImage: "magnifyingglass",
                                           description: Text("No valid or invalid words in \(model.setup.lexicon.name) match \(model.setup.pattern). Try another pattern."))
                case .failed:
                    ContentUnavailableView("Unable to load quiz", systemImage: "exclamationmark.triangle",
                                           description: Text(model.failureMessage ?? "Please try again."))
                }
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(AppStyle.paper)
        .navigationTitle("Yes/No")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if let question = model.currentQuestion {
                    HStack(spacing: 12) {
                        Button { model.answer(markedValid: false, questionID: question.id) } label: {
                            Label("Invalid", systemImage: "arrow.left")
                        }
                        .accessibilityIdentifier("yes-no-invalid")
                        Button { model.answer(markedValid: true, questionID: question.id) } label: {
                            Label("Valid", systemImage: "arrow.right")
                        }
                        .accessibilityIdentifier("yes-no-valid")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if model.phase == .completed || model.phase == .empty || model.phase == .failed {
                    if model.phase == .failed {
                        Button("Try again") { Task { await model.retry() } }
                    }
                    Button("Back to setup") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("yes-no-back-setup")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppStyle.paper)
        }
    }

    private var feedbackBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let feedback = model.feedback {
                Label(feedback.isCorrect ? "Correct" : "Incorrect", systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                    .accessibilityIdentifier("yes-no-verdict")
                Text("\(feedback.question.word) is \(feedback.question.isValid ? "valid" : "invalid") in \(model.setup.lexicon.name).")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("yes-no-feedback-word")
                Text("Answer \(feedback.questionNumber) · You chose \(feedback.markedValid ? "Valid" : "Invalid")")
                    .font(.caption)
                if feedback.question.isValid {
                    Text(feedback.question.displayDefinition)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("yes-no-definition")
                }
            } else {
                Text("Valid or invalid?").font(.headline)
                Text("Swipe left for Invalid. Swipe right for Valid.")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .foregroundStyle(model.feedback == nil ? Color.primary : .white)
        .background(bannerColor, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yes-no-banner")
    }

    private var bannerColor: Color {
        guard let feedback = model.feedback else { return AppStyle.card }
        return feedback.isCorrect ? Color(red: 0.10, green: 0.42, blue: 0.23) : Color(red: 0.68, green: 0.13, blue: 0.15)
    }

    private func questionCard(_ question: YesNoQuestion) -> some View {
        VStack(spacing: 24) {
            Text("WORD \(model.questionIndex + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(question.word)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("yes-no-word")
            HStack {
                Label("Invalid", systemImage: "arrow.left")
                Spacer()
                Label("Valid", systemImage: "arrow.right")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(AppStyle.accent.opacity(swipeOffset == 0 ? 0 : 0.5), lineWidth: 2)
        }
        .offset(x: swipeOffset)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .updating($swipeOffset) { value, offset, _ in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        offset = value.translation.width * 0.4
                    }
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) >= 60, abs(horizontal) > abs(value.translation.height) * 1.3 else { return }
                    model.answer(markedValid: horizontal > 0, questionID: question.id)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Mark valid") { model.answer(markedValid: true, questionID: question.id) }
        .accessibilityAction(named: "Mark invalid") { model.answer(markedValid: false, questionID: question.id) }
    }
}
