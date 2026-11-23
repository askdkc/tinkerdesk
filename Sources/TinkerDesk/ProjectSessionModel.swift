import AppKit
import Foundation
import TinkerCore

@MainActor
final class ProjectSessionModel: ObservableObject, Identifiable {
    enum RunPhase: Equatable {
        case idle
        case running
        case stopping
    }

    enum LanguageServiceState: Equatable {
        case inactive
        case indexing
        case ready
        case unavailable(String)
    }

    let id = UUID()
    let project: LaravelProject

    @Published var code: String {
        didSet { defaults.set(code, forKey: codeDefaultsKey) }
    }
    @Published private(set) var phase: RunPhase = .idle
    @Published private(set) var result: ExecutionResult?
    @Published private(set) var didCancel = false
    @Published private(set) var languageServiceState: LanguageServiceState = .inactive
    @Published var alertMessage: String?

    private let defaults: UserDefaults
    private let codeDefaultsKey: String
    private lazy var modelNames = ProjectModelCompletions(projectRoot: project.rootURL)
    private let runner = TinkerRunner()
    private let phpantomExecutable: URL?
    private var executionTask: Task<Void, Never>?
    private var languageClient: PHPantomClient?

    var isRunning: Bool { phase != .idle }

    init(
        project: LaravelProject,
        defaults: UserDefaults,
        legacyCode: String?,
        phpantomExecutable: URL?
    ) {
        self.project = project
        self.defaults = defaults
        self.codeDefaultsKey = "editor.code.\(project.rootURL.path)"
        self.phpantomExecutable = phpantomExecutable
        self.code = defaults.string(forKey: codeDefaultsKey)
            ?? legacyCode
            ?? Self.starterCode

        Task { [weak self] in await self?.configureLanguageService() }
    }

    func canRun(with php: PHPInstallation?) -> Bool {
        php != nil
            && phase == .idle
            && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(with php: PHPInstallation?) {
        guard let php else {
            alertMessage = "Choose a PHP executable before running the snippet."
            return
        }
        guard phase == .idle else { return }

        let code = code
        let project = project
        phase = .running
        didCancel = false
        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await runner.run(
                    project: project,
                    phpExecutable: php.executableURL,
                    code: code
                )
                guard !Task.isCancelled else {
                    self.result = nil
                    self.didCancel = true
                    phase = .idle
                    executionTask = nil
                    return
                }
                self.result = result
            } catch {
                if Task.isCancelled {
                    self.result = nil
                    self.didCancel = true
                } else {
                    self.result = ExecutionResult(
                        succeeded: false,
                        output: "",
                        value: "",
                        valueType: "",
                        errorTitle: "Could not run snippet",
                        errorMessage: error.localizedDescription,
                        duration: 0
                    )
                }
            }
            phase = .idle
            executionTask = nil
        }
    }

    func stop() {
        guard phase == .running else { return }
        phase = .stopping
        runner.cancel()
        executionTask?.cancel()
    }

    func shutdown() {
        runner.cancel()
        executionTask?.cancel()
        executionTask = nil
        languageClient?.stop()
        languageClient = nil
    }

    func copyResult() {
        guard let result else { return }
        var sections: [String] = []
        if !result.output.isEmpty { sections.append(result.output) }
        if result.succeeded {
            sections.append(result.value)
        } else {
            sections.append([result.errorTitle, result.errorMessage, result.errorLocation]
                .compactMap { $0 }
                .joined(separator: "\n"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
    }

    func completionSuggestions(source: String, caretUTF16Offset: Int) async -> [EditorCompletion] {
        let local = modelNames.suggestions(source: source, caret: caretUTF16Offset)
        guard languageServiceState == .ready, let languageClient else { return local }
        do {
            let items = try await languageClient.completions(
                source: source,
                caretUTF16Offset: caretUTF16Offset
            )
            return items + local.filter { candidate in !items.contains { $0.label == candidate.label } }
        } catch {
            languageServiceState = .unavailable(error.localizedDescription)
            return local
        }
    }

    var languageServiceLabel: String {
        switch languageServiceState {
        case .inactive:
            return "PHPantom —"
        case .indexing:
            return "PHPantom Indexing"
        case .ready:
            return "PHPantom Ready"
        case .unavailable:
            return "PHPantom Unavailable"
        }
    }

    private func configureLanguageService() async {
        languageClient?.stop()
        languageClient = nil
        guard let phpantomExecutable else {
            languageServiceState = .unavailable("The bundled PHPantom language server is missing.")
            return
        }

        languageServiceState = .indexing
        let client = PHPantomClient(serverURL: phpantomExecutable)
        do {
            try await client.start(projectRoot: project.rootURL)
            languageClient = client
            languageServiceState = .ready
        } catch {
            client.stop()
            languageServiceState = .unavailable(error.localizedDescription)
        }
    }

    private static let starterCode = """
    // Laravel is booted and ready here.
    return [
        'app' => config('app.name'),
        'environment' => app()->environment(),
        'laravel' => app()->version(),
    ];
    """
}
