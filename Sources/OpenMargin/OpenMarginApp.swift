import AppKit
import SwiftUI

@main
struct OpenMarginApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("OpenMargin", id: "main") {
            ContentView()
                .environment(model)
                .background { MenuBarInstaller(model: model) }
                .frame(minWidth: 920, minHeight: 600)
                .task {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let image = NSImage(contentsOf: url) {
                        NSApp.applicationIconImage = image
                    }
                    model.beginWatching()
                    Self.bringWindowOnScreen()
                }
        }
        .defaultSize(width: 1140, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Meeting") { model.newMeeting() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Meeting") {
                Button(model.listening ? "Stop Listening" : "Start Listening") {
                    model.toggleListening()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.phase == .stopping || model.selectedID == nil)
                Button("Enhance Notes") { model.enhance() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.enhancing || model.selectedID == nil)
                Divider()
                Button("Export Note…") { model.exportSelected() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.selectedID == nil)
                Button("Email Note") { model.emailSelected() }
                    .disabled(model.selectedID == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    /// A restored frame can sit above the displays. Pull it back only when it is actually off screen.
    private static func bringWindowOnScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            let frame = window.frame
            let visible = NSScreen.screens.contains { screen in
                let overlap = screen.visibleFrame.intersection(frame)
                return overlap.width > 120 && overlap.height > 120
            }
            guard !visible, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            var next = frame
            next.size.width = min(next.width, screen.visibleFrame.width - 48)
            next.size.height = min(next.height, screen.visibleFrame.height - 48)
            next.origin.x = screen.visibleFrame.midX - next.width / 2
            next.origin.y = screen.visibleFrame.midY - next.height / 2
            window.setFrame(next, display: true)
        }
    }
}
