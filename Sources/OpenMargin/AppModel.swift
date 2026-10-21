import AppKit
import Foundation
import Observation
import OpenMarginCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case stopping
    }

    private let store: MeetingStore
    private let session = CaptureSession()
    private var captureTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    let agenda = CalendarAgenda()
    let apps = MeetingApps()
    let workspace = Workspace()

    var meetings: [Meeting]
    var selectedID: UUID?
    var phase: Phase = .idle
    var status: String?
    var youLevel: Float = 0
    var speakersLevel: Float = 0
    var enhancing = false
    var enhancedTick = 0
    var startOffer: StartCandidate?
    private var handledOffers: Set<String> = []
    /// Native app already running at launch. A resident Zoom process is not a meeting starting.
    private var capturedLiveBaseline = false
    private var liveBaselineID: String?

    var selected: Meeting? {
        guard let selectedID else { return nil }
        return meetings.first { $0.id == selectedID }
    }

    var listening: Bool { phase == .listening || phase == .preparing }

    init(store: MeetingStore = .live()) {
        self.store = store
        meetings = store.load().sorted { $0.createdAt > $1.createdAt }
        selectedID = nil
    }

    func beginWatching() {
        guard watchTask == nil else { return }
        let bridge = NotificationBridge.shared
        bridge.install()
        bridge.onListen = { [weak self] id in
            self?.acceptOffer(id: id)
        }
        bridge.onDismiss = { [weak self] id in
            self?.dismissOffer(id: id)
        }
        apps.onUpdate = { [weak self] in
            self?.noteLiveSample()
            self?.considerStartPrompt()
        }
        apps.start()
        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.agenda.prepare()
            self.considerStartPrompt()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self.agenda.refresh()
                await self.apps.refresh()
                self.considerStartPrompt()
            }
        }
    }

    func acceptStartOffer() {
        guard let id = startOffer?.id else { return }
        acceptOffer(id: id)
    }

    func dismissStartOffer() {
        guard let id = startOffer?.id else { return }
        dismissOffer(id: id)
    }

    func listenToCurrent() {
        if phase == .listening || phase == .preparing {
            stopListening()
            return
        }
        if let now = agenda.events.first(where: \.isNow), selected?.calendarEventID != now.id {
            selectAgendaItem(now)
        } else if selected == nil {
            if let live = apps.live {
                selectLiveCall(live)
            } else {
                newMeeting()
            }
        }
        showMainWindow()
        startListening()
    }

    func openAgendaItem(_ item: AgendaItem) {
        selectAgendaItem(item)
        showMainWindow()
    }

    func openLiveCall() {
        guard let live = apps.live else { return }
        selectLiveCall(live)
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    func newMeeting() {
        let meeting = Meeting.new()
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id
        save()
    }

    func delete(_ id: UUID) {
        if selectedID == id, phase == .listening || phase == .preparing {
            stopListening()
        }
        meetings.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = meetings.first?.id
        }
        if meetings.isEmpty {
            newMeeting()
            return
        }
        save()
    }

    func setTitle(_ title: String) {
        mutate { $0.title = title }
    }

    func setNotes(_ notes: String) {
        mutate { $0.rawNotes = notes }
    }

    func setCaptureMode(_ mode: CaptureMode) {
        guard phase == .idle else { return }
        mutate { $0.captureMode = mode }
    }

    func setTemplate(_ template: NoteTemplate) {
        mutate { $0.template = template }
    }

    func setEnhanced(_ text: String) {
        mutate { $0.enhancedNote = text }
    }

    func toggleListening() {
        if phase == .listening || phase == .preparing {
            stopListening()
        } else if phase == .idle {
            startListening()
        }
    }

    func startListening() {
        guard phase == .idle, let meeting = selected else { return }
        markCurrentContextHandled()
        phase = .preparing
        status = "Preparing…"
        youLevel = 0
        speakersLevel = 0
        let mode = meeting.captureMode
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let warnings = try await self.session.start(
                    mode: mode,
                    onStatus: { [weak self] message in
                        Task { @MainActor in self?.status = message }
                    },
                    onTranscript: { [weak self] speaker, text, isFinal in
                        Task { @MainActor in
                            self?.ingest(speaker: speaker, text: text, isFinal: isFinal)
                        }
                    },
                    onLevel: { [weak self] speaker, level in
                        Task { @MainActor in
                            self?.setLevel(speaker, level: level)
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                self.phase = .listening
                let listening = mode == .call
                    ? "Listening. Tell the other people on the call."
                    : "Listening through the microphone. Tell the other people in the room."
                self.status = warnings.isEmpty ? listening : warnings.joined(separator: " ")
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.phase = .idle
                self.status = error.localizedDescription
                self.youLevel = 0
                self.speakersLevel = 0
            }
        }
    }

    func stopListening() {
        guard phase == .listening || phase == .preparing else { return }
        phase = .stopping
        status = "Stopping…"
        captureTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await self.session.stop()
            self.phase = .idle
            self.youLevel = 0
            self.speakersLevel = 0
            self.status = nil
            self.save()
            self.considerStartPrompt()
        }
    }

    func enhance() {
        guard !enhancing, let meeting = selected else { return }
        guard let key = KeyStore.current() else {
            status = EnhanceError.missingKey.errorDescription
            SettingsOpener.open()
            return
        }
        enhancing = true
        status = "Enhancing…"
        let snapshot = meeting
        Task { [weak self] in
            guard let self else { return }
            do {
                let note = try await NoteEnhancer.enhance(meeting: snapshot, key: key)
                self.mutate(id: snapshot.id) { $0.enhancedNote = note }
                self.enhancedTick += 1
                self.status = "Enhanced. Copper text was added by the model."
            } catch {
                self.status = error.localizedDescription
                if error as? EnhanceError == .missingKey {
                    SettingsOpener.open()
                }
            }
            self.enhancing = false
        }
    }

    func exportSelected() {
        guard let meeting = selected else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = NoteExport.filename(for: meeting)
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try NoteExport.document(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Task { @MainActor in
                    self?.status = "Couldn't export. \(error.localizedDescription)"
                }
            }
        }
    }

    func emailSelected() {
        guard let meeting = selected else { return }
        let body = NoteExport.document(for: meeting)
        guard let service = NSSharingService(named: .composeEmail) else {
            status = "Mail isn't available on this Mac."
            return
        }
        service.subject = NoteExport.subject(for: meeting)
        guard service.canPerform(withItems: [body]) else {
            status = "Mail isn't available on this Mac."
            return
        }
        service.perform(withItems: [body])
    }

    private func selectAgendaItem(_ item: AgendaItem) {
        if let existing = meetings.first(where: { $0.calendarEventID == item.id }) {
            selectedID = existing.id
            if existing.joinURL == nil, let url = item.joinURL {
                mutate(id: existing.id) { $0.joinURL = url.absoluteString }
            }
            return
        }
        var meeting = Meeting.new(now: item.start)
        meeting.title = item.title
        meeting.calendarEventID = item.id
        meeting.joinURL = item.joinURL?.absoluteString
        meeting.captureMode = .call
        meeting.template = NoteTemplate.guess(from: item.title)
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id
        save()
    }

    private func selectLiveCall(_ live: LiveCall) {
        let recent = meetings.first { meeting in
            meeting.title == live.name && Date().timeIntervalSince(meeting.createdAt) < 3 * 60 * 60
        }
        if let recent {
            selectedID = recent.id
            if recent.joinURL == nil, let url = live.joinURL {
                mutate(id: recent.id) { $0.joinURL = url.absoluteString }
            }
            return
        }
        var meeting = Meeting.new()
        meeting.title = live.name
        meeting.joinURL = live.joinURL?.absoluteString
        meeting.captureMode = .call
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id
        save()
    }

    private func ingest(speaker: Speaker, text: String, isFinal: Bool) {
        mutate { meeting in
            TranscriptLog.ingest(&meeting.transcript, speaker: speaker, text: text, isFinal: isFinal)
        }
    }

    private func setLevel(_ speaker: Speaker, level: Float) {
        let shown = min(1, max(0, level) * 12)
        switch speaker {
        case .me, .room:
            youLevel = shown
        case .speakers:
            speakersLevel = shown
        }
    }

    private func mutate(id: UUID? = nil, _ body: (inout Meeting) -> Void) {
        let target = id ?? selectedID
        guard let target, let index = meetings.firstIndex(where: { $0.id == target }) else { return }
        body(&meetings[index])
        save()
    }

    private func save() {
        try? store.save(meetings)
    }

    private func noteLiveSample() {
        let nativeID = apps.native.map { StartCandidate.live(name: $0.name).id }
        if !capturedLiveBaseline {
            capturedLiveBaseline = true
            liveBaselineID = nativeID
            return
        }
        if nativeID != liveBaselineID {
            liveBaselineID = nil
        }
    }

    /// A meeting link is a real meeting. A native app with no link is ignored until it launches after we started.
    private func liveForPrompt() -> StartCandidate? {
        guard let live = apps.live else { return nil }
        let candidate = StartCandidate.live(name: live.name)
        if live.joinURL == nil, candidate.id == liveBaselineID {
            return nil
        }
        return candidate
    }

    private func considerStartPrompt() {
        let happening = agenda.events.first(where: \.isNow).map {
            StartCandidate.event(id: $0.id, title: $0.title)
        }
        let next = StartOffers.next(
            listening: listening,
            handled: handledOffers,
            happeningNow: happening,
            liveApp: liveForPrompt()
        )
        guard startOffer?.id != next?.id else { return }
        if let previous = startOffer {
            NotificationBridge.shared.withdraw(previous.id)
        }
        startOffer = next
        if let next {
            NotificationBridge.shared.post(next)
        }
    }

    private func acceptOffer(id: String) {
        handledOffers.insert(id)
        NotificationBridge.shared.withdraw(id)
        let candidate = currentCandidate()
        if startOffer?.id == id {
            startOffer = nil
        }
        guard phase == .idle, candidate?.id == id else { return }
        if candidate?.kind == .liveApp {
            if let live = apps.live {
                selectLiveCall(live)
            }
        } else if let item = agenda.events.first(where: { $0.id == id }) {
            selectAgendaItem(item)
        }
        showMainWindow()
        startListening()
    }

    private func dismissOffer(id: String) {
        handledOffers.insert(id)
        NotificationBridge.shared.withdraw(id)
        if startOffer?.id == id {
            startOffer = nil
        }
    }

    private func currentCandidate() -> StartCandidate? {
        if let now = agenda.events.first(where: \.isNow) {
            return StartCandidate.event(id: now.id, title: now.title)
        }
        if let live = apps.live {
            return StartCandidate.live(name: live.name)
        }
        return nil
    }

    private func markCurrentContextHandled() {
        if let now = agenda.events.first(where: \.isNow) {
            handledOffers.insert(now.id)
        }
        if let live = apps.live {
            handledOffers.insert(StartCandidate.live(name: live.name).id)
        }
        if let offer = startOffer {
            handledOffers.insert(offer.id)
            NotificationBridge.shared.withdraw(offer.id)
            startOffer = nil
        }
    }
}

@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
