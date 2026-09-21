# Song Harmonize

Song Harmonize is a free, local-only macOS app for deriving three same-singer vocal harmony stems from a song. It is an Apple-silicon SwiftUI app with no account, network API, telemetry, or subscription.

## Run locally

Open `Package.swift` in Xcode 16 or later, select the `SongHarmonize` scheme, and run. The command-line build can be checked with `swift test`.

## Model download

The app shows a **Download AI Model** button on first launch. It downloads the MIT-licensed, 232 MB `HTDemucs_CoreML_FP16.mlpackage` directly from its public source, verifies the published SHA-256 hashes, and saves it under `Application Support/SongHarmonize/Models`. The app automatically connects to that local package once validation succeeds; the model is then available offline.

The music-theory planner and pitch tracker are app-native and require no additional model or network service. Keep the model's attribution and checksum information in `THIRD_PARTY_NOTICES.md` when distributing the app.

## Release notes

The intended zero-cost distribution is a source release plus unsigned GitHub DMG/ZIP. Users may need to use Finder's Open command to approve the app. Do not upload audio; all processing runs locally.
