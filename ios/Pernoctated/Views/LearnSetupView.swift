import SwiftUI

struct LearnSetupView: View {
    @State private var model = LearnSetupViewModel()
    @FocusState private var isPatternFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Lexicon", selection: $model.selectedLexiconID) {
                        ForEach(model.catalog?.lexicons ?? []) { lexicon in
                            Text(lexicon.name).tag(lexicon.id)
                        }
                    }
                    .accessibilityIdentifier("learn-lexicon")
                    Picker("Preset", selection: $model.selectedPresetID) {
                        ForEach(model.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .accessibilityIdentifier("learn-preset")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pattern").font(.subheadline)
                        TextField("e.g. ?? or TISANE?", text: Binding(
                            get: { model.displayedPattern },
                            set: { if model.isCustomPattern { model.customPattern = $0 } }
                        ))
                        .font(.system(.title3, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($isPatternFocused)
                        .submitLabel(.done)
                        .onSubmit { isPatternFocused = false }
                        .disabled(!model.isCustomPattern)
                        .foregroundStyle(model.isCustomPattern ? .primary : .secondary)
                        .padding(12)
                        .background(Color.primary.opacity(model.isCustomPattern ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Pattern")
                        .accessibilityHint(model.isCustomPattern ? "Enter letters and wildcard symbols." : "Choose None under Preset to edit the pattern.")
                        .accessibilityIdentifier("learn-pattern")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Word selection")
                } footer: {
                    Text("Letters can be rearranged. ? adds one unknown letter; * adds any number of extra letters. For example, ?? selects 2 letter words, TISANE? selects anagrams of TISANE plus one letter, and J* selects words containing J. Choose None to enter your own pattern.")
                }

                Section {
                    Picker("Quiz mode", selection: $model.mode) {
                        ForEach(LearnQuizMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("learn-mode")
                } header: {
                    Text("Yes/No vs Anagram")
                } footer: {
                    if model.mode == .yesNo {
                        Text("Swipe left for Invalid or right for Valid. Feedback about your previous answer stays visible as you continue.")
                    }
                }

                if let error = model.resourceError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Learn")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.resourceError == nil, let error = model.patternError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("learn-pattern-error")
                    }
                    Button {
                        isPatternFocused = false
                        model.startQuiz()
                    } label: {
                        Label("Start quiz", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("learn-start")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppStyle.paper)
            }
            .onChange(of: model.selectedPresetID) { _, _ in isPatternFocused = false }
            .navigationDestination(item: $model.startedSetup) { setup in
                switch setup.mode {
                case .anagram: AnagramQuizView(setup: setup)
                case .yesNo: YesNoQuizView(setup: setup)
                }
            }
        }
    }
}
