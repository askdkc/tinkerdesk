import AppKit
import Combine
import Foundation
import TinkerCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tabs: [ProjectSessionModel] = []
    @Published private(set) var selectedTabID: UUID?
    @Published private(set) var php: PHPInstallation?
    @Published var alertMessage: String?

    private let defaults: UserDefaults
    private var tabState = WorkspaceTabState()
    private var shortcutMonitor: Any?
    private var selectedTabObservation: AnyCancellable?

    var selectedTab: ProjectSessionModel? {
        tabs.first(where: { $0.id == selectedTabID })
    }

    var canRun: Bool {
        selectedTab?.canRun(with: php) == true
    }

    var isRunning: Bool {
        selectedTab?.isRunning == true
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.php = PHPInstallation.discover(
            preferredPath: defaults.string(forKey: Keys.phpPath)
        )

        let commandLineProject = CommandLine.arguments.dropFirst().first
        let restoredPaths = defaults.stringArray(forKey: Keys.openProjectPaths) ?? []
        let legacyPath = defaults.string(forKey: Keys.legacyProjectPath)
        var paths = commandLineProject.map { [$0] } ?? restoredPaths
        if paths.isEmpty, let legacyPath { paths = [legacyPath] }

        let legacyCode = defaults.string(forKey: Keys.legacyCode)
        for (index, path) in paths.enumerated() {
            guard let project = try? LaravelProject.inspect(URL(fileURLWithPath: path)) else {
                continue
            }
            addProject(project, legacyCode: index == 0 ? legacyCode : nil, persist: false)
        }

        if commandLineProject == nil,
           let selectedPath = defaults.string(forKey: Keys.selectedProjectPath) {
            selectProject(at: URL(fileURLWithPath: selectedPath), persist: false)
        }
        observeSelectedTab()
        persistTabs()
        installShortcutMonitor()
    }

    deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open a Laravel project in a new tab"
        panel.message = "Choose a folder containing artisan and an installed vendor directory."
        panel.prompt = "Open in New Tab"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        do {
            addProject(try LaravelProject.inspect(url), legacyCode: nil, persist: true)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func selectTab(_ tab: ProjectSessionModel) {
        tabState.select(tab.project.rootURL)
        selectedTabID = tab.id
        observeSelectedTab()
        persistTabs()
    }

    func closeTab(_ tab: ProjectSessionModel) {
        tab.shutdown()
        let selectedURL = tabState.close(tab.project.rootURL)
        tabs.removeAll(where: { $0.id == tab.id })
        selectedTabID = selectedURL.flatMap { url in
            tabs.first(where: { $0.project.rootURL == url })?.id
        }
        observeSelectedTab()
        persistTabs()
    }

    func choosePHP() {
        let panel = NSOpenPanel()
        panel.title = "Choose a PHP executable"
        panel.message = "Select the PHP binary used by your Laravel projects."
        panel.prompt = "Use PHP"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let installation = PHPInstallation.discover(preferredPath: url.path),
              installation.executableURL == url.standardizedFileURL else {
            alertMessage = "The selected file is not a working PHP executable."
            return
        }
        php = installation
        defaults.set(installation.executableURL.path, forKey: Keys.phpPath)
    }

    func run() {
        selectedTab?.run(with: php)
    }

    func stop() {
        selectedTab?.stop()
    }

    private func addProject(
        _ project: LaravelProject,
        legacyCode: String?,
        persist: Bool
    ) {
        let created = tabState.open(project.rootURL)
        if created {
            tabs.append(ProjectSessionModel(
                project: project,
                defaults: defaults,
                legacyCode: legacyCode,
                phpantomExecutable: Self.phpantomExecutableURL()
            ))
        }
        selectedTabID = tabs.first(where: {
            $0.project.rootURL == tabState.selectedURL
        })?.id
        observeSelectedTab()
        if persist { persistTabs() }
    }

    private func selectProject(at url: URL, persist: Bool) {
        tabState.select(url)
        selectedTabID = tabs.first(where: {
            $0.project.rootURL == tabState.selectedURL
        })?.id
        observeSelectedTab()
        if persist { persistTabs() }
    }

    private func observeSelectedTab() {
        selectedTabObservation = selectedTab?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func persistTabs() {
        defaults.set(tabState.projectURLs.map(\.path), forKey: Keys.openProjectPaths)
        defaults.set(tabState.selectedURL?.path, forKey: Keys.selectedProjectPath)
        defaults.set(tabState.selectedURL?.path, forKey: Keys.legacyProjectPath)
    }

    private func installShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "r" {
                self.run()
                return nil
            }
            if event.keyCode == 53, self.isRunning {
                self.stop()
                return nil
            }
            return event
        }
    }

    private static func phpantomExecutableURL() -> URL? {
        var candidates: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["TINKERDESK_PHPANTOM"] {
            candidates.append(URL(fileURLWithPath: configured))
        }
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/phpantom_lsp")
        )
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/PHPantom/phpantom_lsp")
        )
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }?.standardizedFileURL
    }

    private enum Keys {
        static let legacyCode = "editor.code"
        static let legacyProjectPath = "project.path"
        static let openProjectPaths = "projects.openPaths"
        static let selectedProjectPath = "projects.selectedPath"
        static let phpPath = "php.path"
    }
}
