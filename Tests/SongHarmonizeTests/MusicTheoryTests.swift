import XCTest
@testable import SongHarmonize

final class MusicTheoryTests: XCTestCase {
    func testKeyDetectorRecognizesCMajorPitchClasses() {
        let key = KeyDetector.detect(from: [60, 64, 67, 72, 76, 79, 84])
        XCTAssertEqual(key, MusicalKey(tonic: 0, isMinor: false))
    }

    func testHarmonyPartsRemainInTheirVoiceRanges() {
        let key = MusicalKey(tonic: 0, isMinor: false)
        let roles: [(HarmonyRole, ClosedRange<Int>)] = [(.low, 45...62), (.mid, 55...72), (.high, 60...81)]
        for source in stride(from: 48, through: 84, by: 3) {
            for (role, range) in roles {
                XCTAssertTrue(range.contains(HarmonyPlanner.targetPitch(sourceMidi: source, role: role, key: key)))
            }
        }
    }

    func testSilenceDoesNotCreateAPitchFrame() {
        let frames = PitchTracker.frames(samples: Array(repeating: 0, count: 8_192), sampleRate: 44_100)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.midi == nil })
    }

    func testExportFileNamesAreDeterministic() {
        XCTAssertEqual(HarmonyRole.low.filenameSuffix, "– Low Harmony.wav")
        XCTAssertEqual(HarmonyRole.mid.filenameSuffix, "– Mid Harmony.wav")
        XCTAssertEqual(HarmonyRole.high.filenameSuffix, "– High Harmony.wav")
    }
}
