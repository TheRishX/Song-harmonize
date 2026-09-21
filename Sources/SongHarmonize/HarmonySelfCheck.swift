@preconcurrency import AVFoundation
import Foundation

enum HarmonySelfCheck {
    static func run() -> Int32 {
        do {
            try validateMusicLogic()
            try validateWAVRoundTrip()
            try validatePipeline()
            print("Song Harmonize self-check passed")
            return 0
        } catch {
            fputs("Song Harmonize self-check failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func validateMusicLogic() throws {
        let key = KeyDetector.detect(from: [60, 64, 67, 72, 76, 79])
        guard key == MusicalKey(tonic: 0, isMinor: false) else { throw CheckError.keyDetection }
        let silence = PitchTracker.frames(samples: Array(repeating: 0, count: 8_192), sampleRate: 44_100)
        guard !silence.isEmpty, silence.allSatisfy({ $0.midi == nil }) else { throw CheckError.silence }

        let ranges: [(HarmonyRole, ClosedRange<Int>)] = [(.low, 45...62), (.mid, 55...72), (.high, 60...81)]
        for source in stride(from: 48, through: 84, by: 3) {
            for (role, range) in ranges {
                guard range.contains(HarmonyPlanner.targetPitch(sourceMidi: source, role: role, key: key)) else {
                    throw CheckError.voiceRange
                }
            }
        }
    }

    private static func validateWAVRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-harmonize-self-check-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("tone.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples = (0..<44_100).map { index in Float(sin(2 * Double.pi * 440 * Double(index) / 44_100) * 0.15) }
        try WAVWriter.write(samples: samples, to: file, sampleRate: 44_100)
        let info = try AudioInspector.inspect(file)
        guard abs(info.duration - 1) < 0.03, Int(info.sampleRate) == 44_100 else {
            throw CheckError.wavRoundTrip
        }
    }

    private static func validatePipeline() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-harmonize-pipeline-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("test-tone.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples = (0..<22_050).map { index in Float(sin(2 * Double.pi * 220 * Double(index) / 44_100) * 0.12) }
        try WAVWriter.write(samples: samples, to: source, sampleRate: 44_100)
        let result = try HarmonyPipeline().generateSynchronously(from: source, outputDirectory: directory) { _ in }
        guard result.warnings.isEmpty else { throw CheckError.modelFallback }
        guard result.exports.count == 3 else { throw CheckError.pipelineExportCount }
        for export in result.exports {
            let info = try AudioInspector.inspect(export.url)
            guard abs(info.duration - 0.5) < 0.04, Int(info.sampleRate) == 44_100 else {
                throw CheckError.pipelineOutput
            }
        }
    }

    private enum CheckError: LocalizedError {
        case keyDetection, silence, voiceRange, wavRoundTrip, modelFallback, pipelineExportCount, pipelineOutput
        var errorDescription: String? {
            switch self {
            case .keyDetection: "key detection produced an unexpected result"
            case .silence: "silence handling produced an unexpected result"
            case .voiceRange: "a harmony voice escaped its allowed range"
            case .wavRoundTrip: "24-bit WAV export could not be read back"
            case .modelFallback: "model-backed separation did not activate"
            case .pipelineExportCount: "pipeline did not produce three harmony files"
            case .pipelineOutput: "pipeline output was not aligned to its source"
            }
        }
    }
}
