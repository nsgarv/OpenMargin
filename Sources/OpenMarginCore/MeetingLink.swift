import Foundation

public enum MeetingLink {
    public static func name(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "meet.google.com" || host.hasSuffix(".meet.google.com") {
            return "Google Meet"
        }
        if host.contains("zoom.us") || host.contains("zoom.com") || host.contains("zoomgov.com") {
            return "Zoom"
        }
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") {
            return "Teams"
        }
        if host.contains("webex.com") {
            return "Webex"
        }
        if host.contains("facetime.apple.com") || path.contains("facetime") && host.contains("apple.com") {
            return "FaceTime"
        }
        return nil
    }

    public static func firstMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, name(for: url) != nil else { continue }
            return url
        }
        return nil
    }

    public static func conferenceURL(eventURL: URL?, text: String) -> URL? {
        if let eventURL, name(for: eventURL) != nil {
            return eventURL
        }
        return firstMeetingURL(in: text)
    }
}
