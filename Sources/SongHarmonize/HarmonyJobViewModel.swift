import AppKit
import Foundation

@MainActor
final class HarmonyJobViewModel: ObservableObject {
    @Published private(set) var song: SongInfo?
    @Published private(set) var stage: JobStage = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var exports: [HarmonyExport] = []
    @Published private(set) var warnings: [String] = []
    @Published private(set) var detectedKey: MusicalKey?
    @Published var errorMessage: String?

    var isWorking: Bool {
        [.loading, .separating, .analyzing, .arranging, .rendering].contains(stage)
    }

    private var job: Task<Void, Never>?

    func choose(_ url: URL) {
        job?.cancel()
        guard SupportedAudio.isSupported(url) else {
            errorMessage = HarmonyError.unsupportedFormat.localizedDescription
            return
        }
        do {
            song = try AudioInspector.inspect(url)
            stage = .idle
            progress = 0
            exports = []
            warnings = []
            detectedKey = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generate() {
        guard let song, !isWorking else { return }
        exports = []
        warnings = []
        errorMessage = nil
        job = Task { [weak self] in
            guard let self else { return }
            let accessed = song.url.startAccessingSecurityScopedResource()
            defer {
                if accessed { song.url.stopAccessingSecurityScopedResource() }
            }
            do {
                let result = try await HarmonyPipeline().generate(from: song.url) { update in
                    Task { @MainActor in
                        self.stage = update.stage
                        self.progress = update.progress
                    }
                }
                guard !Task.isCancelled else { throw HarmonyError.cancelled }
                exports = result.exports
                warnings = result.warnings
                detectedKey = result.key
                stage = .complete
                progress = 1
            } catch is CancellationError {
                stage = .cancelled
            } catch let error as HarmonyError {
                if case .cancelled = error {
                    stage = .cancelled
                } else {
                    errorMessage = error.localizedDescription
                    stage = .failed
                }
            } catch {
                errorMessage = error.localizedDescription
                stage = .failed
            }
        }
    }

    func cancel() {
        job?.cancel()
        stage = .cancelled
    }

    func revealExports() {
        NSWorkspace.shared.activateFileViewerSelecting(exports.map(\.url))
    }
}

private enum SupportedAudio {
    private static let extensions = Set(["wav", "wave", "aif", "aiff", "m4a", "mp3"])
    static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
