import Foundation

public struct PHPInstallation: Equatable, Sendable {
    public let executableURL: URL
    public let version: String

    public init(executableURL: URL, version: String) {
        self.executableURL = executableURL
        self.version = version
    }

    public static func discover(preferredPath: String? = nil) -> PHPInstallation? {
        var candidates: [String] = []
        if let preferredPath, !preferredPath.isEmpty { candidates.append(preferredPath) }
        if let environmentPath = ProcessInfo.processInfo.environment["TINKERDESK_PHP"] {
            candidates.append(environmentPath)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/php",
            "/usr/local/bin/php",
            "/usr/bin/php"
        ])

        for path in candidates.uniqued() where FileManager.default.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if let version = readVersion(at: url) {
                return PHPInstallation(executableURL: url, version: version)
            }
        }
        return nil
    }

    private static func readVersion(at url: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["-r", "echo PHP_VERSION;"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let value = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
