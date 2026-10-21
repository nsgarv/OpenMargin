import Foundation

public struct MeetingStore: Sendable {
    public var fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("meetings.json")
    }

    public static func live() -> MeetingStore {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMargin", isDirectory: true)
        return MeetingStore(directory: directory)
    }

    public func load() -> [Meeting] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StoreEnvelope.self, from: data).meetings
        } catch {
            let bad = fileURL.deletingLastPathComponent().appendingPathComponent("meetings.json.bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: fileURL, to: bad)
            return []
        }
    }

    public func save(_ meetings: [Meeting]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(StoreEnvelope(version: 1, meetings: meetings))
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct StoreEnvelope: Codable {
    var version: Int
    var meetings: [Meeting]
}
