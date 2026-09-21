@preconcurrency import AVFoundation
import Foundation

struct PipelineUpdate: Sendable {
    let stage: JobStage
    let progress: Double
}

struct PCMTrack: Sendable {
    let sampleRate: Double
    let samples: [Float]
}

enum AudioInspector {
    static func inspect(_ url: URL) throws -> SongInfo {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw HarmonyError.invalidAudio }
        return SongInfo(url: url, duration: duration, sampleRate: file.processingFormat.sampleRate)
    }
}

enum AudioDecoder {
    static func decodeMono44k(_ url: URL) throws -> PCMTrack {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw HarmonyError.invalidAudio
        }
        var samples: [Float] = []
        let inputCapacity: AVAudioFrameCount = 8_192
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputCapacity)!
            try file.read(into: input)
            guard input.frameLength > 0 else { break }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 64)
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)!
            try converter.convert(to: output, from: input)
            guard let channel = output.floatChannelData?[0] else { throw HarmonyError.invalidAudio }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
        guard !samples.isEmpty else { throw HarmonyError.invalidAudio }
        return PCMTrack(sampleRate: 44_100, samples: samples)
    }
}

enum OfflinePitchRenderer {
    static func shift(samples: [Float], semitones: Int, sampleRate: Double) throws -> [Float] {
        guard semitones != 0 else { return samples }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            input.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = Float(semitones * 100)
        timePitch.rate = 1
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        try engine.start()
        player.scheduleBuffer(input, at: nil, options: .interrupts)
        player.play()

        var rendered: [Float] = []
        rendered.reserveCapacity(samples.count)
        var emptyPasses = 0
        while rendered.count < samples.count && emptyPasses < 32 {
            try Task.checkCancellation()
            let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096)!
            let frames = min(AVAudioFrameCount(samples.count - rendered.count), 4_096)
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                if buffer.frameLength == 0 { emptyPasses += 1; continue }
                emptyPasses = 0
                if let channel = buffer.floatChannelData?[0] {
                    rendered.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                }
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                emptyPasses += 1
            case .error:
                throw HarmonyError.exportFailed
            @unknown default:
                throw HarmonyError.exportFailed
            }
        }
        player.stop()
        engine.stop()
        if rendered.count < samples.count { rendered.append(contentsOf: repeatElement(0, count: samples.count - rendered.count)) }
        return Array(rendered.prefix(samples.count))
    }
}

enum WAVWriter {
    static func write(samples: [Float], to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_384
        for start in stride(from: 0, to: samples.count, by: chunk) {
            let count = min(chunk, samples.count - start)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData?[0].update(from: source.baseAddress!.advanced(by: start), count: count)
            }
            try file.write(from: buffer)
        }
    }
}

struct HarmonyPipeline: Sendable {
    typealias ProgressHandler = @Sendable (PipelineUpdate) -> Void

    func generate(
        from sourceURL: URL,
        outputDirectory: URL? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> GenerationResult {
        try await Task.detached(priority: .userInitiated) {
            try generateSynchronously(from: sourceURL, outputDirectory: outputDirectory, progress: progress)
        }.value
    }

    func generateSynchronously(
        from sourceURL: URL,
        outputDirectory: URL? = nil,
        progress: @escaping ProgressHandler
    ) throws -> GenerationResult {
            progress(PipelineUpdate(stage: .loading, progress: 0.05))
            let decoded = try AudioDecoder.decodeMono44k(sourceURL)
            try Task.checkCancellation()

            progress(PipelineUpdate(stage: .separating, progress: 0.22))
            var vocal = decoded.samples
            var warnings: [String] = []
            switch ModelAssetLocator.status() {
            case let .ready(separator, _):
                vocal = try CoreMLVocalIsolator(modelURL: separator).isolate(decoded.samples)
            case .unavailable:
                warnings.append("Preview isolation is active because the bundled Core ML model assets are not installed; exported tracks include elements of the original mix.")
            }
            try Task.checkCancellation()

            progress(PipelineUpdate(stage: .analyzing, progress: 0.48))
            let frames = PitchTracker.frames(samples: vocal, sampleRate: decoded.sampleRate)
            let key = KeyDetector.detect(from: frames.compactMap(\.midi))

            progress(PipelineUpdate(stage: .arranging, progress: 0.62))
            let shifts = Dictionary(uniqueKeysWithValues: HarmonyRole.allCases.map { role in
                (role, representativeShift(frames: frames, role: role, key: key))
            })

            progress(PipelineUpdate(stage: .rendering, progress: 0.70))
            let destinationDirectory = try outputDirectory ?? exportDirectory(for: sourceURL)
            var exports: [HarmonyExport] = []
            for (offset, role) in HarmonyRole.allCases.enumerated() {
                try Task.checkCancellation()
                progress(PipelineUpdate(stage: .rendering, progress: 0.70 + Double(offset) * 0.09))
                let rendered = try OfflinePitchRenderer.shift(samples: vocal, semitones: shifts[role] ?? 0, sampleRate: decoded.sampleRate)
                let name = sourceURL.deletingPathExtension().lastPathComponent + " " + role.filenameSuffix
                let output = destinationDirectory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: output)
                try WAVWriter.write(samples: rendered, to: output, sampleRate: decoded.sampleRate)
                exports.append(HarmonyExport(role: role, url: output))
            }
            return GenerationResult(exports: exports, key: key, warnings: warnings)
    }

    private func representativeShift(frames: [PitchFrame], role: HarmonyRole, key: MusicalKey) -> Int {
        let shifts = frames.compactMap { frame in
            frame.midi.map { HarmonyPlanner.semitoneShift(sourceMidi: $0, role: role, key: key) }
        }
        guard !shifts.isEmpty else {
            return switch role { case .low: -3; case .mid: 4; case .high: 7 }
        }
        let frequency = Dictionary(grouping: shifts, by: { $0 }).mapValues(\.count)
        return frequency.max { $0.value < $1.value }!.key
    }

    private func exportDirectory(for sourceURL: URL) throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? sourceURL.deletingLastPathComponent()
        let directory = base.appendingPathComponent("Song Harmonize Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
