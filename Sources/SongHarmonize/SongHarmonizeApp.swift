import SwiftUI
import Darwin

@main
struct SongHarmonizeApp: App {
    init() {
        if CommandLine.arguments.contains("--self-check") {
            exit(HarmonySelfCheck.run())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 680)
        }
        .windowResizability(.automatic)
    }
}
