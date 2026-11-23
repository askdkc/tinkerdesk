import Foundation

public struct LineCommentEdit {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(source: String, selection: NSRange) {
        let text = source as NSString
        range = text.lineRange(for: selection)
        let block = NSMutableString(string: text.substring(with: range))
        var prefixes: [NSRange] = []
        var start = 0
        repeat {
            var end = 0
            var contentEnd = 0
            block.getLineStart(nil, end: &end, contentsEnd: &contentEnd,
                               for: NSRange(location: start, length: 0))
            var offset = start
            while offset < contentEnd, [9, 32].contains(block.character(at: offset)) {
                offset += 1
            }
            let rest = block.substring(with: NSRange(location: offset, length: contentEnd - offset))
            let length = rest.hasPrefix("// ") ? 3 : (rest.hasPrefix("//") ? 2 : 0)
            prefixes.append(NSRange(location: offset, length: length))
            start = end
        } while start < block.length

        let uncomment = prefixes.allSatisfy { $0.length > 0 }
        var caret = selection.location
        for prefix in prefixes.reversed() {
            let edit = NSRange(location: prefix.location, length: uncomment ? prefix.length : 0)
            let marker = uncomment ? "" : "// "
            block.replaceCharacters(in: edit, with: marker)
            let position = range.location + edit.location
            if caret >= position {
                caret = max(position, caret - edit.length) + marker.utf16.count
            }
        }
        replacement = block as String
        self.selection = selection.length == 0 ? NSRange(location: caret, length: 0)
            : NSRange(location: range.location, length: block.length)
    }
}
