# Song Harmonize

Song Harmonize is a free, local-only macOS app for deriving three same-singer vocal harmony stems from a song. It is an Apple-silicon SwiftUI app with no account, network API, telemetry, or subscription.

## Run locally

Open `Package.swift` in Xcode 16 or later, select the `SongHarmonize` scheme, and run. The command-line build can be checked with `swift test`.

## Model assets

The release app is designed to bundle two compiled Core ML model directories in `Sources/SongHarmonize/Resources/Models`:

- `Demucs.mlmodelc` — source separation; upstream code is MIT licensed.
- `BasicPitch.mlmodelc` — note detection; upstream project is Apache-2.0 licensed.

They are intentionally **not** represented by fake model binaries in source control. Add verified, compatible Core ML conversions and their model-card/license files during release packaging. Until those assets are added, the app remains usable in its clearly labelled preview-isolation mode, which derives harmony from the supplied mix and is not suitable for dry vocal stems.

## Release notes

The intended zero-cost distribution is a source release plus unsigned GitHub DMG/ZIP. Users may need to use Finder's Open command to approve the app. Do not upload audio; all processing runs locally.
