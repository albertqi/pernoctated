import SwiftUI

struct AnagramQuizView: View {
    @State private var model: AnagramQuizViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var rackFrames: [Int: CGRect] = [:]
    @State private var draggingTile: LetterTile?
    @State private var dragLocation = CGPoint.zero

    init(setup: LearnQuizSetup) {
        _model = State(initialValue: AnagramQuizViewModel(setup: setup))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.racks.isEmpty, model.phase != .completed {
                HStack {
                    Text(model.setup.lexicon.name).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.counter)
                        .monospacedDigit()
                        .accessibilityLabel("Alphagram \(model.roundIndex + 1) of \(model.racks.count)")
                        .accessibilityIdentifier("quiz-counter")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            switch model.phase {
            case .loading:
                Spacer()
                ProgressView("Loading anagrams…")
                Spacer()
            case .answering:
                answering
            case .review:
                review
            case .completed:
                message(title: "Quiz complete", symbol: "checkmark.seal", detail: "You found \(model.totalGuessed) of \(model.totalAnswers) words across \(model.racks.count) \(model.racks.count == 1 ? "alphagram" : "alphagrams").")
            case .empty:
                message(title: "No matching words", symbol: "magnifyingglass", detail: "No words in \(model.setup.lexicon.name) match \(model.setup.pattern). Try a different pattern.")
            case .failed:
                message(title: "Unable to load quiz", symbol: "exclamationmark.triangle", detail: model.failureMessage ?? "Please try again.")
            }
        }
        .background(AppStyle.paper)
        .navigationTitle("Anagram")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { draggingTile = nil }
        .onChange(of: model.phase) { _, _ in draggingTile = nil }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if model.phase == .answering { rack }
                if model.phase == .answering || model.phase == .review {
                    Button { Task { await model.next() } } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("quiz-next")
                } else if model.phase == .completed || model.phase == .empty || model.phase == .failed {
                    if model.phase == .failed {
                        Button("Try again") { Task { await model.retry() } }
                    }
                    Button("Back to setup") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("quiz-back-setup")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppStyle.paper)
        }
    }

    private var answering: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.alphagram)
                    .font(.system(.title, design: .monospaced, weight: .semibold))
                    .tracking(2)
                    .accessibilityIdentifier("quiz-alphagram")
                Text("Tap the tiles to make a word. Using every tile submits it automatically. Tap a chosen tile to return it. Drag rack tiles to reorder them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.selected) { tile in
                        tileButton(tile, selected: true) { model.returnTile(tile) }
                    }
                }
                .frame(minHeight: 50, alignment: .top)
                .padding(12)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("quiz-chosen-tiles")
                if let feedback = model.feedback {
                    Text(feedback)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.lastGuessWasValid ? AppStyle.accent : .red)
                        .accessibilityIdentifier("quiz-feedback")
                }
                Text("FOUND WORDS · \(model.guessed.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if model.guessed.isEmpty {
                    Text("Your valid words and definitions will appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.guessed) { answer in answerCard(answer) }
            }
            .padding(20)
        }
    }

    private var rack: some View {
        VStack(spacing: 12) {
            HStack {
                Button { model.shuffle() } label: { Label("Shuffle", systemImage: "shuffle") }
                    .accessibilityIdentifier("quiz-shuffle")
                Spacer()
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .accessibilityIdentifier("quiz-reset")
            }
            .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(model.rackOrder.indices, id: \.self) { slot in
                    rackSlot(slot)
                }
            }
            .coordinateSpace(name: "quizRack")
            .onPreferenceChange(RackSlotFramesKey.self) { rackFrames = $0 }
            .overlay(alignment: .topLeading) {
                if let tile = draggingTile {
                    tileLabel(tile)
                        .frame(width: rackFrames.values.first?.width ?? 44, height: 46)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("quiz-rack")
        }
    }

    private func rackSlot(_ slot: Int) -> some View {
        let tile = model.rackOrder[slot]
        let isSelected = model.selected.contains(tile)
        return ZStack {
            if isSelected {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .accessibilityHidden(true)
            } else {
                tileButton(tile, selected: false) { model.selectTile(tile) }
                    .opacity(draggingTile == tile ? 0.25 : 1)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8, coordinateSpace: .named("quizRack"))
                            .onChanged { value in
                                guard model.phase == .answering else { return }
                                draggingTile = tile
                                dragLocation = value.location
                            }
                            .onEnded { value in
                                if let destination = rackFrames.first(where: {
                                    $0.value.insetBy(dx: -4, dy: -4).contains(value.location)
                                })?.key {
                                    model.moveRackTile(tile, toSlot: destination)
                                }
                                draggingTile = nil
                            }
                    )
                    .accessibilityHint("Tap to choose. Drag to another rack slot to reorder.")
                    .accessibilityAction(named: "Move left") { model.moveRackTile(tile, toSlot: slot - 1) }
                    .accessibilityAction(named: "Move right") { model.moveRackTile(tile, toSlot: slot + 1) }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: RackSlotFramesKey.self,
                                       value: [slot: geometry.frame(in: .named("quizRack"))])
            }
        }
    }

    private func tileLabel(_ tile: LetterTile) -> some View {
        Text(tile.letter)
            .font(.system(.title2, design: .monospaced, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(Color.primary)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(AppStyle.accent.opacity(0.4)) }
    }

    private func tileButton(_ tile: LetterTile, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileLabel(tile)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tile.letter), \(selected ? "chosen" : "rack") tile \(tile.id + 1)")
        .accessibilityIdentifier("quiz-\(selected ? "chosen" : "rack")-tile-\(tile.id)")
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.alphagram)
                    .font(.system(.title, design: .monospaced, weight: .semibold))
                    .accessibilityIdentifier("quiz-review-alphagram")
                Text("You found \(model.guessed.count) of \(model.answers.count) anagrams.")
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    reviewColumn(title: "Correct · \(model.guessed.count)", words: model.guessed, empty: "No words guessed.")
                    reviewColumn(title: "Missed · \(model.missed.count)", words: model.missed, empty: "None — you found them all!")
                }
            }
            .padding(20)
        }
    }

    private func reviewColumn(title: String, words: [AnagramAnswer], empty: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if words.isEmpty { Text(empty).font(.footnote).foregroundStyle(.secondary) }
            ForEach(words) { answer in answerCard(answer) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answerCard(_ answer: AnagramAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.word)
                .font(.system(.headline, design: .monospaced))
                .accessibilityIdentifier("quiz-word-\(answer.word)")
            Text(answer.displayDefinition)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func message(title: String, symbol: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
    }
}

private struct RackSlotFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
