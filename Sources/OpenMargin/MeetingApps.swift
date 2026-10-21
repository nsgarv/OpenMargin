import AppKit
import Foundation
import OpenMarginCore

struct LiveCall: Equatable {
    var name: String
    var joinURL: URL?
}

@MainActor
@Observable
final class MeetingApps {
    var live: LiveCall?
    private var observers: [NSObjectProtocol] = []
    private var automationBlocked = false

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.refresh()
                }
            }
            observers.append(token)
        }
        Task { await refresh() }
    }

    func refresh() async {
        let native = Self.runningNative()
        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           let script = Self.browserScripts[bundleID],
           !automationBlocked,
           let url = tabURL(script: script),
           let name = MeetingLink.name(for: url) {
            live = LiveCall(name: name, joinURL: url)
            return
        }
        live = native
    }

    private static let nativeApps = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams2", "Teams"),
        ("com.microsoft.teams", "Teams"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.cisco.webexmeetings", "Webex"),
        ("com.webex.meetingmanager", "Webex"),
        ("com.apple.FaceTime", "FaceTime")
    ]

    private static let browserScripts = [
        "com.apple.Safari": #"tell application id "com.apple.Safari" to get URL of current tab of front window"#,
        "com.google.Chrome": #"tell application id "com.google.Chrome" to get URL of active tab of front window"#,
        "com.brave.Browser": #"tell application id "com.brave.Browser" to get URL of active tab of front window"#,
        "com.microsoft.edgemac": #"tell application id "com.microsoft.edgemac" to get URL of active tab of front window"#,
        "company.thebrowser.Browser": #"tell application id "company.thebrowser.Browser" to get URL of active tab of front window"#
    ]

    private static func runningNative() -> LiveCall? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for (bundleID, name) in nativeApps where running.contains(bundleID) {
            return LiveCall(name: name, joinURL: nil)
        }
        return nil
    }

    private func tabURL(script source: String) -> URL? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if number == -1743 {
                automationBlocked = true
            }
            return nil
        }
        guard let text = result.stringValue, let url = URL(string: text) else { return nil }
        return url
    }
}
