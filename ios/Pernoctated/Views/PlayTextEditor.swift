import SwiftUI
import UIKit

/// UITextView lets us reject a Return/paste before it changes the text or caret.
struct PlayTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let rules: InputRules
    let isEditable: Bool
    let onRejectedEdit: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .monospacedSystemFont(ofSize: 20, weight: .regular)
        )
        view.adjustsFontForContentSizeCategory = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        view.typingAttributes[.paragraphStyle] = paragraph
        view.autocapitalizationType = .allCharacters
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.returnKeyType = .default
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "Words, one per line"
        view.accessibilityHint = "Up to \(rules.maximumLines) lines. Enter a character before adding a new line."
        view.accessibilityIdentifier = "words-input"

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.done))
        ]
        toolbar.sizeToFit()
        view.inputAccessoryView = toolbar
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            let oldSelection = view.selectedRange
            view.text = text
            let length = (text as NSString).length
            let start = min(oldSelection.location, length)
            view.selectedRange = NSRange(location: start, length: min(oldSelection.length, length - start))
            view.scrollRangeToVisible(view.selectedRange)
        }
        // First-responder changes query the hosting view's responder graph. Performing
        // them during updateUIView reenters SwiftUI's graph update and can hang navigation.
        context.coordinator.scheduleResponderUpdate()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlayTextEditor
        weak var textView: UITextView?
        private var responderUpdateScheduled = false

        init(_ parent: PlayTextEditor) { self.parent = parent }

        func scheduleResponderUpdate() {
            guard !responderUpdateScheduled else { return }
            responderUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.responderUpdateScheduled = false
                guard let view = self.textView else { return }
                if view.isEditable != self.parent.isEditable {
                    view.isEditable = self.parent.isEditable
                }
                let shouldFocus = self.parent.isFocused && self.parent.isEditable
                if shouldFocus && !view.isFirstResponder && view.window != nil {
                    view.becomeFirstResponder()
                } else if !shouldFocus && view.isFirstResponder {
                    view.resignFirstResponder()
                }
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.isEditable else { return false }
            do {
                try parent.rules.validateEditorChange(in: textView.text, range: range, replacement: text)
                return true
            } catch {
                parent.onRejectedEdit(error)
                return false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        @objc func done() {
            textView?.resignFirstResponder()
        }
    }
}
