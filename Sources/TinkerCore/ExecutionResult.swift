import Foundation

public struct ExecutionResult: Equatable, Sendable {
    public let succeeded: Bool
    public let output: String
    public let value: String
    public let valueType: String
    public let errorTitle: String?
    public let errorMessage: String?
    public let errorLocation: String?
    public let duration: TimeInterval

    public init(
        succeeded: Bool,
        output: String,
        value: String,
        valueType: String,
        errorTitle: String? = nil,
        errorMessage: String? = nil,
        errorLocation: String? = nil,
        duration: TimeInterval
    ) {
        self.succeeded = succeeded
        self.output = output
        self.value = value
        self.valueType = valueType
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage
        self.errorLocation = errorLocation
        self.duration = duration
    }
}

public enum ExecutionResultParser {
    public static let marker = "__TINKERDESK_RESULT__"

    public static func parse(stdout: Data, stderr: Data, exitCode: Int32) throws -> ExecutionResult {
        let output = String(decoding: stdout, as: UTF8.self)
        guard let markerRange = output.range(of: marker, options: .backwards) else {
            throw ExecutionError.invalidRunnerResponse(
                stderr: String(decoding: stderr, as: UTF8.self),
                exitCode: exitCode
            )
        }
        let encodedPayload = String(output[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payloadData = Data(base64Encoded: encodedPayload),
              let payload = try? JSONDecoder().decode(RunnerPayload.self, from: payloadData) else {
            throw ExecutionError.invalidRunnerResponse(
                stderr: String(decoding: stderr, as: UTF8.self),
                exitCode: exitCode
            )
        }
        return ExecutionResult(
            succeeded: payload.ok,
            output: payload.output,
            value: payload.value,
            valueType: payload.valueType,
            errorTitle: payload.errorClass,
            errorMessage: payload.errorMessage,
            errorLocation: payload.errorLocation,
            duration: payload.durationMs / 1_000
        )
    }
}

private struct RunnerPayload: Decodable {
    let ok: Bool
    let output: String
    let value: String
    let valueType: String
    let errorClass: String?
    let errorMessage: String?
    let errorLocation: String?
    let durationMs: Double
}

public enum ExecutionError: LocalizedError, Equatable {
    case invalidRunnerResponse(stderr: String, exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case let .invalidRunnerResponse(stderr, exitCode):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "PHP exited with status \(exitCode) without returning a result."
                : detail
        }
    }
}
