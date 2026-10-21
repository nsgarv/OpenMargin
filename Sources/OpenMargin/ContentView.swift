import AppKit
import OpenMarginCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: UUID?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            if let id = model.selectedID {
                MeetingPane(meetingID: id)
                    .id(id)
            } else {
                empty
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("OpenMargin")
        .background(Ink.paper)
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { model.delete(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Text("OpenMargin")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.sidebarText)
                Spacer()
                Button {
                    model.newMeeting()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Ink.sidebarText)
                .help("New meeting")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            calendarSection
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            List(selection: $model.selectedID) {
                ForEach(model.meetings) { meeting in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.sidebarText)
                            .lineLimit(1)
                        Text(MeetingDate.sidebar(meeting.createdAt))
                            .font(.caption)
                            .foregroundStyle(Ink.sidebarText.opacity(0.55))
                    }
                    .padding(.vertical, 4)
                    .tag(meeting.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingDelete = meeting.id }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Text("Notes stay on this Mac.")
                .font(.caption2)
                .foregroundStyle(Ink.sidebarText.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Ink.sidebar)
    }

    @ViewBuilder
    private var calendarSection: some View {
        if !model.agenda.events.isEmpty || model.apps.live != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.sidebarText.opacity(0.45))
                    .padding(.horizontal, 4)
                if let live = model.apps.live {
                    Label("\(live.name) is open", systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(Ink.sidebarText.opacity(0.8))
                        .padding(.horizontal, 4)
                }
                ForEach(Array(model.agenda.events.prefix(4))) { event in
                    Button {
                        model.openAgendaItem(event)
                    } label: {
                        HStack(spacing: 8) {
                            Text(event.timeLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Ink.copper)
                                .frame(width: 46, alignment: .leading)
                            Text(event.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Ink.sidebarText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if case .denied = model.agenda.access {
            Text("Calendar access is off.")
                .font(.caption2)
                .foregroundStyle(Ink.sidebarText.opacity(0.45))
                .padding(.horizontal, 4)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("No meeting")
                .font(.system(size: 22, weight: .semibold, design: .serif))
            Button("New meeting") { model.newMeeting() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
    }
}

private struct MeetingPane: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID
    @State private var mode: NoteMode = .rough

    private var meeting: Meeting? {
        model.meetings.first { $0.id == meetingID }
    }

    var body: some View {
        if let meeting {
            VStack(spacing: 0) {
                toolbar(meeting)
                if let status = model.status, !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(Ink.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(Ink.paperDeep)
                }
                HSplitView {
                    noteColumn(meeting)
                        .frame(minWidth: 380)
                    transcriptColumn(meeting)
                        .frame(minWidth: 260, idealWidth: 340)
                }
            }
            .background(Ink.paper)
            .onChange(of: model.enhancedTick) { _, _ in
                if meeting.enhancedNote != nil { mode = .enhanced }
            }
        }
    }

    private func toolbar(_ meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            TextField("Title", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Ink.ink)

            Spacer(minLength: 12)

            if let link = meeting.joinURL.flatMap(URL.init(string:)) {
                Button("Join") {
                    NSWorkspace.shared.open(link)
                }
                .help(link.absoluteString)
            }

            Picker("Capture", selection: captureBinding) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .disabled(model.phase != .idle)
            .labelsHidden()

            Button {
                model.toggleListening()
            } label: {
                Label(listenTitle, systemImage: model.phase == .listening ? "stop.fill" : "waveform")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.phase == .listening ? Color.red : Ink.copper)
            .disabled(model.phase == .stopping)

            Button {
                model.enhance()
            } label: {
                if model.enhancing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Enhance")
                }
            }
            .disabled(model.enhancing)
            .help("Sends the note and transcript to xAI. Audio stays here.")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Ink.paper)
    }

    private var listenTitle: String {
        switch model.phase {
        case .preparing: "Starting…"
        case .listening: "Stop"
        case .stopping: "Stopping…"
        case .idle: "Start listening"
        }
    }

    private func noteColumn(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if meeting.enhancedNote != nil {
                    Picker("Note", selection: $mode) {
                        Text("Rough").tag(NoteMode.rough)
                        Text("Enhanced").tag(NoteMode.enhanced)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .labelsHidden()
                }
                Spacer()
                if mode == .enhanced, meeting.enhancedNote != nil {
                    Button("Copy") { copyEnhanced(meeting) }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if mode == .enhanced, let enhanced = meeting.enhancedNote {
                ScrollView {
                    Text(rendered(enhanced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: notesBinding)
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(Ink.ink)
                        .scrollContentBackground(.hidden)
                        .padding(.leading, 36)
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                    if meeting.rawNotes.isEmpty {
                        Text("Jot what matters. Decisions, names, questions. The wording can be rough.")
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(Ink.inkSoft.opacity(0.75))
                            .padding(.leading, 42)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                    Rectangle()
                        .fill(Ink.rule)
                        .frame(width: 1)
                        .padding(.leading, 28)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Ink.paper)
    }

    private func transcriptColumn(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                    Text(meeting.captureMode == .call ? "You is the mic. Speakers is the call." : "One microphone hears the room.")
                        .font(.caption)
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if model.phase == .listening || model.phase == .preparing {
                HStack(spacing: 16) {
                    LevelMeter(title: meeting.captureMode == .call ? "You" : "Room", level: model.youLevel)
                    if meeting.captureMode == .call {
                        LevelMeter(title: "Speakers", level: model.speakersLevel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if meeting.transcript.isEmpty {
                        Text("Nothing transcribed yet. Audio is not kept after it becomes text.")
                            .font(.callout)
                            .foregroundStyle(Ink.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(meeting.transcript) { line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.speaker.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Ink.copper)
                                    Text(line.text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(line.isFinal ? Ink.ink : Ink.inkSoft)
                                        .textSelection(.enabled)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(16)
                    }
                }
                .onChange(of: meeting.transcript.last?.text) { _, _ in
                    if let last = meeting.transcript.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Ink.paperDeep.opacity(0.45))
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { meeting?.title ?? "" },
            set: { model.setTitle($0) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { meeting?.rawNotes ?? "" },
            set: { model.setNotes($0) }
        )
    }

    private var captureBinding: Binding<CaptureMode> {
        Binding(
            get: { meeting?.captureMode ?? .call },
            set: { model.setCaptureMode($0) }
        )
    }

    private func rendered(_ source: String) -> AttributedString {
        var result = AttributedString()
        for block in EnhancedNote.parse(source) {
            switch block {
            case .heading(let text):
                var heading = AttributedString(text + "\n")
                heading.font = .system(size: 18, weight: .semibold, design: .serif)
                heading.foregroundColor = Ink.ink
                result += heading
            case .paragraph(let text, let added):
                var paragraph = AttributedString(text + "\n\n")
                paragraph.font = .system(size: 16, design: .serif)
                if added {
                    paragraph.foregroundColor = Ink.added
                    paragraph.inlinePresentationIntent = .emphasized
                } else {
                    paragraph.foregroundColor = Ink.ink
                }
                result += paragraph
            }
        }
        return result
    }

    private func copyEnhanced(_ meeting: Meeting) {
        guard let note = meeting.enhancedNote else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(EnhancedNote.plain(note), forType: .string)
    }
}

private enum NoteMode: Hashable {
    case rough
    case enhanced
}

private struct LevelMeter: View {
    var title: String
    var level: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Ink.inkSoft)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.paperDeep)
                    Capsule()
                        .fill(Ink.copper)
                        .frame(width: max(3, geo.size.width * CGFloat(min(max(level, 0), 1))))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }
}
