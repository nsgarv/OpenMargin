import AppKit
import OpenMarginCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: UUID?
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 228, ideal: 248, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let offer = model.startOffer {
                    startBanner(offer)
                }
                if let id = model.selectedID {
                    MeetingPane(meetingID: id)
                        .id(id)
                } else {
                    HomeView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .title)
        .tint(Ink.copper)
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
            HStack(spacing: 8) {
                Text("OpenMargin")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.sidebarText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
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
            .padding(.bottom, 8)

            Button {
                model.selectedID = nil
            } label: {
                Label("Home", systemImage: "house")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        model.selectedID == nil ? Color.white.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.sidebarText)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            calendarSection
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(Ink.sidebarText.opacity(0.45)))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Ink.sidebarText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            List(selection: $model.selectedID) {
                if filtering && rows.isEmpty {
                    Text("No matches")
                        .font(.caption)
                        .foregroundStyle(Ink.sidebarText.opacity(0.55))
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.sidebarText)
                            .lineLimit(1)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(Ink.sidebarText.opacity(0.55))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(row.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingDelete = row.id }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 2) {
                if let account = model.workspace.account {
                    Text(account.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.sidebarText)
                        .lineLimit(1)
                    Text(account.email)
                        .font(.caption2)
                        .foregroundStyle(Ink.sidebarText.opacity(0.55))
                        .lineLimit(1)
                }
                Text("Notes stay on this Mac.")
                    .font(.caption2)
                    .foregroundStyle(Ink.sidebarText.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Ink.sidebar)
    }

    private var filtering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rows: [SidebarRow] {
        if filtering {
            return MeetingSearch.hits(in: model.meetings, query: query).map { hit in
                let meeting = model.meetings.first { $0.id == hit.meetingID }
                let title = meeting?.title ?? ""
                return SidebarRow(
                    id: hit.meetingID,
                    title: title.isEmpty ? "Untitled" : title,
                    subtitle: hit.snippet
                )
            }
        }
        return model.meetings.map { meeting in
            SidebarRow(
                id: meeting.id,
                title: meeting.title.isEmpty ? "Untitled" : meeting.title,
                subtitle: MeetingDate.sidebar(meeting.createdAt)
            )
        }
    }

    private func startBanner(_ offer: StartCandidate) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.promptTitle)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.ink)
                Text("Listen? Tell the other people if you do.")
                    .font(.caption)
                    .foregroundStyle(Ink.inkSoft)
            }
            Spacer(minLength: 8)
            Button("Not now") { model.dismissStartOffer() }
            Button("Listen") { model.acceptStartOffer() }
                .buttonStyle(.borderedProminent)
                .tint(Ink.copper)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Ink.paperDeep)
    }

    @ViewBuilder
    private var calendarSection: some View {
        let happening = model.agenda.events.filter(\.isNow)
        if !happening.isEmpty || model.apps.live != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.sidebarText.opacity(0.45))
                    .padding(.horizontal, 4)
                if let live = model.apps.live {
                    Button {
                        model.openLiveCall()
                    } label: {
                        Label("\(live.name) is open", systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(Ink.sidebarText.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
                ForEach(happening) { event in
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
                if showsTranscript(meeting) {
                    HSplitView {
                        noteColumn(meeting)
                            .frame(minWidth: 380)
                        transcriptColumn(meeting)
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
                    }
                } else {
                    noteColumn(meeting)
                }
            }
            .background(Ink.paper)
            .onChange(of: model.enhancedTick) { _, _ in
                if meeting.enhancedNote != nil { mode = .enhanced }
            }
        }
    }

    private func showsTranscript(_ meeting: Meeting) -> Bool {
        model.phase != .idle || !meeting.transcript.isEmpty
    }

    private func toolbar(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(Ink.ink)

            HStack(spacing: 8) {
                Picker("Template", selection: templateBinding) {
                    ForEach(NoteTemplate.allCases, id: \.self) { template in
                        Text(template.label).tag(template)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("How Enhance shapes the note")

                if let link = meeting.joinURL.flatMap(URL.init(string:)) {
                    Button("Join") { NSWorkspace.shared.open(link) }
                        .help(link.absoluteString)
                }

                Picker("Capture", selection: captureBinding) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(model.phase != .idle)
                .labelsHidden()

                Spacer(minLength: 8)

                Button("Export") { model.exportSelected() }
                Button("Email") { model.emailSelected() }
                if meeting.enhancedNote != nil {
                    Button("Copy") { copyEnhanced(meeting) }
                }

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

                Button {
                    model.toggleListening()
                } label: {
                    Label(listenTitle, systemImage: model.phase == .listening ? "stop.fill" : "waveform")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.phase == .listening ? Color.red : Ink.copper)
                .disabled(model.phase == .stopping)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
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
            if meeting.enhancedNote != nil {
                Picker("Note", selection: $mode) {
                    Text("Rough").tag(NoteMode.rough)
                    Text("Enhanced").tag(NoteMode.enhanced)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

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

    private var templateBinding: Binding<NoteTemplate> {
        Binding(
            get: { meeting?.template ?? .general },
            set: { model.setTemplate($0) }
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

private struct SidebarRow: Identifiable {
    var id: UUID
    var title: String
    var subtitle: String
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
