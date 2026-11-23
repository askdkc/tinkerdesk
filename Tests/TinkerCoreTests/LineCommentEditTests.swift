import XCTest
import TinkerCore

final class LineCommentEditTests: XCTestCase {
    func testCursorOnIndentedLine() {
        let edit = LineCommentEdit(source: "first\n  😀;\n", selection: NSRange(location: 10, length: 0))
        XCTAssertEqual(edit.replacement, "  // 😀;\n")
        XCTAssertEqual(edit.selection, NSRange(location: 13, length: 0))
    }

    func testSelectionEndsAtNextLineStartAndTogglesBack() {
        let source = "  one\r\n\r\n\ttwo\r\nthree"
        let selection = NSRange(location: 2, length: 13)
        let edit = LineCommentEdit(source: source, selection: selection)
        XCTAssertEqual(edit.replacement, "  // one\r\n// \r\n\t// two\r\n")
        let commented = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        let undo = LineCommentEdit(source: commented, selection: edit.selection)
        XCTAssertEqual((commented as NSString).replacingCharacters(in: undo.range, with: undo.replacement), source)
    }
}
