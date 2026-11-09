import Foundation

public struct LaravelProject: Equatable, Sendable {
    public let rootURL: URL
    public let name: String
    public let laravelVersion: String

    public static func inspect(_ rootURL: URL) throws -> LaravelProject {
        let root = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LaravelProjectError.notDirectory
        }

        for relativePath in ["artisan", "vendor/autoload.php", "bootstrap/app.php"] {
            guard FileManager.default.fileExists(
                atPath: root.appendingPathComponent(relativePath).path
            ) else {
                throw LaravelProjectError.missingFile(relativePath)
            }
        }

        let version = try readLaravelVersion(
            from: root.appendingPathComponent("composer.lock")
        )
        return LaravelProject(
            rootURL: root,
            name: root.lastPathComponent,
            laravelVersion: version
        )
    }

    private static func readLaravelVersion(from lockURL: URL) throws -> String {
        guard let data = try? Data(contentsOf: lockURL),
              let document = try? JSONDecoder().decode(ComposerLock.self, from: data) else {
            throw LaravelProjectError.unreadableComposerLock
        }
        return document.packages
            .first(where: { $0.name == "laravel/framework" })?
            .version
            .trimmingPrefix("v") ?? "Unknown"
    }
}

private struct ComposerLock: Decodable {
    let packages: [ComposerPackage]
}

private struct ComposerPackage: Decodable {
    let name: String
    let version: String
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

public enum LaravelProjectError: LocalizedError, Equatable {
    case notDirectory
    case missingFile(String)
    case unreadableComposerLock

    public var errorDescription: String? {
        switch self {
        case .notDirectory:
            return "Choose a Laravel project folder."
        case let .missingFile(path):
            return "This folder is missing \(path)."
        case .unreadableComposerLock:
            return "The project's composer.lock file could not be read."
        }
    }
}
