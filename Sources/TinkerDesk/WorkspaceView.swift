import SwiftUI
import TinkerCore

struct WorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            projectTabs
            if let selectedTab = appModel.selectedTab {
                ProjectWorkspaceView(model: selectedTab)
                    .id(selectedTab.id)
            } else {
                emptyWorkspace
            }
        }
        .background(Palette.background)
        .alert(
            "TinkerDesk",
            isPresented: Binding(
                get: { appModel.alertMessage != nil },
                set: { if !$0 { appModel.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appModel.alertMessage = nil }
        } message: {
            Text(appModel.alertMessage ?? "")
        }
    }

    private var projectTabs: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(appModel.tabs) { tab in
                        ProjectTab(
                            tab: tab,
                            isSelected: appModel.selectedTabID == tab.id,
                            select: { appModel.selectTab(tab) },
                            close: { appModel.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }

            Button(action: appModel.openProject) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryText)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .help("Open Laravel project in a new tab (⌘O)")
            .accessibilityLabel("Open project in new tab")
            .padding(.trailing, 10)
        }
        .frame(height: 42)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.border) }
    }

    private var emptyWorkspace: some View {
        EmptyResultView(
            icon: "folder.badge.plus",
            title: "Open a Laravel project",
            detail: "Each project opens in its own tab, with separate code, results, and PHPantom context.",
            actionTitle: "Open Project",
            action: appModel.openProject
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.output)
    }
}

private struct ProjectTab: View {
    @ObservedObject var tab: ProjectSessionModel
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: select) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(tab.isRunning ? Palette.accent : Palette.success)
                        .frame(width: 6, height: 6)
                    Text(tab.project.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                }
                .padding(.leading, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.tertiaryText)
            .help("Close \(tab.project.name)")
            .accessibilityLabel("Close \(tab.project.name) tab")
            .padding(.trailing, 3)
        }
        .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
        .background(isSelected ? Palette.card : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Palette.border : Color.clear, lineWidth: 1)
        }
    }
}

private struct ProjectWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var model: ProjectSessionModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            HSplitView {
                editorPanel
                    .frame(minWidth: 420, idealWidth: 680)
                outputPanel
                    .frame(minWidth: 340, idealWidth: 500)
            }
            Divider().overlay(Palette.border)
            statusBar
        }
        .alert(
            "TinkerDesk",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.accentGradient)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(model.project.rootURL.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            Button(action: appModel.openProject) {
                Label("New Project Tab", systemImage: "folder.badge.plus")
            }
            .buttonStyle(QuietButtonStyle())

            if model.isRunning {
                Button(action: model.stop) {
                    Label(model.phase == .stopping ? "Stopping…" : "Stop", systemImage: "stop.fill")
                }
                .buttonStyle(StopButtonStyle())
                .disabled(model.phase == .stopping)
                .help("Force stop (Esc)")
                .accessibilityHint("Force stops the running PHP process. Shortcut: Escape")
            } else {
                Button(action: { model.run(with: appModel.php) }) {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(RunButtonStyle())
                .disabled(!model.canRun(with: appModel.php))
                .keyboardShortcut("r", modifiers: .command)
                .help("Run snippet (⌘R)")
                .accessibilityHint("Runs this PHP snippet inside the selected Laravel application")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Palette.chrome)
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            panelHeader(title: "PHP", detail: "Laravel application context") {
                Text("No <?php tag needed")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryText)
            }
            ZStack(alignment: .topLeading) {
                PHPCodeEditor(
                    text: $model.code,
                    completionProvider: { source, caret in
                        await model.completionSuggestions(
                            source: source,
                            caretUTF16Offset: caret
                        )
                    }
                )
                .background(Palette.editor)

                if model.code.isEmpty {
                    Text("return User::query()->count();")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText)
                        .padding(.leading, 15)
                        .padding(.top, 17)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(Palette.editor)
    }

    private var outputPanel: some View {
        VStack(spacing: 0) {
            panelHeader(title: "Result", detail: resultDetail) {
                if model.result != nil {
                    Button(action: model.copyResult) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondaryText)
                    .help("Copy result")
                    .accessibilityLabel("Copy result")
                }
            }

            Group {
                if model.isRunning {
                    runningState
                } else if let result = model.result {
                    ResultView(result: result)
                } else if model.didCancel {
                    EmptyResultView(
                        icon: "stop.circle",
                        title: "Run stopped",
                        detail: "The PHP process was stopped. Your snippet is still in the editor and ready to run again."
                    )
                } else if appModel.php == nil {
                    EmptyResultView(
                        icon: "terminal",
                        title: "PHP was not found",
                        detail: "Choose the PHP executable used by this project.",
                        actionTitle: "Choose PHP",
                        action: appModel.choosePHP
                    )
                } else {
                    EmptyResultView(
                        icon: "play.circle",
                        title: "Ready to run",
                        detail: "Press ⌘R or use Run. Printed output and the returned value will appear here."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.output)
        }
    }

    private var runningState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(Palette.accent)
            Text(model.phase == .stopping ? "Stopping PHP…" : "Running in Laravel…")
                .font(.system(size: 13, weight: .medium))
            Text("Press Esc to force stop. Your script stays in the editor.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.phase == .stopping ? "Stopping PHP" : "Running snippet in Laravel")
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            StatusItem(icon: "shippingbox", text: "Laravel \(model.project.laravelVersion)")
            Button(action: appModel.choosePHP) {
                StatusItem(icon: "terminal", text: "PHP \(appModel.php?.version ?? "Not found")")
            }
            .buttonStyle(.plain)
            .help("Choose PHP executable")
            StatusItem(icon: "sparkles.rectangle.stack", text: model.languageServiceLabel)
                .help(languageServiceHelp)

            Spacer()

            Text(model.isRunning ? "Running" : "Local project")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.isRunning ? Palette.accent : Palette.secondaryText)
            Circle()
                .fill(model.isRunning ? Palette.accent : Palette.success)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(Palette.chrome)
    }

    private var resultDetail: String {
        guard let result = model.result else { return "Output and returned value" }
        return String(format: "%.0f ms", result.duration * 1_000)
    }

    private var languageServiceHelp: String {
        switch model.languageServiceState {
        case .inactive:
            return "PHPantom has not started for this project."
        case .indexing:
            return "PHPantom is indexing the selected project."
        case .ready:
            return "PHPantom completion and automatic imports are ready."
        case let .unavailable(message):
            return message
        }
    }

    private func panelHeader<Trailing: View>(
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Palette.panelHeader)
    }
}

private struct ResultView: View {
    let result: ExecutionResult

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !result.output.isEmpty {
                    ResultCard(title: "Output", icon: "text.alignleft") {
                        Text(result.output)
                    }
                }
                if result.succeeded {
                    ResultCard(title: "Return · \(result.valueType)", icon: "arrow.turn.down.right") {
                        Text(result.value)
                    }
                } else {
                    ResultCard(
                        title: result.errorTitle ?? "Error",
                        icon: "exclamationmark.triangle.fill",
                        tint: Palette.danger
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(result.errorMessage ?? "The snippet failed without an error message.")
                            if let location = result.errorLocation {
                                Text(location)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13, design: .monospaced))
        .textSelection(.enabled)
        .accessibilityLabel(result.succeeded ? "Snippet completed" : "Snippet failed")
    }
}

private struct ResultCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = Palette.accent
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
            content()
                .foregroundStyle(Palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Palette.border, lineWidth: 1)
        }
    }
}

private struct EmptyResultView: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusItem: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.secondaryText)
    }
}

private struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .foregroundStyle(.white)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(Palette.danger)
            .background(Palette.danger.opacity(configuration.isPressed ? 0.20 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .foregroundStyle(Palette.primaryText)
            .background(Palette.card.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.border, lineWidth: 1)
            }
    }
}

private enum Palette {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.11)
    static let chrome = Color(red: 0.070, green: 0.083, blue: 0.135)
    static let editor = Color(red: 34 / 255, green: 34 / 255, blue: 33 / 255)
    static let output = Color(red: 0.061, green: 0.073, blue: 0.118)
    static let panelHeader = Color(red: 0.078, green: 0.091, blue: 0.145)
    static let card = Color(red: 0.085, green: 0.099, blue: 0.158)
    static let border = Color.white.opacity(0.09)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.34)
    static let accent = Color(red: 0.49, green: 0.39, blue: 0.98)
    static let danger = Color(red: 1.0, green: 0.39, blue: 0.46)
    static let success = Color(red: 0.32, green: 0.82, blue: 0.58)
    static let accentGradient = LinearGradient(
        colors: [accent, Color(red: 0.32, green: 0.58, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
