import SwiftUI

#if canImport(UIKit)
import UIKit

/// Multiline editor with zero `UITextView` insets so the caret lines up with placeholder text.
struct MeshAlignedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding?
    var fontSize: CGFloat = 17
    var fontWeight: Font.Weight = .regular
    var isMonospaced: Bool = false
    var minHeight: CGFloat = 140

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = editorFont
        textView.textColor = UIColor(MeshTheme.Colors.textPrimary)
        textView.tintColor = UIColor(MeshTheme.Colors.accent)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.isScrollEnabled = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.typingAttributes = typingAttributes
        textView.delegate = context.coordinator
        textView.text = text
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = UILabel()
        placeholderLabel.font = editorFont
        placeholderLabel.textColor = UIColor(MeshTheme.Colors.textTertiary)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.text = placeholder
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(textView)
        container.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
        ])

        context.coordinator.textView = textView
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.updatePlaceholderVisibility()

        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard !context.coordinator.isSyncingFromUIKit else { return }

        if context.coordinator.placeholderLabel?.text != placeholder {
            context.coordinator.placeholderLabel?.text = placeholder
        }

        if textView.text != text {
            let selectedRange = textView.selectedRange
            context.coordinator.isSyncingFromSwiftUI = true
            textView.text = text
            context.coordinator.isSyncingFromSwiftUI = false
            let length = (textView.text as NSString).length
            let location = min(selectedRange.location, length)
            let tail = max(0, length - location)
            textView.selectedRange = NSRange(
                location: location,
                length: min(selectedRange.length, tail)
            )
        }

        let targetFont = editorFont
        if textView.font != targetFont {
            textView.font = targetFont
            context.coordinator.placeholderLabel?.font = targetFont
        }
        textView.typingAttributes = typingAttributes
        context.coordinator.updatePlaceholderVisibility()

        guard let isFocused, isFocused.wrappedValue, !textView.isFirstResponder else { return }
        textView.becomeFirstResponder()
    }

    private var editorFont: UIFont {
        if isMonospaced {
            return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return MeshFont.uiFont(size: fontSize, weight: fontWeight)
    }

    private var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: editorFont, .foregroundColor: UIColor(MeshTheme.Colors.textPrimary)]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding?
        weak var textView: UITextView?
        weak var placeholderLabel: UILabel?
        var isSyncingFromUIKit = false
        var isSyncingFromSwiftUI = false

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding?) {
            _text = text
            self.isFocused = isFocused
        }

        func updatePlaceholderVisibility() {
            placeholderLabel?.isHidden = !(textView?.text ?? text).isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isSyncingFromSwiftUI else { return }
            let newText = textView.text ?? ""
            updatePlaceholderVisibility()
            guard newText != text else { return }
            isSyncingFromUIKit = true
            text = newText
            isSyncingFromUIKit = false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = false
        }
    }
}
#endif

/// Multiline input with placeholder and caret aligned to the same origin as the text.
struct MeshMultilineField: View {
    @Binding var text: String
    let placeholder: String
    var isMonospaced: Bool = false
    var minHeight: CGFloat = 140

    var body: some View {
        #if canImport(UIKit)
        MeshAlignedTextEditor(
            text: $text,
            placeholder: placeholder,
            fontSize: 17,
            isMonospaced: isMonospaced,
            minHeight: minHeight
        )
        .frame(minHeight: minHeight, alignment: .topLeading)
        #else
        ZStack(alignment: .topLeading) {
            Text(placeholder)
                .font(placeholderFont)
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .opacity(text.isEmpty ? 1 : 0)
                .allowsHitTesting(false)

            TextEditor(text: $text)
                .font(placeholderFont)
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .meshTextInputAccent()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight, alignment: .topLeading)
        }
        #endif
    }

    private var placeholderFont: Font {
        if isMonospaced {
            return .system(.body, design: .monospaced)
        }
        return MeshTheme.Typography.body()
    }
}
