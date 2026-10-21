import AVFoundation
import Foundation
import OpenMarginCore
import Speech

actor SpeechChannel {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var converter: AnalyzerInputConverter?
    private var inbox: ChunkInbox?
    private var analysisTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    private var pumpTask: Task<Void, Never>?

    func start(
        speaker: Speaker,
        onTranscript: @escaping @Sendable (Speaker, String, Bool) -> Void,
        onLevel: @escaping @Sendable (Speaker, Float) -> Void
    ) async throws -> ChunkInbox {
        let locale = try await SpeechSetup.locale()
        try await SpeechSetup.ensureModel(for: locale)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .lingering,
                ignoresResourceLimits: true
            )
        )
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptureFailure(message: "On-device transcription has no audio format for \(locale.identifier).")
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (chunkStream, chunkContinuation) = AsyncStream.makeStream(
            of: PCMChunk.self,
            bufferingPolicy: .bufferingNewest(200)
        )
        let (inputStream, inputContinuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(200)
        )
        let inbox = ChunkInbox(chunkContinuation)
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.converter = AnalyzerInputConverter(analyzerFormat: format)
        self.inbox = inbox

        analysisTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    onTranscript(speaker, text, result.isFinal)
                }
            } catch {
                // The sequence ends when analysis is cancelled.
            }
        }
        pumpTask = Task {
            await self.pump(chunks: chunkStream, speaker: speaker, input: inputContinuation, onLevel: onLevel)
        }
        return inbox
    }

    func stop() async {
        inbox?.finish()
        inbox = nil
        await pumpTask?.value
        pumpTask = nil
        try? await analysisTask?.value
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        converter = nil
        transcriber = nil
        self.analyzer = nil
    }

    private func pump(
        chunks: AsyncStream<PCMChunk>,
        speaker: Speaker,
        input: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @Sendable (Speaker, Float) -> Void
    ) async {
        var lastLevel = Date.distantPast
        for await chunk in chunks {
            let now = Date()
            if now.timeIntervalSince(lastLevel) > 0.08 {
                lastLevel = now
                onLevel(speaker, chunk.rms)
            }
            guard let converter, let buffer = chunk.makeBuffer() else { continue }
            guard let inputs = try? converter.convert(buffer, at: nil) else { continue }
            for item in inputs {
                input.yield(item)
            }
        }
        if let converter, let rest = try? converter.flush() {
            for item in rest {
                input.yield(item)
            }
        }
        input.finish()
    }
}

enum SpeechSetup {
    static func locale() async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw CaptureFailure(message: "On-device transcription is not available on this Mac.")
        }
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return match
        }
        if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) {
            return english
        }
        throw CaptureFailure(message: "No on-device speech language is available.")
    }

    static func ensureModel(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        try await request.downloadAndInstall()
    }
}
