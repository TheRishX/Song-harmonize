import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = HarmonyJobViewModel()
    @StateObject private var uiState = ContentUIState()
    @StateObject private var modelStore = ModelStore()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    header
                    VStack(spacing: 18) {
                        songCard
                        modelCard
                        processingCard
                        actionArea
                        resultArea
                    }
                    .frame(maxWidth: 760)
                    legalNotice
                }
                .padding(.horizontal, 42)
                .padding(.vertical, 30)
            }
        }
        .fileImporter(
            isPresented: $uiState.isImporting,
            allowedContentTypes: [.wav, .aiff, .mpeg4Audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.choose(url)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 31, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("Song Harmonize")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Three harmony stems. On your Mac. From your song.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Label("Local only", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Apple Silicon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var songCard: some View {
        if let song = viewModel.song {
            selectedSong(song)
        } else {
            dropZone
        }
    }

    private var dropZone: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 70, height: 70)
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.tint)
            }
            Text("Drop a song to get started")
                .font(.title3.weight(.semibold))
            Text("WAV, AIFF, M4A, or MP3 · Files never leave your Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Song…") { uiState.isImporting = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 265)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(uiState.isDropTargeted ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(uiState.isDropTargeted ? Color.accentColor : .secondary.opacity(0.26), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
        }
        .onDrop(of: [.fileURL], isTargeted: $uiState.isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { viewModel.choose(url) } }
            }
            return true
        }
    }

    private func selectedSong(_ song: SongInfo) -> some View {
        HStack(spacing: 17) {
            Image(systemName: "music.note")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("Selected song").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(song.displayName).font(.headline).lineLimit(1)
                Text("\(formatted(song.duration))  ·  \(Int(song.sampleRate)) Hz  ·  Ready for local processing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Replace") { uiState.isImporting = true }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.separator.opacity(0.4)))
    }

    private var processingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What you’ll get").font(.headline)
                    Text("Three aligned 24-bit WAV harmony parts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "cpu")
                    .foregroundStyle(.tint)
            }
            HStack(spacing: 10) {
                FeaturePill(icon: "arrow.down.left.and.arrow.up.right", title: "Low")
                FeaturePill(icon: "music.note", title: "Mid")
                FeaturePill(icon: "arrow.up.right", title: "High")
                Spacer()
                Text("WAV · 44.1 kHz")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var modelCard: some View {
        switch modelStore.state {
        case .ready:
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI vocal model ready").font(.headline)
                    Text("HTDemucs runs privately on this Mac using Apple Silicon GPU acceleration.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("On-device")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(18)
            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .missing:
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Download the free AI vocal model").font(.headline)
                    Text("One-time 233 MB download. It remains on your Mac and no audio is uploaded.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Download") { modelStore.download() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case let .downloading(step, total, name):
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Downloading AI model", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Spacer()
                    Text("\(step) of \(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(step - 1), total: Double(total))
                Text("Downloading \(name)… This is a one-time setup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case let .failed(message):
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Model download failed").font(.headline)
                    Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Try Again") { modelStore.download() }.buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder private var actionArea: some View {
        if viewModel.isWorking {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(viewModel.stage.rawValue, systemImage: stageSymbol)
                        .font(.headline)
                    Spacer()
                    Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.progress)
                    .tint(.accentColor)
                Button("Cancel Generation", role: .cancel) { viewModel.cancel() }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Button(action: viewModel.generate) {
                Label("Generate Harmonies", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.song == nil || !modelStore.isReady)
        }
    }

    @ViewBuilder private var resultArea: some View {
        if !viewModel.exports.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your harmony stems are ready").font(.headline)
                        if let key = viewModel.detectedKey {
                            Text("Detected key: \(key.displayName)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Reveal All") { viewModel.revealExports() }
                        .buttonStyle(.bordered)
                }
                ForEach(viewModel.exports) { export in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(export.role.rawValue) harmony").font(.subheadline.weight(.semibold))
                            Text(export.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([export.url]) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if !viewModel.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(viewModel.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle.fill")
                }
            }
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var legalNotice: some View {
        Text("Only process music you have permission to use. Dense mixes, choirs, and heavily processed vocals may produce artifacts. Song Harmonize does not upload audio or collect usage data.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 650)
    }

    private var stageSymbol: String {
        switch viewModel.stage {
        case .loading: "arrow.down.circle"
        case .separating: "waveform"
        case .analyzing: "waveform.path.ecg"
        case .arranging: "music.quarternote.3"
        case .rendering: "square.and.arrow.down"
        default: "gearshape"
        }
    }

    private func formatted(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

private struct FeaturePill: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.11), in: Capsule())
            .foregroundStyle(.tint)
    }
}

@MainActor
private final class ContentUIState: ObservableObject {
    @Published var isImporting = false
    @Published var isDropTargeted = false
}
