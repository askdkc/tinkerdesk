import AppKit
import SwiftUI
import TinkerCore

struct PHPCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let completionProvider: (String, Int) async -> [EditorCompletion]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = LaravelCodePalette.background

        let textView = CompletionTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = LaravelCodePalette.font
        textView.textColor = LaravelCodePalette.foreground
        textView.insertionPointColor = LaravelCodePalette.caret
        textView.backgroundColor = scrollView.backgroundColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 14, height: 13)
        textView.setAccessibilityLabel("PHP snippet editor")
        textView.setAccessibilityHelp(
            "Write PHP to execute inside Laravel. PHPantom provides completions and automatic imports."
        )
        textView.onCompletionSelected = { [weak coordinator = context.coordinator] completion, range in
            coordinator?.apply(completion, fallbackRange: range)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CompletionTextView,
              textView.string != text else {
            return
        }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(selection.location, (text as NSString).length),
            length: 0
        ))
        context.coordinator.applyHighlighting(to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PHPCodeEditor
        fileprivate weak var textView: CompletionTextView?
        private var completionTask: Task<Void, Never>?
        private var suppressNextRequest = false
        private var isApplyingHighlighting = false

        init(parent: PHPCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            applyHighlighting(to: textView)
            parent.text = textView.string
            if suppressNextRequest {
                suppressNextRequest = false
                return
            }
            requestCompletions(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !textView.completionItems.isEmpty else { return }
            textView.completionItems = []
        }

        func apply(_ completion: EditorCompletion, fallbackRange: NSRange) {
            guard let textView else { return }
            let result = CompletionEditApplier.apply(
                completion,
                to: textView.string,
                fallbackRange: fallbackRange
            )
            suppressNextRequest = true
            textView.string = result.text
            textView.setSelectedRange(NSRange(
                location: min(result.caretUTF16Offset, (result.text as NSString).length),
                length: 0
            ))
            textView.didChangeText()
            parent.text = result.text
        }

        fileprivate func applyHighlighting(to textView: NSTextView) {
            guard !isApplyingHighlighting, let storage = textView.textStorage else { return }
            isApplyingHighlighting = true
            defer { isApplyingHighlighting = false }

            let selection = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: storage.length)
            let baseAttributes = LaravelCodePalette.baseAttributes
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)
            for token in PHPSyntaxHighlighter.tokens(in: textView.string)
                where NSMaxRange(token.range) <= storage.length {
                storage.addAttribute(
                    .foregroundColor,
                    value: LaravelCodePalette.color(for: token.kind),
                    range: token.range
                )
            }
            storage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.setSelectedRange(NSRange(
                location: min(selection.location, storage.length),
                length: min(selection.length, max(0, storage.length - min(selection.location, storage.length)))
            ))
        }

        private func requestCompletions(for textView: CompletionTextView) {
            completionTask?.cancel()
            let source = textView.string
            let caret = textView.selectedRange().location
            guard Self.shouldRequestCompletion(source: source, caret: caret) else {
                textView.completionItems = []
                return
            }

            completionTask = Task { [weak self, weak textView] in
                try? await Task.sleep(nanoseconds: 170_000_000)
                guard !Task.isCancelled, let self, let textView else { return }
                let items = await parent.completionProvider(source, caret)
                guard !Task.isCancelled,
                      textView.string == source,
                      textView.selectedRange().location == caret else {
                    return
                }
                textView.completionItems = items
                if !items.isEmpty, textView.window?.firstResponder === textView {
                    textView.complete(nil)
                }
            }
        }

        private static func shouldRequestCompletion(source: String, caret: Int) -> Bool {
            guard caret > 0, caret <= (source as NSString).length else { return false }
            let character = (source as NSString).character(at: caret - 1)
            guard let scalar = UnicodeScalar(character) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_"
                || scalar == ">"
                || scalar == ":"
                || scalar == "\\"
                || scalar == "$"
        }
    }
}

private enum LaravelCodePalette {
    static let background = color(34, 34, 33)
    static let foreground = color(191, 199, 213)
    static let caret = color(211, 66, 62)
    static let font = NSFont(name: "IBM Plex Mono", size: 15)
        ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 32
        return [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
    }

    static func color(for kind: PHPSyntaxTokenKind) -> NSColor {
        switch kind {
        case .comment:
            return color(105, 112, 152)
        case .keyword:
            return color(199, 146, 234)
        case .string:
            return color(195, 232, 141)
        case .number, .literal:
            return color(247, 140, 108)
        case .variable:
            return color(190, 197, 212)
        case .type:
            return color(169, 199, 125)
        case .declaration:
            return color(255, 203, 107)
        case .function:
            return color(130, 170, 255)
        case .operator:
            return color(137, 221, 255)
        }
    }

    private static func color(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

fileprivate final class CompletionTextView: NSTextView {
    var completionItems: [EditorCompletion] = []
    var onCompletionSelected: ((EditorCompletion, NSRange) -> Void)?

    override func completions(
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String]? {
        guard !completionItems.isEmpty else {
            if let index {
                return super.completions(
                    forPartialWordRange: charRange,
                    indexOfSelectedItem: index
                )
            }
            var selectedIndex = 0
            return withUnsafeMutablePointer(to: &selectedIndex) { pointer in
                super.completions(
                    forPartialWordRange: charRange,
                    indexOfSelectedItem: pointer
                )
            }
        }
        index?.pointee = 0
        return completionItems.map(\.label)
    }

    override func insertCompletion(
        _ word: String,
        forPartialWordRange charRange: NSRange,
        movement: Int,
        isFinal flag: Bool
    ) {
        guard flag, let completion = completionItems.first(where: { $0.label == word }) else {
            if !flag { return }
            super.insertCompletion(
                word,
                forPartialWordRange: charRange,
                movement: movement,
                isFinal: flag
            )
            return
        }
        completionItems = []
        onCompletionSelected?(completion, charRange)
    }
}
