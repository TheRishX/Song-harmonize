import Foundation

struct MusicalKey: Hashable, Sendable {
    let tonic: Int
    let isMinor: Bool

    static let cMajor = MusicalKey(tonic: 0, isMinor: false)

    var displayName: String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return names[tonic] + (isMinor ? " minor" : " major")
    }

    var scale: [Int] {
        let intervals = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return intervals.map { ($0 + tonic) % 12 }
    }
}

struct PitchFrame: Sendable {
    let start: Int
    let length: Int
    let midi: Int?
}

enum KeyDetector {
    // Krumhansl-Schmuckler pitch-class profiles. Frames without a confident pitch
    // deliberately have no vote, which avoids treating silence as C.
    static func detect(from pitches: [Int]) -> MusicalKey {
        guard !pitches.isEmpty else { return .cMajor }
        var histogram = Array(repeating: 0.0, count: 12)
        for pitch in pitches { histogram[positiveModulo(pitch, 12)] += 1 }
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

        var best = (key: MusicalKey.cMajor, score: -Double.infinity)
        for tonic in 0..<12 {
            for (isMinor, profile) in [(false, major), (true, minor)] {
                let score = zip(0..<12, profile).reduce(0.0) { partial, pair in
                    partial + histogram[(pair.0 + tonic) % 12] * pair.1
                }
                if score > best.score { best = (MusicalKey(tonic: tonic, isMinor: isMinor), score) }
            }
        }
        return best.key
    }
}

enum HarmonyPlanner {
    static func targetPitch(sourceMidi: Int, role: HarmonyRole, key: MusicalKey) -> Int {
        let degree = nearestScaleDegree(for: sourceMidi, key: key)
        let degreeOffset: Int
        let range: ClosedRange<Int>
        switch role {
        case .low: degreeOffset = -2; range = 45...62
        case .mid: degreeOffset = 2; range = 55...72
        case .high: degreeOffset = 4; range = 60...81
        }
        let targetDegree = degree + degreeOffset
        let scale = key.scale
        let octaveDelta = floorDiv(targetDegree, scale.count)
        let scaleIndex = positiveModulo(targetDegree, scale.count)
        let sourceOctave = floorDiv(sourceMidi, 12)
        var target = sourceOctave * 12 + scale[scaleIndex] + octaveDelta * 12

        while target < range.lowerBound { target += 12 }
        while target > range.upperBound { target -= 12 }
        return target
    }

    static func semitoneShift(sourceMidi: Int, role: HarmonyRole, key: MusicalKey) -> Int {
        targetPitch(sourceMidi: sourceMidi, role: role, key: key) - sourceMidi
    }

    private static func nearestScaleDegree(for midi: Int, key: MusicalKey) -> Int {
        let pitchClass = positiveModulo(midi, 12)
        let candidates = key.scale.enumerated().map { index, note -> (degree: Int, distance: Int) in
            let up = positiveModulo(pitchClass - note, 12)
            let distance = min(up, 12 - up)
            return (index, distance)
        }
        return candidates.min { $0.distance < $1.distance }?.degree ?? 0
    }
}

enum PitchTracker {
    // Fast, intentionally conservative zero-crossing tracker. The production
    // Basic Pitch model refines this once its bundled asset is present.
    static func frames(samples: [Float], sampleRate: Double) -> [PitchFrame] {
        let window = 4_096
        let hop = 2_048
        guard samples.count >= window else { return [] }
        return stride(from: 0, through: samples.count - window, by: hop).map { start in
            let slice = samples[start..<(start + window)]
            let rms = sqrt(slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(window))
            guard rms > 0.008 else { return PitchFrame(start: start, length: hop, midi: nil) }
            var crossings = 0
            var previous = slice.first ?? 0
            for value in slice.dropFirst() {
                if (previous <= 0 && value > 0) || (previous >= 0 && value < 0) { crossings += 1 }
                previous = value
            }
            let frequency = Double(crossings) * sampleRate / (2.0 * Double(window))
            guard frequency >= 70, frequency <= 1_100 else {
                return PitchFrame(start: start, length: hop, midi: nil)
            }
            let midi = Int((69.0 + 12.0 * log2(frequency / 440.0)).rounded())
            return PitchFrame(start: start, length: hop, midi: midi)
        }
    }
}

private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
}

private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    let quotient = value / divisor
    return value < 0 && value % divisor != 0 ? quotient - 1 : quotient
}
