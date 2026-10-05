import SwiftUI

struct PlayResultView: View {
    let result: PlayResult
    @Environment(\.dismiss) private var dismiss

    private var statusColor: Color { result.isValid ? AppStyle.accent : Color(uiColor: .systemRed) }
    private var visibleWords: [WordResult] { result.isValid ? result.words : result.invalidWords }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                summary
                Text(result.isValid ? "WORDS & DEFINITIONS" : "INVALID WORDS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                ForEach(visibleWords) { word in
                    wordCard(word)
                }

                if result.isValid {
                    Text("Base points use letter values only. Blanks, board multipliers, and bingo bonuses aren’t included.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { dismiss() } label: {
                    Label("Check another play", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("check-another-play")
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(AppStyle.paper)
        .navigationTitle("Play result")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(result.lexicon.name)
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppStyle.card, in: Capsule())
                Spacer()
                Image(systemName: result.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
            }
            Text(result.isValid ? "Valid play" : "Not valid")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .foregroundStyle(statusColor)
                .accessibilityIdentifier("result-verdict")
            Text(summaryText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("result-summary")
        }
    }

    private var summaryText: String {
        if result.isValid {
            let count = result.words.count
            return count == 1
                ? "Your word is accepted in \(result.lexicon.name)."
                : "All \(count) words are accepted in \(result.lexicon.name)."
        }
        let count = result.invalidWords.count
        return "\(count) of \(result.words.count) \(result.words.count == 1 ? "word" : "words") \(count == 1 ? "is" : "are") invalid in \(result.lexicon.name)."
    }

    private func wordCard(_ word: WordResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(word.word)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("result-word-\(word.id)")
                if result.isValid, let points = word.basePoints {
                    Text("\(points) pts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppStyle.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppStyle.accent.opacity(0.08), in: Capsule())
                        .fixedSize()
                        .accessibilityLabel("\(points) base points")
                        .accessibilityIdentifier("result-points-\(word.id)")
                }
            }
            if result.isValid {
                Text(word.definition.flatMap { $0.isEmpty ? nil : $0 } ?? "No definition is available in this lexicon.")
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("result-definition-\(word.id)")
            } else if let issue = word.inputIssue {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}
