import Foundation

public enum EnhancedNote {
    public enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph(String, added: Bool)
    }

    public static let addedOpen = "[[added]]"
    public static let addedClose = "[[/added]]"

    public static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var added = false
        var buffer = ""
        var index = source.startIndex

        func flush() {
            emit(buffer, added: added, into: &blocks)
            buffer.removeAll(keepingCapacity: true)
        }

        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix(addedOpen) {
                flush()
                added = true
                index = source.index(index, offsetBy: addedOpen.count)
                continue
            }
            if rest.hasPrefix(addedClose) {
                flush()
                added = false
                index = source.index(index, offsetBy: addedClose.count)
                continue
            }
            buffer.append(source[index])
            index = source.index(after: index)
        }
        flush()
        return blocks
    }

    public static func plain(_ source: String) -> String {
        parse(source).map { block in
            switch block {
            case .heading(let text): text
            case .paragraph(let text, _): text
            }
        }
        .joined(separator: "\n\n")
    }

    private static func emit(_ raw: String, added: Bool, into blocks: inout [Block]) {
        if added {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed, added: true))
            }
            return
        }

        var paragraph: [String] = []
        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined, added: false))
            }
            paragraph.removeAll(keepingCapacity: true)
        }

        for lineSub in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = lineSub.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") {
                flushParagraph()
                let heading = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty {
                    blocks.append(.heading(String(heading)))
                }
            } else if line.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(String(line))
            }
        }
        flushParagraph()
    }
}
