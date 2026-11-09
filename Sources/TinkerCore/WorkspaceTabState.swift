import Foundation

public struct WorkspaceTabState: Equatable, Sendable {
    public private(set) var projectURLs: [URL]
    public private(set) var selectedURL: URL?

    public init(projectURLs: [URL] = [], selectedURL: URL? = nil) {
        var seen: Set<URL> = []
        self.projectURLs = projectURLs
            .map(Self.normalize)
            .filter { seen.insert($0).inserted }
        let selectedURL = selectedURL.map(Self.normalize)
        self.selectedURL = selectedURL.flatMap { self.projectURLs.contains($0) ? $0 : nil }
            ?? self.projectURLs.first
    }

    @discardableResult
    public mutating func open(_ projectURL: URL) -> Bool {
        let projectURL = Self.normalize(projectURL)
        selectedURL = projectURL
        guard !projectURLs.contains(projectURL) else { return false }
        projectURLs.append(projectURL)
        return true
    }

    public mutating func select(_ projectURL: URL) {
        let projectURL = Self.normalize(projectURL)
        guard projectURLs.contains(projectURL) else { return }
        selectedURL = projectURL
    }

    @discardableResult
    public mutating func close(_ projectURL: URL) -> URL? {
        let projectURL = Self.normalize(projectURL)
        guard let index = projectURLs.firstIndex(of: projectURL) else { return selectedURL }
        projectURLs.remove(at: index)
        guard selectedURL == projectURL else { return selectedURL }
        guard !projectURLs.isEmpty else {
            selectedURL = nil
            return nil
        }
        selectedURL = projectURLs[min(index, projectURLs.count - 1)]
        return selectedURL
    }

    private static func normalize(_ url: URL) -> URL {
        url.standardizedFileURL
    }
}
