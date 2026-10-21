import AppKit
import OpenMarginCore
import SwiftUI

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.listening ? "Listening" : "OpenMargin")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(model.listening ? "Stop" : "Start") {
                    model.listenToCurrent()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.listening ? Color.red : Ink.copper)
                .disabled(model.phase == .stopping)
            }

            if let live = model.apps.live {
                Label("\(live.name) is open", systemImage: "video")
                    .font(.callout)
                    .foregroundStyle(Ink.ink)
            }

            if !model.agenda.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.inkSoft)
                    ForEach(model.agenda.events.prefix(5)) { event in
                        Button {
                            model.openAgendaItem(event)
                            openWindow(id: "main")
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.timeLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Ink.copper)
                                    .frame(width: 58, alignment: .leading)
                                Text(event.title)
                                    .font(.callout)
                                    .foregroundStyle(Ink.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if case .denied(let message) = model.agenda.access {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Ink.inkSoft)
            }

            Divider()

            Button("Open OpenMargin") {
                model.showMainWindow()
                openWindow(id: "main")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
        .background(Ink.paper)
    }

    private var headline: String {
        if model.listening {
            return "Tell the other people. Audio is not saved."
        }
        if let now = model.agenda.events.first(where: \.isNow) {
            return now.title
        }
        if let live = model.apps.live {
            return "Ready for \(live.name)"
        }
        return "Notes stay on this Mac."
    }
}
