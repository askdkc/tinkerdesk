import SwiftUI

@main
struct TinkerDeskApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_240, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Laravel Project…") { model.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Run") {
                Button("Run Snippet") { model.run() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.canRun)
                Button("Force Stop") { model.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!model.isRunning)
            }
        }
    }
}
