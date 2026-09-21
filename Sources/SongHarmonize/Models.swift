import Foundation

enum JobStage: String, CaseIterable, Sendable {
    case idle = "Ready"
    case loading = "Reading audio"
    case separating = "Isolating lead vocal"
    case analyzing = "Finding melody and key"
    case arranging = "Writing harmony parts"
    case rendering = "Rendering WAV stems"
    case complete = "Complete"
    case failed = "Could not generate"
    case cancelled = "Cancelled"
}

struct SongInfo: Sendable {
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double

    var displayName: String { url.deletingPathExtension().lastPathComponent }
}

struct HarmonyExport: Identifiable, Sendable {
    let role: HarmonyRole
    let url: URL
    var id: URL { url }
}

enum HarmonyRole: String, CaseIterable, Sendable {
    case low = "Low"
    case mid = "Mid"
    case high = "High"

    var filenameSuffix: String { "– \(rawValue) Harmony.wav" }
}

struct GenerationResult: Sendable {
    let exports: [HarmonyExport]
    let key: MusicalKey
    let warnings: [String]
}

enum HarmonyError: LocalizedError {
    case unsupportedFormat
    case invalidAudio
    case exportFailed
    case cancelled
    case modelsRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Choose a WAV, AIFF, M4A, or MP3 file."
        case .invalidAudio: "This audio file could not be decoded."
        case .exportFailed: "The harmony stems could not be written."
        case .cancelled: "Generation was cancelled."
        case .modelsRequired: "The bundled Core ML model assets are unavailable."
        }
    }
}
