import EventKit
import Foundation
import OpenMarginCore

struct AgendaItem: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var joinURL: URL?
    var isNow: Bool

    var timeLabel: String {
        if isNow { return "Now" }
        return start.formatted(date: .omitted, time: .shortened)
    }

    var rangeLabel: String {
        let startText = start.formatted(date: .omitted, time: .shortened)
        let endText = end.formatted(date: .omitted, time: .shortened)
        if isNow { return "Now · \(startText) – \(endText)" }
        return "\(startText) – \(endText)"
    }
}

@MainActor
@Observable
final class CalendarAgenda {
    enum Access: Equatable {
        case unknown
        case granted
        case denied(String)
    }

    var access: Access = .unknown
    var events: [AgendaItem] = []

    private let store = EKEventStore()

    func prepare() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            access = .granted
            refresh()
        case .denied, .restricted:
            access = .denied("Calendar access is off. Turn it on in System Settings → Privacy & Security → Calendars.")
        case .writeOnly:
            access = .denied("Calendar access is write-only. Allow full access in System Settings → Privacy & Security → Calendars.")
        case .notDetermined:
            let granted = await requestAccess()
            access = granted
                ? .granted
                : .denied("Calendar access was not allowed.")
            if granted { refresh() }
        @unknown default:
            access = .denied("Calendar access is unavailable.")
        }
    }

    func refresh() {
        guard access == .granted else { return }
        let now = Date()
        let windowStart = now.addingTimeInterval(-30 * 60)
        let windowEnd = now.addingTimeInterval(14 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        var seen = Set<String>()
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .compactMap { event in
                guard let id = event.eventIdentifier, seen.insert(id).inserted else { return nil }
                let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else { return nil }
                let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
                return AgendaItem(
                    id: id,
                    title: title,
                    start: event.startDate,
                    end: event.endDate,
                    joinURL: MeetingLink.conferenceURL(eventURL: event.url, text: text),
                    isNow: event.startDate.addingTimeInterval(-60) <= now && event.endDate >= now
                )
            }
            .sorted { $0.start < $1.start }
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
    }

    private func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
