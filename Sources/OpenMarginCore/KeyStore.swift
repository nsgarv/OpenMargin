import Foundation

public enum KeyStore {
    public static func fileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMargin", isDirectory: true)
            .appendingPathComponent("xai-api-key")
    }

    public static func environmentKey() -> String? {
        trimmed(ProcessInfo.processInfo.environment["XAI_API_KEY"])
    }

    public static func savedKey() -> String? {
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return trimmed(String(data: data, encoding: .utf8))
    }

    public static func current() -> String? {
        environmentKey() ?? savedKey()
    }

    public static func save(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = fileURL()
        if trimmedKey.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(trimmedKey.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
