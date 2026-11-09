import Foundation

public enum PHPSyntaxTokenKind: Equatable, Sendable {
    case comment
    case keyword
    case string
    case number
    case variable
    case type
    case declaration
    case function
    case literal
    case `operator`
}

public struct PHPSyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: PHPSyntaxTokenKind

    public init(range: NSRange, kind: PHPSyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

public enum PHPSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "abstract", "and", "array", "as", "break", "callable", "case", "catch",
        "class", "clone", "const", "continue", "declare", "default", "do", "echo",
        "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif",
        "endswitch", "endwhile", "enum", "eval", "exit", "extends", "final", "finally",
        "fn", "for", "foreach", "from", "function", "global", "goto", "if",
        "implements", "include", "include_once", "instanceof", "insteadof", "interface",
        "isset", "list", "match", "namespace", "new", "or", "print", "private",
        "protected", "public", "readonly", "require", "require_once", "return", "static",
        "switch", "throw", "trait", "try", "unset", "use", "var", "while", "xor",
        "yield"
    ]

    private static let literals: Set<String> = ["false", "null", "true"]
    private static let declarationKeywords: Set<String> = ["class", "enum", "interface", "trait"]
    private static let typeContextKeywords: Set<String> = [
        "catch", "extends", "implements", "instanceof", "namespace", "new", "use"
    ]

    public static func tokens(in source: String) -> [PHPSyntaxToken] {
        let text = source as NSString
        var tokens: [PHPSyntaxToken] = []
        var index = 0
        var previousKeyword: String?

        func append(_ start: Int, _ end: Int, _ kind: PHPSyntaxTokenKind) {
            guard end > start else { return }
            tokens.append(PHPSyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
        }

        while index < text.length {
            let character = text.character(at: index)
            if isWhitespace(character) {
                index += 1
                continue
            }

            if character == 47, index + 1 < text.length {
                let next = text.character(at: index + 1)
                if next == 47 {
                    let start = index
                    index += 2
                    while index < text.length, text.character(at: index) != 10 { index += 1 }
                    append(start, index, .comment)
                    continue
                }
                if next == 42 {
                    let start = index
                    index += 2
                    while index + 1 < text.length {
                        if text.character(at: index) == 42, text.character(at: index + 1) == 47 {
                            index += 2
                            break
                        }
                        index += 1
                    }
                    if index == text.length - 1 { index = text.length }
                    append(start, index, .comment)
                    continue
                }
            }

            if character == 35,
               !(index + 1 < text.length && text.character(at: index + 1) == 91) {
                let start = index
                index += 1
                while index < text.length, text.character(at: index) != 10 { index += 1 }
                append(start, index, .comment)
                continue
            }

            if character == 39 || character == 34 || character == 96 {
                let quote = character
                let start = index
                index += 1
                var escaped = false
                while index < text.length {
                    let current = text.character(at: index)
                    index += 1
                    if escaped {
                        escaped = false
                    } else if current == 92 {
                        escaped = true
                    } else if current == quote {
                        break
                    }
                }
                append(start, index, .string)
                previousKeyword = nil
                continue
            }

            if character == 36,
               index + 1 < text.length,
               isIdentifierStart(text.character(at: index + 1)) {
                let start = index
                index += 2
                while index < text.length, isIdentifierPart(text.character(at: index)) { index += 1 }
                append(start, index, .variable)
                previousKeyword = nil
                continue
            }

            if isDigit(character) {
                let start = index
                index += 1
                while index < text.length {
                    let current = text.character(at: index)
                    if isDigit(current) || current == 46 || current == 95 {
                        index += 1
                    } else {
                        break
                    }
                }
                append(start, index, .number)
                previousKeyword = nil
                continue
            }

            if isIdentifierStart(character) || character == 92 {
                let start = index
                index += 1
                while index < text.length {
                    let current = text.character(at: index)
                    if isIdentifierPart(current) || current == 92 {
                        index += 1
                    } else {
                        break
                    }
                }
                let word = text.substring(with: NSRange(location: start, length: index - start))
                let lowercased = word.lowercased()
                let kind: PHPSyntaxTokenKind
                if keywords.contains(lowercased) {
                    kind = .keyword
                    previousKeyword = lowercased
                } else if literals.contains(lowercased) {
                    kind = .literal
                    previousKeyword = nil
                } else if let contextKeyword = previousKeyword, declarationKeywords.contains(contextKeyword) {
                    kind = .declaration
                    previousKeyword = nil
                } else if let contextKeyword = previousKeyword, typeContextKeywords.contains(contextKeyword) {
                    kind = .type
                    self.consumeTypeContextIfNeeded(word: word, previousKeyword: &previousKeyword)
                } else if word.contains("\\") || startsWithUppercase(word) || nextOperator(in: text, after: index) == "::" {
                    kind = .type
                    previousKeyword = nil
                } else if nextNonWhitespace(in: text, after: index) == 40
                            || previousOperator(in: text, before: start) == "->"
                            || previousOperator(in: text, before: start) == "::" {
                    kind = .function
                    previousKeyword = nil
                } else {
                    previousKeyword = nil
                    continue
                }
                append(start, index, kind)
                continue
            }

            if isOperatorCharacter(character) {
                let start = index
                index += 1
                while index < text.length,
                      isOperatorCharacter(text.character(at: index)),
                      index - start < 3 {
                    index += 1
                }
                append(start, index, .operator)
                previousKeyword = nil
                continue
            }

            if character == 59 || character == 123 || character == 125 {
                previousKeyword = nil
            }
            index += 1
        }

        return tokens
    }

    private static func consumeTypeContextIfNeeded(word: String, previousKeyword: inout String?) {
        if previousKeyword != "use" && previousKeyword != "namespace" && previousKeyword != "implements" {
            previousKeyword = nil
        } else if word.contains("\\") {
            previousKeyword = nil
        }
    }

    private static func nextNonWhitespace(in text: NSString, after index: Int) -> unichar? {
        var current = index
        while current < text.length, isWhitespace(text.character(at: current)) { current += 1 }
        return current < text.length ? text.character(at: current) : nil
    }

    private static func nextOperator(in text: NSString, after index: Int) -> String? {
        var current = index
        while current < text.length, isWhitespace(text.character(at: current)) { current += 1 }
        guard current + 1 < text.length else { return nil }
        return text.substring(with: NSRange(location: current, length: 2))
    }

    private static func previousOperator(in text: NSString, before index: Int) -> String? {
        var current = index - 1
        while current >= 0, isWhitespace(text.character(at: current)) { current -= 1 }
        guard current >= 1 else { return nil }
        return text.substring(with: NSRange(location: current - 1, length: 2))
    }

    private static func startsWithUppercase(_ word: String) -> Bool {
        guard let scalar = word.unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(scalar)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    private static func isIdentifierStart(_ character: unichar) -> Bool {
        (character >= 65 && character <= 90)
            || (character >= 97 && character <= 122)
            || character == 95
            || character > 127
    }

    private static func isIdentifierPart(_ character: unichar) -> Bool {
        isIdentifierStart(character) || isDigit(character)
    }

    private static func isOperatorCharacter(_ character: unichar) -> Bool {
        switch character {
        case 33, 37, 38, 42, 43, 45, 46, 47, 58, 60, 61, 62, 63, 64, 94, 124, 126:
            return true
        default:
            return false
        }
    }
}
