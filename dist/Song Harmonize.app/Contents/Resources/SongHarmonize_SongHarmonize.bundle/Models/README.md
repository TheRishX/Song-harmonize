# Bundled model location

The distributable app keeps its model package out of the initial download. At first use, the user can download the verified Core ML package directly from the app:

```
Application Support/SongHarmonize/Models/HTDemucs_CoreML_FP16.mlpackage
```

The app compiles this package locally on its first use, runs it on CPU/GPU, and checks its `audio` / `sources` interface before generation. Keep the upstream license, model card, source revision, SHA-256 checksum, and Core ML conversion script in the release's `THIRD_PARTY_NOTICES.md`.
