import Foundation
import XCTest
@testable import TinkerCore

final class LaravelProjectTests: XCTestCase {
    func testRejectsFolderWithoutLaravelRuntimeFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try LaravelProject.inspect(root)) { error in
            XCTAssertEqual(error as? LaravelProjectError, .missingFile("artisan"))
        }
    }

    func testReadsLaravelVersionFromComposerLock() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("vendor", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bootstrap", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("artisan"))
        try Data().write(to: root.appendingPathComponent("vendor/autoload.php"))
        try Data().write(to: root.appendingPathComponent("bootstrap/app.php"))
        let composerLock = """
        {"packages":[{"name":"laravel/framework","version":"v12.4.1"}]}
        """
        try Data(composerLock.utf8).write(to: root.appendingPathComponent("composer.lock"))

        let project = try LaravelProject.inspect(root)

        XCTAssertEqual(project.name, root.lastPathComponent)
        XCTAssertEqual(project.laravelVersion, "12.4.1")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
