import AppKit
import SwiftUI

@main
struct OpenMarginApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("OpenMargin", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 600)
                .task {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let image = NSImage(contentsOf: url) {
                        NSApp.applicationIconImage = image
                    }
                    model.beginWatching()
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
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(listening: model.listening))
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
