import Foundation
import XCTest
@testable import TinkerCore

final class TinkerRunnerIntegrationTests: XCTestCase {
    func testResolvesUnqualifiedModelInProject() async throws {
        guard let path = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_SAMPLE_PROJECT to a Laravel project with App\\Models\\User.")
        }
        let project = try LaravelProject.inspect(URL(fileURLWithPath: path))
        let php = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] ?? "/opt/homebrew/bin/php"
        let result = try await TinkerRunner().run(
            project: project, phpExecutable: URL(fileURLWithPath: php),
            code: "return get_class(new User());"
        )
        XCTAssertEqual(result.value, "App\\Models\\User", result.errorMessage ?? "")
    }

    func testExecutesCodeInsideLaravelApplication() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_SAMPLE_PROJECT to run the Laravel integration test.")
        }
        let phpPath = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] ?? "/opt/homebrew/bin/php"
        let project = try LaravelProject.inspect(URL(fileURLWithPath: projectPath))

        let result = try await TinkerRunner().run(
            project: project,
            phpExecutable: URL(fileURLWithPath: phpPath),
            code: "echo config('app.name'); return app()->version();"
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "Laravel")
        XCTAssertEqual(result.valueType, "string")
        XCTAssertEqual(result.value, project.laravelVersion)
    }

    func testReturnsSyntaxErrorAsAResult() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_SAMPLE_PROJECT to run the Laravel integration test.")
        }
        let phpPath = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] ?? "/opt/homebrew/bin/php"
        let project = try LaravelProject.inspect(URL(fileURLWithPath: projectPath))

        let result = try await TinkerRunner().run(
            project: project,
            phpExecutable: URL(fileURLWithPath: phpPath),
            code: "echo 'before'; this is invalid"
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.errorTitle, "ParseError")
        XCTAssertFalse(result.errorMessage?.isEmpty ?? true)
    }

    func testPreservesOutputBeforeRuntimeException() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_SAMPLE_PROJECT to run the Laravel integration test.")
        }
        let phpPath = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] ?? "/opt/homebrew/bin/php"
        let project = try LaravelProject.inspect(URL(fileURLWithPath: projectPath))

        let result = try await TinkerRunner().run(
            project: project,
            phpExecutable: URL(fileURLWithPath: phpPath),
            code: "echo 'before'; throw new RuntimeException('Broken');"
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.output, "before")
        XCTAssertEqual(result.errorTitle, "RuntimeException")
        XCTAssertEqual(result.errorMessage, "Broken")
    }
}
