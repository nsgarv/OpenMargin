import AVFoundation
import Foundation
import OpenMarginCore
import Speech

actor CaptureSession {
    private var microphone: MicrophoneFeed?
    private var systemAudio: SystemAudioTap?
    private var channels: [SpeechChannel] = []
    private var stopRequested = false

    func start(
        mode: CaptureMode,
        onStatus: @escaping @Sendable (String) -> Void,
        onTranscript: @escaping @Sendable (Speaker, String, Bool) -> Void,
        onLevel: @escaping @Sendable (Speaker, Float) -> Void
    ) async throws -> [String] {
        stopRequested = false
        await teardown()

        do {
            let warnings = try await arm(
                mode: mode,
                onStatus: onStatus,
                onTranscript: onTranscript,
                onLevel: onLevel
            )
            if stopRequested {
                await teardown()
                throw CancellationError()
            }
            return warnings
        } catch {
            await teardown()
            throw error
        }
    }

    func stop() async {
        stopRequested = true
        await teardown()
    }

    private func arm(
        mode: CaptureMode,
        onStatus: @escaping @Sendable (String) -> Void,
        onTranscript: @escaping @Sendable (Speaker, String, Bool) -> Void,
        onLevel: @escaping @Sendable (Speaker, Float) -> Void
    ) async throws -> [String] {
        let allowed = await Self.requestMicrophone()
        guard allowed else {
            throw CaptureFailure(message: "The microphone is off. Allow OpenMargin in System Settings → Privacy & Security → Microphone.")
        }
        try await Self.requestSpeech()
        if stopRequested { return [] }

        onStatus("Preparing the on-device speech model. The first time can take a few minutes.")
        let locale = try await SpeechSetup.locale()
        try await SpeechSetup.ensureModel(for: locale)
        if stopRequested { return [] }

        let pairs: [(Speaker, Bool)] = switch mode {
        case .call: [(.me, false), (.speakers, true)]
        case .inRoom: [(.room, false)]
        }
        // Bool is "use system audio".

        var warnings: [String] = []
        for (speaker, system) in pairs {
            if stopRequested { return [] }
            let channel = SpeechChannel()
            let inbox: ChunkInbox
            do {
                inbox = try await channel.start(speaker: speaker, onTranscript: onTranscript, onLevel: onLevel)
            } catch {
                warnings.append(error.localizedDescription)
                continue
            }
            channels.append(channel)

            if system {
                let feed = SystemAudioTap()
                do {
                    try feed.start { inbox.yield($0) }
                    systemAudio = feed
                } catch {
                    warnings.append(error.localizedDescription)
                    await channel.stop()
                    if let index = channels.firstIndex(where: { $0 === channel }) {
                        channels.remove(at: index)
                    }
                }
            } else {
                let feed = MicrophoneFeed()
                do {
                    try feed.start { inbox.yield($0) }
                    microphone = feed
                } catch {
                    warnings.append(error.localizedDescription)
                    await channel.stop()
                    if let index = channels.firstIndex(where: { $0 === channel }) {
                        channels.remove(at: index)
                    }
                }
            }
        }

        guard microphone != nil || systemAudio != nil else {
            throw CaptureFailure(message: warnings.joined(separator: " "))
        }
        return warnings
    }

    private func teardown() async {
        microphone?.stop()
        microphone = nil
        systemAudio?.stop()
        systemAudio = nil
        let running = channels
        channels.removeAll()
        for channel in running {
            await channel.stop()
        }
    }

    private static func requestMicrophone() async -> Bool {
        let current = AVAudioApplication.shared.recordPermission
        if current == .granted { return true }
        if current == .denied { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeech() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw CaptureFailure(message: "Speech recognition is off. Allow OpenMargin in System Settings → Privacy & Security → Speech Recognition.")
        }
    }
}
