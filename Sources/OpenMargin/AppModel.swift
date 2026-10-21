import AppKit
import Foundation
import Observation
import OpenMarginCore

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

    var meetings: [Meeting]
    var selectedID: UUID?
    var phase: Phase = .idle
    var status: String?
    var youLevel: Float = 0
    var speakersLevel: Float = 0
    var enhancing = false
    var enhancedTick = 0

    var selected: Meeting? {
        guard let selectedID else { return nil }
        return meetings.first { $0.id == selectedID }
    }

    var listening: Bool { phase == .listening || phase == .preparing }

    init(store: MeetingStore = .live()) {
        self.store = store
        let loaded = store.load().sorted { $0.createdAt > $1.createdAt }
        if loaded.isEmpty {
            let meeting = Meeting.new()
            meetings = [meeting]
            selectedID = meeting.id
            try? store.save(meetings)
        } else {
            meetings = loaded
            selectedID = loaded.first?.id
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
}

@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
