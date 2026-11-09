import Foundation

public struct LSPPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct LSPRange: Codable, Equatable, Sendable {
    public let start: LSPPosition
    public let end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

public struct LSPTextEdit: Codable, Equatable, Sendable {
    public let range: LSPRange
    public let newText: String

    public init(range: LSPRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

public struct EditorCompletion: Codable, Equatable, Sendable {
    public let label: String
    public let detail: String?
    public let insertText: String?
    public let textEdit: LSPTextEdit?
    public let additionalTextEdits: [LSPTextEdit]

    public init(
        label: String,
        detail: String? = nil,
        insertText: String? = nil,
        textEdit: LSPTextEdit? = nil,
        additionalTextEdits: [LSPTextEdit] = []
    ) {
        self.label = label
        self.detail = detail
        self.insertText = insertText
        self.textEdit = textEdit
        self.additionalTextEdits = additionalTextEdits
    }
}

public struct CompletionApplication: Equatable, Sendable {
    public let text: String
    public let caretUTF16Offset: Int
}

public enum CompletionEditApplier {
    private static let virtualPrefix = "<?php\n"
    private static let caretMarker = "\u{E000}"

    public static func apply(
        _ completion: EditorCompletion,
        to source: String,
        fallbackRange: NSRange
    ) -> CompletionApplication {
        let virtualSource = virtualPrefix + source
        let mutable = NSMutableString(string: virtualSource)
        let prefixLength = (virtualPrefix as NSString).length
        let sourceLength = (source as NSString).length
        let location = min(max(0, fallbackRange.location), sourceLength)
        let safeFallback = NSRange(
            location: location,
            length: min(max(0, fallbackRange.length), max(0, sourceLength - location))
        )

        var edits: [(range: NSRange, text: String, primary: Bool)] = []
        if let textEdit = completion.textEdit,
           let range = nsRange(for: textEdit.range, in: virtualSource) {
            edits.append((range, normalizedInsertText(textEdit.newText), true))
        } else {
            edits.append((
                NSRange(
                    location: safeFallback.location + prefixLength,
                    length: safeFallback.length
                ),
                normalizedInsertText(completion.insertText ?? completion.label),
                true
            ))
        }
        for edit in completion.additionalTextEdits {
            guard let range = nsRange(for: edit.range, in: virtualSource) else { continue }
            edits.append((range, normalizedInsertText(edit.newText), false))
        }

        edits.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location > $1.range.location
            }
            if $0.range.length != $1.range.length {
                return $0.range.length > $1.range.length
            }
            return $0.primary && !$1.primary
        }

        for edit in edits where NSMaxRange(edit.range) <= mutable.length {
            let replacement = edit.primary ? edit.text + caretMarker : edit.text
            mutable.replaceCharacters(in: edit.range, with: replacement)
        }

        let markerRange = mutable.range(of: caretMarker)
        let virtualCaret = markerRange.location == NSNotFound
            ? safeFallback.location + prefixLength
            : markerRange.location
        if markerRange.location != NSNotFound {
            mutable.deleteCharacters(in: markerRange)
        }

        let rendered = mutable as String
        let text = rendered.hasPrefix(virtualPrefix)
            ? String(rendered.dropFirst(virtualPrefix.count))
            : rendered
        return CompletionApplication(
            text: text,
            caretUTF16Offset: max(0, virtualCaret - prefixLength)
        )
    }

    private static func nsRange(for range: LSPRange, in text: String) -> NSRange? {
        let nsText = text as NSString
        guard let start = utf16Offset(for: range.start, in: nsText),
              let end = utf16Offset(for: range.end, in: nsText),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private static func utf16Offset(for position: LSPPosition, in text: NSString) -> Int? {
        guard position.line >= 0, position.character >= 0 else { return nil }
        var line = 0
        var lineStart = 0
        while line < position.line {
            let searchRange = NSRange(location: lineStart, length: text.length - lineStart)
            let newline = text.range(of: "\n", options: [], range: searchRange)
            guard newline.location != NSNotFound else { return nil }
            lineStart = NSMaxRange(newline)
            line += 1
        }
        let remaining = NSRange(location: lineStart, length: text.length - lineStart)
        let newline = text.range(of: "\n", options: [], range: remaining)
        let lineEnd = newline.location == NSNotFound ? text.length : newline.location
        let offset = lineStart + position.character
        guard offset <= lineEnd else { return nil }
        return offset
    }

    private static func normalizedInsertText(_ text: String) -> String {
        var result = text
        if let expression = try? NSRegularExpression(pattern: #"\$\{\d+:([^}]*)\}"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1"
            )
        }
        if let tabStops = try? NSRegularExpression(pattern: #"\$\d+"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = tabStops.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
    }
}
