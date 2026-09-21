@preconcurrency import AVFoundation
@preconcurrency import CoreML
import CryptoKit
import Foundation

enum ModelAssetStatus: Sendable {
    case ready(separator: URL)
    case unavailable
}

enum ModelPaths {
    static let packageName = "HTDemucs_CoreML_FP16.mlpackage"

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SongHarmonize/Models", isDirectory: true)
    }

    static var downloadedPackage: URL { modelsDirectory.appendingPathComponent(packageName, isDirectory: true) }
    static var validationMarker: URL { modelsDirectory.appendingPathComponent("HTDemucs_CoreML_FP16.validated") }
}

enum ModelAssetLocator {
    static func status(bundle: Bundle = .module) -> ModelAssetStatus {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: ModelPaths.downloadedPackage.path),
           fileManager.fileExists(atPath: ModelPaths.validationMarker.path) {
            return .ready(separator: ModelPaths.downloadedPackage)
        }
        if let bundled = bundle.url(forResource: "HTDemucs_CoreML_FP16", withExtension: "mlpackage", subdirectory: "Models") {
            return .ready(separator: bundled)
        }
        return .unavailable
    }
}

enum ModelDownloadState: Equatable {
    case missing
    case downloading(step: Int, total: Int, name: String)
    case ready
    case failed(String)
}

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var state: ModelDownloadState = .missing
    private var downloadTask: Task<Void, Never>?

    init() { refresh() }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func refresh() {
        state = switch ModelAssetLocator.status() {
        case .ready: .ready
        case .unavailable: .missing
        }
    }

    func download() {
        guard !isReady else { return }
        downloadTask?.cancel()
        let relay = DownloadProgressRelay(store: self)
        downloadTask = Task { [weak self] in
            do {
                try await ModelDownloader.install { step, total, name in
                    relay.report(step: step, total: total, name: name)
                }
                self?.refresh()
            } catch is CancellationError {
                self?.state = .missing
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func reportDownload(step: Int, total: Int, name: String) {
        state = .downloading(step: step, total: total, name: name)
    }
}

private final class DownloadProgressRelay: @unchecked Sendable {
    weak var store: ModelStore?

    init(store: ModelStore) { self.store = store }

    func report(step: Int, total: Int, name: String) {
        Task { @MainActor [weak store] in
            store?.reportDownload(step: step, total: total, name: name)
        }
    }
}

enum ModelDownloader {
    private struct FileSpec {
        let path: String
        let label: String
        let sha256: String?
    }

    private static let repository = "https://huggingface.co/dexxdean/htdemucs-coreml/resolve/main/HTDemucs_CoreML_FP16.mlpackage"
    private static let files = [
        FileSpec(path: "Manifest.json", label: "model manifest", sha256: nil),
        FileSpec(path: "Data/com.apple.CoreML/model.mlmodel", label: "model definition", sha256: "307ddf24af60111ba821d4ad6bf2d1d987d6531ca2f487b6a95ec16a16a9c644"),
        FileSpec(path: "Data/com.apple.CoreML/weights/weight.bin", label: "model weights", sha256: "efab790ad07d93faeb5a19b6e1eedad8c37ad351563a891a153fce307811c099"),
        FileSpec(path: "LICENSE", label: "license", sha256: nil),
        FileSpec(path: "ATTRIBUTION.md", label: "attribution", sha256: nil)
    ]

    static func install(progress: @escaping @Sendable (Int, Int, String) -> Void) async throws {
        let fileManager = FileManager.default
        let parent = ModelPaths.modelsDirectory
        let partial = parent.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: partial) }

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, files.count, file.label)
            let url = URL(string: "\(repository)/\(file.path)?download=true")!
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw HarmonyError.modelsRequired
            }
            let destination = partial.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: temporaryURL, to: destination)
            if let expected = file.sha256, try sha256(of: destination) != expected {
                throw HarmonyError.modelsRequired
            }
        }

        if fileManager.fileExists(atPath: ModelPaths.downloadedPackage.path) {
            try fileManager.removeItem(at: ModelPaths.downloadedPackage)
        }
        try fileManager.moveItem(at: partial, to: ModelPaths.downloadedPackage)
        try Data("validated".utf8).write(to: ModelPaths.validationMarker, options: .atomic)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Local HTDemucs Core ML runner. The downloaded FP16 package accepts 10 seconds
/// of 44.1 kHz stereo Float32 audio (`audio` [1,2,441000]) and produces four
/// stems (`sources` [1,4,2,441000]), with vocals at stem index zero.
final class CoreMLVocalIsolator: @unchecked Sendable {
    private let model: MLModel
    private let segmentSamples = 441_000
    private let overlapSamples = 44_100
    private let inferenceLock = NSLock()

    init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        let compiledURL = modelURL.pathExtension == "mlpackage" ? try MLModel.compileModel(at: modelURL) : modelURL
        model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        let description = model.modelDescription
        guard description.inputDescriptionsByName["audio"]?.type == .multiArray,
              description.outputDescriptionsByName["sources"]?.type == .multiArray else {
            throw HarmonyError.modelsRequired
        }
    }

    func isolate(_ sourceURL: URL, progress: @Sendable (Double) -> Void) throws -> [Float] {
        let mix = try loadStereo44k(sourceURL)
        let total = mix.count / 2
        guard total > 0 else { throw HarmonyError.invalidAudio }
        let stride = segmentSamples - overlapSamples
        let chunks = max(1, Int(ceil(Double(total) / Double(stride))))
        var vocal = [Float](repeating: 0, count: total)
        var weights = [Float](repeating: 0, count: total)
        let window = overlapWindow()

        for chunkIndex in 0..<chunks {
            try Task.checkCancellation()
            let start = chunkIndex * stride
            let predicted = try predictVocals(makeChunk(from: mix, start: start))
            for frame in 0..<segmentSamples {
                let destination = start + frame
                guard destination < total else { break }
                let weight = window[frame]
                vocal[destination] += (predicted[frame * 2] + predicted[frame * 2 + 1]) * 0.5 * weight
                weights[destination] += weight
            }
            progress(Double(chunkIndex + 1) / Double(chunks))
        }
        for frame in 0..<total { vocal[frame] /= max(weights[frame], 0.000_001) }
        return vocal
    }

    private func loadStereo44k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw HarmonyError.invalidAudio }
        let capacity = AVAudioFrameCount(Double(file.length) * 44_100 / file.processingFormat.sampleRate + 1)
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true; status.pointee = .haveData; return input
        }
        if let error { throw error }
        guard let left = output.floatChannelData?[0], let right = output.floatChannelData?[1] else { throw HarmonyError.invalidAudio }
        var interleaved = [Float](repeating: 0, count: Int(output.frameLength) * 2)
        for frame in 0..<Int(output.frameLength) {
            interleaved[frame * 2] = left[frame]
            interleaved[frame * 2 + 1] = right[frame]
        }
        return interleaved
    }

    private func overlapWindow() -> [Float] {
        var window = [Float](repeating: 1, count: segmentSamples)
        for index in 0..<overlapSamples {
            let weight = Float(index) / Float(overlapSamples)
            window[index] = weight; window[segmentSamples - 1 - index] = weight
        }
        return window
    }

    private func makeChunk(from mix: [Float], start: Int) -> [Float] {
        var chunk = [Float](repeating: 0, count: segmentSamples * 2)
        let frames = mix.count / 2
        for frame in 0..<segmentSamples where start + frame < frames {
            chunk[frame * 2] = mix[(start + frame) * 2]
            chunk[frame * 2 + 1] = mix[(start + frame) * 2 + 1]
        }
        return chunk
    }

    private func predictVocals(_ chunk: [Float]) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, 2, NSNumber(value: segmentSamples)], dataType: .float32)
        let inputPointer = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
        for frame in 0..<segmentSamples {
            inputPointer[frame] = chunk[frame * 2]
            inputPointer[segmentSamples + frame] = chunk[frame * 2 + 1]
        }
        inferenceLock.lock(); defer { inferenceLock.unlock() }
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": input]))
        guard let sources = result.featureValue(for: "sources")?.multiArrayValue, sources.count >= segmentSamples * 2 else {
            throw HarmonyError.modelsRequired
        }
        let output = sources.dataPointer.bindMemory(to: Float.self, capacity: sources.count)
        var vocal = [Float](repeating: 0, count: segmentSamples * 2)
        for frame in 0..<segmentSamples {
            vocal[frame * 2] = output[frame]
            vocal[frame * 2 + 1] = output[segmentSamples + frame]
        }
        return vocal
    }
}
