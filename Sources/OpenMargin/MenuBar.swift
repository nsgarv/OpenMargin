import AppKit
import Observation
import SwiftUI

/// Installs the status-item menu once the app is up, and keeps a way to reopen the main window.
struct MenuBarInstaller: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let opener = openWindow
                let controller = MenuBarController.shared(model: model)
                controller.reopen = {
                    opener(id: "main")
                }
            }
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static var controller: MenuBarController?

    static func shared(model: AppModel) -> MenuBarController {
        if let controller {
            return controller
        }
        let created = MenuBarController(model: model)
        controller = created
        return created
    }

    var reopen: (@MainActor () -> Void)?

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "OpenMargin"
        applyIcon()
        watch()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func watch() {
        withObservationTracking {
            _ = model.listening
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyIcon()
                self?.watch()
            }
        }
    }

    private func applyIcon() {
        let image = MenuBarIcon.image(listening: model.listening)
        image.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuild() {
        menu.removeAllItems()
        appendMeetings()
        if menu.items.contains(where: { !$0.isSeparatorItem }) {
            menu.addItem(.separator())
        }
        appendListening()
        menu.addItem(.separator())
        appendCommands()
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let about = NSMenuItem(title: "OpenMargin \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        add("Quit", action: #selector(quit(_:)))
    }

    private func appendMeetings() {
        let calendar = Calendar.current
        var sections: [(String, [AgendaItem])] = []
        func add(_ title: String, _ event: AgendaItem) {
            if let index = sections.firstIndex(where: { $0.0 == title }) {
                sections[index].1.append(event)
            } else {
                sections.append((title, [event]))
            }
        }
        for event in model.agenda.events.prefix(8) {
            if event.isNow {
                add("Now", event)
            } else if calendar.isDateInToday(event.start) {
                add("Today", event)
            } else if calendar.isDateInTomorrow(event.start) {
                add("Tomorrow", event)
            } else {
                add(event.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), event)
            }
        }
        for (title, events) in sections {
            menu.addItem(.sectionHeader(title: title))
            for event in events {
                let item = NSMenuItem(title: event.title, action: #selector(openEvent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = event.id
                let start = event.start.formatted(date: .omitted, time: .shortened)
                let end = event.end.formatted(date: .omitted, time: .shortened)
                item.subtitle = "\(start) - \(end)"
                menu.addItem(item)
            }
        }
        if let live = model.apps.live {
            let item = NSMenuItem(title: "\(live.name) is open", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if case .denied = model.agenda.access, model.agenda.events.isEmpty {
            let item = NSMenuItem(title: "Calendar access is off", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func appendListening() {
        if model.listening {
            add(model.phase == .stopping ? "Stopping…" : "Stop Listening", action: #selector(toggleListening(_:)))
                .isEnabled = model.phase != .stopping
            return
        }
        if let offer = model.startOffer {
            let listen = add("Listen", action: #selector(acceptOffer(_:)))
            listen.subtitle = offer.promptTitle
            add("Not Now", action: #selector(dismissOffer(_:)))
            return
        }
        add("Start Listening", action: #selector(toggleListening(_:)))
            .isEnabled = model.phase != .stopping
    }

    private func appendCommands() {
        add("Open OpenMargin", action: #selector(openApp(_:)))
        add("New Meeting", action: #selector(newMeeting(_:)))
        add("Settings…", action: #selector(openSettings(_:)))
    }

    @discardableResult
    private func add(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func reveal() {
        model.showMainWindow()
        reopen?()
    }

    @objc private func openEvent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let event = model.agenda.events.first(where: { $0.id == id }) else { return }
        model.openAgendaItem(event)
        reopen?()
    }

    @objc private func toggleListening(_ sender: NSMenuItem) {
        let starting = !model.listening
        model.listenToCurrent()
        if starting { reopen?() }
    }

    @objc private func acceptOffer(_ sender: NSMenuItem) {
        model.acceptStartOffer()
        reopen?()
    }

    @objc private func dismissOffer(_ sender: NSMenuItem) {
        model.dismissStartOffer()
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        reveal()
    }

    @objc private func newMeeting(_ sender: NSMenuItem) {
        model.newMeeting()
        reveal()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        reopen?()
        SettingsOpener.open()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
