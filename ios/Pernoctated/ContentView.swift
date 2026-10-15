import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            JudgeView()
                .tabItem { Label("Judge", systemImage: "checkmark.seal") }
            LearnSetupView()
                .tabItem { Label("Learn", systemImage: "book") }
        }
        .tint(AppStyle.accent)
    }
}

struct JudgeView: View {
    @State private var model = PlayCheckViewModel()
    @State private var isWordsFocused = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        lexiconPicker
                        wordEntry(height: max(160, geometry.size.height - 285))
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(AppStyle.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                submissionBar
            }
            .navigationTitle("Pernoctated")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $model.result) { result in
                PlayResultView(result: result)
            }
            .alert("Unable to check play", isPresented: Binding(
                get: { model.serviceError != nil },
                set: { if !$0 { model.serviceError = nil } }
            )) {
                Button("OK", role: .cancel) { model.serviceError = nil }
            } message: {
                Text(model.serviceError ?? "Please try again.")
            }
        }
        .tint(AppStyle.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "character.book.closed.fill")
                .font(.title2)
                .foregroundStyle(AppStyle.accent)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Check a play")
                    .font(.system(.title2, design: .serif, weight: .medium))
                Text("Every word must be valid.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lexiconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { lexiconOptions }
                VStack(spacing: 12) { lexiconOptions }
            }
            if let lexicon = model.selectedLexicon {
                Text(lexicon.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lexiconOptions: some View {
        ForEach(model.catalog?.lexicons ?? []) { lexicon in
            let isSelected = model.selectedLexiconID == lexicon.id
            Button {
                model.selectedLexiconID = lexicon.id
            } label: {
                HStack(spacing: 10) {
                    Text(lexicon.name)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .accessibilityHidden(true)
                }
                .padding(14)
                .foregroundStyle(isSelected ? AppStyle.accent : .secondary)
                .background(isSelected ? AppStyle.accent.opacity(0.08) : AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isSelected ? AppStyle.accent : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.5 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isChecking)
            .accessibilityLabel(lexicon.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("lexicon-\(lexicon.id)")
        }
    }

    private func wordEntry(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WORDS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    model.clearInput()
                    isWordsFocused = true
                }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(model.input.isEmpty || model.isChecking)
                .accessibilityHint("Clears all entered words.")
                .accessibilityIdentifier("clear-words")
            }
            ZStack(alignment: .topLeading) {
                if let rules = model.catalog?.inputRules {
                    PlayTextEditor(
                        text: $model.input,
                        isFocused: $isWordsFocused,
                        rules: rules,
                        isEditable: !model.isChecking,
                        onRejectedEdit: model.reportInputError
                    )
                    .padding(10)
                }
                if model.input.isEmpty {
                    Text("Enter one word per line")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: height)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(model.inputError == nil ? Color.primary.opacity(0.12) : .red, lineWidth: 1)
            }
            .disabled(model.isChecking)
            Text("One word per line. Up to \(model.catalog?.inputRules.maximumLines ?? 8) lines.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var submissionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.inputError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("input-error")
            }
            Button {
                isWordsFocused = false
                Task { await model.checkPlay() }
            } label: {
                HStack {
                    if model.isChecking { ProgressView().tint(.white) }
                    Text(model.isChecking ? "Checking…" : "Check play")
                    if !model.isChecking { Image(systemName: "arrow.right") }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isChecking || model.catalog == nil)
            .accessibilityIdentifier("check-play")
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppStyle.paper)
    }
}

#Preview {
    ContentView()
}
