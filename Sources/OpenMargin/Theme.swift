import SwiftUI

enum Ink {
    static let paper = Color(red: 0.953, green: 0.933, blue: 0.890)
    static let paperDeep = Color(red: 0.910, green: 0.878, blue: 0.816)
    static let ink = Color(red: 0.118, green: 0.102, blue: 0.086)
    static let inkSoft = Color(red: 0.38, green: 0.33, blue: 0.28)
    static let copper = Color(red: 0.769, green: 0.384, blue: 0.176)
    static let rule = Color(red: 0.769, green: 0.384, blue: 0.176).opacity(0.45)
    static let sidebar = Color(red: 0.145, green: 0.125, blue: 0.105)
    static let sidebarText = Color(red: 0.94, green: 0.91, blue: 0.85)
    static let added = Color(red: 0.62, green: 0.33, blue: 0.14)
}

enum MeetingDate {
    static func sidebar(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
