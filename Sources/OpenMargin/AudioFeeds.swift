import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

private let audioLog = Logger(subsystem: "com.nsgarv.openmargin", category: "audio")

struct CaptureFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// A process tap is not an input device. Core Audio only exposes it through a private aggregate device.
final class SystemAudioTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var tap: AudioHardwareTap?
    private var aggregate: AudioHardwareAggregateDevice?
    private var installed = false

    func start(onChunk: @escaping @Sendable (PCMChunk) -> Void) throws {
        let system = AudioHardwareSystem.shared
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.currentProcessIDs())
        description.name = "OpenMargin"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        if let bundleID = Bundle.main.bundleIdentifier {
            description.bundleIDs = [bundleID]
        }

        let tap: AudioHardwareTap
        do {
            guard let created = try system.makeProcessTap(description: description) else {
                throw CaptureFailure(message: Self.permissionHint("System audio did not start."))
            }
            tap = created
        } catch let failure as CaptureFailure {
            throw failure
        } catch {
            audioLog.error("process tap failed: \(error.localizedDescription, privacy: .public)")
            throw CaptureFailure(message: Self.permissionHint(error.localizedDescription))
        }
        self.tap = tap

        let tapUID: String
        do {
            tapUID = try tap.uid
        } catch {
            stop()
            throw CaptureFailure(message: "System audio tap has no identifier. \(error.localizedDescription)")
        }

        let aggregate: AudioHardwareAggregateDevice
        do {
            guard let created = try system.makeAggregateDevice(description: Self.aggregateDescription(tapUID: tapUID)) else {
                throw CaptureFailure(message: "Could not open a private device for system audio.")
            }
            aggregate = created
        } catch {
            stop()
            audioLog.error("aggregate device failed: \(error.localizedDescription, privacy: .public)")
            throw CaptureFailure(message: "Could not open system audio. \(error.localizedDescription)")
        }
        self.aggregate = aggregate

        do {
            try install(deviceID: aggregate.id, onChunk: onChunk)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            installed = false
        }
        let system = AudioHardwareSystem.shared
        if let aggregate {
            try? system.destroyAggregateDevice(aggregate)
            self.aggregate = nil
        }
        if let tap {
            try? system.destroyProcessTap(tap)
            self.tap = nil
        }
    }

    private func install(deviceID: AudioDeviceID, onChunk: @escaping @Sendable (PCMChunk) -> Void) throws {
        let input = engine.inputNode
        try input.withAudioUnit { audioUnit in
            guard let audioUnit else {
                throw CaptureFailure(message: "The audio engine has no input.")
            }
            var selectedDevice = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &selectedDevice,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw CaptureFailure(message: "Could not select the system-audio device (\(status)).")
            }
        }

        let hardware = input.outputFormat(forBus: 0)
        let rate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        let channels = hardware.channelCount > 0 ? hardware.channelCount : 2
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: channels,
            interleaved: false
        ) else {
            throw CaptureFailure(message: "Could not describe the system-audio format.")
        }

        try input.installAudioTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let chunk = PCMChunk(AVAudioPCMBuffer(copying: buffer)) else { return }
            onChunk(chunk)
        }
        installed = true
        engine.prepare()
        try engine.start()
    }

    private static func currentProcessIDs() -> [AudioObjectID] {
        guard let process = try? AudioHardwareSystem.shared.process(for: getpid()) else { return [] }
        return [process.id]
    }

    private static func aggregateDescription(tapUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "OpenMargin Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: NSNumber(value: 1),
            kAudioAggregateDeviceIsStackedKey: NSNumber(value: 0),
            kAudioAggregateDeviceTapAutoStartKey: NSNumber(value: 0),
            kAudioAggregateDeviceMainSubDeviceKey: tapUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: tapUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ]
        ]
    }

    private static func permissionHint(_ detail: String) -> String {
        "System audio was blocked. Allow OpenMargin in System Settings → Privacy & Security → System Audio Recording, then press Start again. \(detail)"
    }
}

final class MicrophoneFeed: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var installed = false

    func start(onChunk: @escaping @Sendable (PCMChunk) -> Void) throws {
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        let rate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        let channels: AVAudioChannelCount = hardware.channelCount > 0 ? hardware.channelCount : 1
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: channels,
            interleaved: false
        ) else {
            throw CaptureFailure(message: "Could not describe the microphone format.")
        }

        try input.installAudioTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let chunk = PCMChunk(AVAudioPCMBuffer(copying: buffer)) else { return }
            onChunk(chunk)
        }
        installed = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw CaptureFailure(message: "The microphone did not start. \(error.localizedDescription)")
        }
    }

    func stop() {
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            installed = false
        }
    }
}
