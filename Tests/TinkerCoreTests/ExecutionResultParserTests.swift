import Foundation
import XCTest
@testable import TinkerCore

final class ExecutionResultParserTests: XCTestCase {
    func testParsesSuccessfulRunnerEnvelopeAfterIncidentalOutput() throws {
        let payload = """
        {"ok":true,"output":"hello\\n","value":"[1, 2]","valueType":"array","durationMs":12.5}
        """
        let encoded = Data(payload.utf8).base64EncodedString()
        let stdout = Data("notice\\n\(ExecutionResultParser.marker)\(encoded)".utf8)

        let result = try ExecutionResultParser.parse(
            stdout: stdout,
            stderr: Data(),
            exitCode: 0
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "hello\n")
        XCTAssertEqual(result.value, "[1, 2]")
        XCTAssertEqual(result.valueType, "array")
        XCTAssertEqual(result.duration, 0.0125, accuracy: 0.0001)
    }

    func testParsesThrowableDetails() throws {
        let payload = """
        {"ok":false,"output":"before\\n","value":"","valueType":"","errorClass":"RuntimeException","errorMessage":"Broken","errorLocation":"snippet:3","durationMs":2}
        """
        let encoded = Data(payload.utf8).base64EncodedString()

        let result = try ExecutionResultParser.parse(
            stdout: Data("\(ExecutionResultParser.marker)\(encoded)".utf8),
            stderr: Data(),
            exitCode: 1
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errorTitle, "RuntimeException")
        XCTAssertEqual(result.errorMessage, "Broken")
        XCTAssertEqual(result.errorLocation, "snippet:3")
        XCTAssertEqual(result.output, "before\n")
    }

    func testRejectsMissingRunnerEnvelopeWithUsefulStderr() {
        XCTAssertThrowsError(
            try ExecutionResultParser.parse(
                stdout: Data("partial".utf8),
                stderr: Data("PHP was terminated".utf8),
                exitCode: 143
            )
        ) { error in
            XCTAssertEqual(
                error as? ExecutionError,
                .invalidRunnerResponse(stderr: "PHP was terminated", exitCode: 143)
            )
        }
    }
}
