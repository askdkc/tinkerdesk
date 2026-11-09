import Foundation
import XCTest
@testable import TinkerCore

final class PHPSyntaxHighlighterTests: XCTestCase {
    func testClassifiesLaravelStylePHPWithoutColoringInsideStringsOrComments() {
        let source = """
        use App\\Models\\User;
        // return Fake::class and $ignored
        $users = User::query()->where('active', true)->limit(10)->get();
        return "class DB::select $users";
        """

        let tokens = PHPSyntaxHighlighter.tokens(in: source)
        let rendered = tokens.map { token in
            (substring(source, token.range), token.kind)
        }

        XCTAssertTrue(rendered.contains { $0 == ("use", .keyword) })
        XCTAssertTrue(rendered.contains { $0 == ("App\\Models\\User", .type) })
        XCTAssertTrue(rendered.contains { $0 == ("// return Fake::class and $ignored", .comment) })
        XCTAssertTrue(rendered.contains { $0 == ("$users", .variable) })
        XCTAssertTrue(rendered.contains { $0 == ("User", .type) })
        XCTAssertTrue(rendered.contains { $0 == ("query", .function) })
        XCTAssertTrue(rendered.contains { $0 == ("'active'", .string) })
        XCTAssertTrue(rendered.contains { $0 == ("true", .literal) })
        XCTAssertTrue(rendered.contains { $0 == ("10", .number) })
        XCTAssertTrue(rendered.contains { $0 == ("return", .keyword) })
        XCTAssertTrue(rendered.contains { $0 == ("\"class DB::select $users\"", .string) })
        XCTAssertFalse(rendered.contains { $0.0 == "Fake" || $0.0 == "$ignored" })
    }

    func testRecognizesDeclarationsAndOperators() {
        let source = "final class UserController extends Controller { public function index(): View {} }"
        let rendered = PHPSyntaxHighlighter.tokens(in: source).map {
            (substring(source, $0.range), $0.kind)
        }

        XCTAssertTrue(rendered.contains { $0 == ("final", .keyword) })
        XCTAssertTrue(rendered.contains { $0 == ("class", .keyword) })
        XCTAssertTrue(rendered.contains { $0 == ("UserController", .declaration) })
        XCTAssertTrue(rendered.contains { $0 == ("Controller", .type) })
        XCTAssertTrue(rendered.contains { $0 == ("function", .keyword) })
        XCTAssertTrue(rendered.contains { $0 == ("index", .function) })
        XCTAssertTrue(rendered.contains { $0 == ("View", .type) })
    }

    private func substring(_ source: String, _ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }
}
