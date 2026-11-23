import Foundation

public struct ProjectModelCompletions {
    private let names: [(short: String, qualified: String)]

    public init(projectRoot: URL) {
        // Resolve the same app directory and namespace convention that Laravel uses.
        let manifest = projectRoot.appendingPathComponent("composer.json")
        let app = projectRoot.appendingPathComponent("app", isDirectory: true).standardizedFileURL
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let autoload = json["autoload"] as? [String: Any],
              let mappings = autoload["psr-4"] as? [String: Any],
              let namespace = mappings.first(where: { _, value in
                  let paths = value as? [String] ?? [value as? String ?? ""]
                  return paths.contains {
                      projectRoot.appendingPathComponent($0, isDirectory: true).standardizedFileURL == app
                  }
              })?.key else {
            names = []
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: app.appendingPathComponent("Models"), includingPropertiesForKeys: nil
        )) ?? []
        names = files.filter { $0.pathExtension == "php" }.map {
            let short = $0.deletingPathExtension().lastPathComponent
            return (short, namespace + "Models\\" + short)
        }.sorted { $0.0 < $1.0 }
    }

    public func suggestions(source: String, caret: Int) -> [EditorCompletion] {
        let text = source as NSString
        guard caret > 0, caret <= text.length else { return [] }
        let prefix = text.substring(to: caret)
        guard let match = prefix.range(of: #"(?<![\w$\\>:])[A-Za-z_]\w*\z"#, options: .regularExpression) else {
            return []
        }
        let word = prefix[match]
        return names.filter { $0.short.lowercased().hasPrefix(word.lowercased()) }.map {
            EditorCompletion(label: $0.short, detail: $0.qualified, insertText: "\\" + $0.qualified)
        }
    }
}
