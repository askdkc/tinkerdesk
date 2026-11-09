import Foundation
import XCTest
@testable import TinkerCore

final class PHPantomIntegrationTests: XCTestCase {
    func testCompletesLaravelModelWithAutomaticNamespaceImport() async throws {
        guard let serverPath = ProcessInfo.processInfo.environment["TINKERDESK_PHPANTOM"],
              let projectPath = ProcessInfo.processInfo.environment["TINKERDESK_SAMPLE_PROJECT"] else {
            throw XCTSkip("Set TINKERDESK_PHPANTOM and TINKERDESK_SAMPLE_PROJECT to run this test.")
        }
        let client = PHPantomClient(serverURL: URL(fileURLWithPath: serverPath))
        defer { client.stop() }
        try await client.start(projectRoot: URL(fileURLWithPath: projectPath))

        let completions = try await client.completions(source: "Us", caretUTF16Offset: 2)
        let user = completions.first {
            $0.label == "User" && ($0.detail?.contains("App\\Models\\User") ?? false)
        }

        XCTAssertNotNil(user)
        XCTAssertTrue(user?.additionalTextEdits.contains {
            $0.newText.contains("use App\\Models\\User")
        } ?? false)
    }
}
