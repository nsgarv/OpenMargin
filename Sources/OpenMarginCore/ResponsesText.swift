import Foundation

public enum ResponsesText {
    public static func outputText(in data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw EnhanceError.emptyResponse
        }
        if let direct = root["output_text"] as? String {
            let trimmed = direct.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let output = root["output"] as? [Any] else {
            throw EnhanceError.emptyResponse
        }

        var parts: [String] = []
        for item in output {
            guard let dict = item as? [String: Any] else { continue }
            let type = dict["type"] as? String
            if type == "output_text", let text = dict["text"] as? String {
                parts.append(text)
                continue
            }
            guard type == "message" || type == nil else { continue }
            if let content = dict["content"] as? String {
                parts.append(content)
            } else if let content = dict["content"] as? [Any] {
                for piece in content {
                    guard let piece = piece as? [String: Any] else { continue }
                    let pieceType = piece["type"] as? String
                    guard pieceType == "output_text" || pieceType == "text" else { continue }
                    if let text = piece["text"] as? String {
                        parts.append(text)
                    }
                }
            }
        }

        let text = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw EnhanceError.emptyResponse }
        return text
    }

    public static func failureMessage(data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let error = object["error"] as? String, !error.isEmpty {
                return error
            }
        }
        let body = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
        if body.isEmpty {
            return "The model request failed (\(status))."
        }
        return "The model request failed (\(status)). \(body)"
    }
}

public enum EnhanceError: LocalizedError, Equatable {
    case missingKey
    case nothingToEnhance
    case emptyResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add an xAI API key in Settings. Enhance sends the note and the transcript. Audio stays on this Mac."
        case .nothingToEnhance:
            "Write a note or capture some of the meeting first."
        case .emptyResponse:
            "The model returned an empty note."
        case .requestFailed(let message):
            message
        }
    }
}
