import Foundation
import XCTest
@testable import TinkerCore

final class PHPantomIntegrationTests: XCTestCase {
    func testCompletesLaravelModelWithAutomaticNamespaceImport() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_SAMPLE_PROJECT to run this test.")
        }
        let client = PHPantomClient(serverURL: try XCTUnwrap(PHPantomClient.bundledServerURL))
        defer { client.stop() }
        try await client.start(projectRoot: URL(fileURLWithPath: projectPath))

        let source = "return get_class(new Us());"
        let word = (source as NSString).range(of: "Us")
        let completions = try await client.completions(source: source, caretUTF16Offset: NSMaxRange(word))
        let user = completions.first {
            $0.label == "User" && ($0.detail?.contains("App\\Models\\User") ?? false)
        }

        let project = try LaravelProject.inspect(URL(fileURLWithPath: projectPath))
        let fallback = ProjectModelCompletions(projectRoot: project.rootURL)
            .suggestions(source: source, caret: NSMaxRange(word)).first { $0.label == "User" }
        let php = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] ?? "/opt/homebrew/bin/php"
        for item in [try XCTUnwrap(user), try XCTUnwrap(fallback)] {
            let applied = CompletionEditApplier.apply(item, to: source, fallbackRange: word)
            let result = try await TinkerRunner().run(project: project, phpExecutable: URL(fileURLWithPath: php), code: applied.text)
            XCTAssertEqual(result.value, "App\\Models\\User", result.errorMessage ?? "")
        }
        XCTAssertTrue(user?.additionalTextEdits.contains {
            $0.newText.contains("use App\\Models\\User")
        } ?? false)
    }
}
