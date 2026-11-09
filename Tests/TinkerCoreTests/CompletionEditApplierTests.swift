import Foundation
import XCTest
@testable import TinkerCore

final class CompletionEditApplierTests: XCTestCase {
    func testAppliesClassCompletionAndAutomaticImportFromVirtualPHPDocument() {
        let source = "Us::query()->count();"
        let completion = EditorCompletion(
            label: "User",
            detail: "App\\Models\\User",
            textEdit: LSPTextEdit(
                range: LSPRange(
                    start: LSPPosition(line: 1, character: 0),
                    end: LSPPosition(line: 1, character: 2)
                ),
                newText: "User"
            ),
            additionalTextEdits: [
                LSPTextEdit(
                    range: LSPRange(
                        start: LSPPosition(line: 1, character: 0),
                        end: LSPPosition(line: 1, character: 0)
                    ),
                    newText: "use App\\Models\\User;\n\n"
                )
            ]
        )

        let result = CompletionEditApplier.apply(
            completion,
            to: source,
            fallbackRange: NSRange(location: 0, length: 2)
        )

        XCTAssertEqual(
            result.text,
            "use App\\Models\\User;\n\nUser::query()->count();"
        )
        XCTAssertEqual(result.caretUTF16Offset, 26)
    }

    func testFallsBackToTheEditorsPartialWordRange() {
        let completion = EditorCompletion(label: "User", insertText: "User")

        let result = CompletionEditApplier.apply(
            completion,
            to: "return Us;",
            fallbackRange: NSRange(location: 7, length: 2)
        )

        XCTAssertEqual(result.text, "return User;")
        XCTAssertEqual(result.caretUTF16Offset, 11)
    }
}
