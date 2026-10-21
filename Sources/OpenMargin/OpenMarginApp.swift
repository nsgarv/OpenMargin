import SwiftUI

@main
struct OpenMarginApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OpenMargin") {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 600)
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
            }
        }

        Settings {
            SettingsView()
        }
    }
}
