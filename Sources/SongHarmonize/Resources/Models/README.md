# Bundled model location

Release packaging places verified compiled Core ML directories here:

```
Models/Demucs.mlmodelc
Models/BasicPitch.mlmodelc
```

The app checks these paths before generation. Keep the upstream license, model card, source revision, SHA-256 checksum, and Core ML conversion script in the release's `THIRD_PARTY_NOTICES.md`.
