import XCTest
import SwiftData
import AVFoundation
@testable import iClaw

// MARK: - BackgroundKeepAliveMode Tests

final class BackgroundKeepAliveModeTests: XCTestCase {

    // MARK: Raw Values

    func testRawValueOff() {
        XCTAssertEqual(BackgroundKeepAliveMode.off.rawValue, "off")
    }

    func testRawValueSilentAudio() {
        XCTAssertEqual(BackgroundKeepAliveMode.silentAudio.rawValue, "silentAudio")
    }

    func testRawValueLiveActivity() {
        XCTAssertEqual(BackgroundKeepAliveMode.liveActivity.rawValue, "liveActivity")
    }

    // MARK: CaseIterable

    func testAllCasesContainsThreeOptions() {
        XCTAssertEqual(BackgroundKeepAliveMode.allCases.count, 3)
    }

    func testAllCasesContainsExpectedValues() {
        let cases = BackgroundKeepAliveMode.allCases
        XCTAssertTrue(cases.contains(.off))
        XCTAssertTrue(cases.contains(.silentAudio))
        XCTAssertTrue(cases.contains(.liveActivity))
    }

    // MARK: Identifiable

    func testIdentifiableIdMatchesRawValue() {
        for mode in BackgroundKeepAliveMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    // MARK: Round-trip

    func testRoundTripFromRawValue() {
        for mode in BackgroundKeepAliveMode.allCases {
            let reconstructed = BackgroundKeepAliveMode(rawValue: mode.rawValue)
            XCTAssertEqual(reconstructed, mode)
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(BackgroundKeepAliveMode(rawValue: "invalid"))
        XCTAssertNil(BackgroundKeepAliveMode(rawValue: ""))
        XCTAssertNil(BackgroundKeepAliveMode(rawValue: "SILENT_AUDIO"))
    }
}

// MARK: - SilentAudioPlayer WAV Generation Tests

final class SilentAudioWAVTests: XCTestCase {

    private var wavData: Data!

    override func setUp() {
        super.setUp()
        wavData = SilentAudioPlayer.generateSilentWAV()
    }

    override func tearDown() {
        wavData = nil
        super.tearDown()
    }

    func testGeneratedDataIsNotNil() {
        XCTAssertNotNil(wavData)
    }

    func testGeneratedDataIsNotEmpty() {
        XCTAssertFalse(wavData.isEmpty)
    }

    /// WAV = 44-byte header + (8000 samples * 2 bytes) = 16044 bytes
    func testExpectedFileSize() {
        let expectedHeaderSize = 44
        let expectedDataSize = 8000 * 2  // 8kHz * 16-bit mono
        XCTAssertEqual(wavData.count, expectedHeaderSize + expectedDataSize)
    }

    func testStartsWithRIFFHeader() {
        let riff = String(data: wavData.prefix(4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")
    }

    func testContainsWAVEFormat() {
        let wave = String(data: wavData.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")
    }

    func testContainsFmtChunk() {
        let fmt = String(data: wavData.subdata(in: 12..<16), encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")
    }

    func testFmtChunkIndicatesPCM() {
        // Audio format at offset 20, 2 bytes little-endian
        let format = wavData.subdata(in: 20..<22).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: format), 1, "Audio format 1 = PCM")
    }

    func testFmtChunkIndicatesMono() {
        let channels = wavData.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: channels), 1, "Should be mono (1 channel)")
    }

    func testFmtChunkSampleRate() {
        let sampleRate = wavData.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: sampleRate), 8000)
    }

    func testFmtChunkBitsPerSample() {
        let bps = wavData.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: bps), 16)
    }

    func testContainsDataChunk() {
        let dataChunk = String(data: wavData.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataChunk, "data")
    }

    func testDataChunkSizeMatchesSampleData() {
        let dataSize = wavData.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: dataSize), 16000, "8000 samples * 2 bytes = 16000")
    }

    /// All PCM samples must be zero (silence).
    func testAudioDataIsAllZeros() {
        let audioData = wavData.subdata(in: 44..<wavData.count)
        let allZero = audioData.allSatisfy { $0 == 0 }
        XCTAssertTrue(allZero, "Silent WAV data section must be all zeros")
    }

    /// Verify the RIFF file size field is consistent with the actual data length.
    func testRIFFFileSizeFieldIsConsistent() {
        let fileSizeField = wavData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        // RIFF file size = total file size - 8 (for "RIFF" + size field itself)
        XCTAssertEqual(UInt32(littleEndian: fileSizeField), UInt32(wavData.count - 8))
    }

    /// The generated WAV should be parseable by AVAudioPlayer.
    func testWAVIsLoadableByAVAudioPlayer() {
        // AVAudioPlayer can parse the data even without a hardware audio route
        XCTAssertNoThrow(try AVAudioPlayer(data: wavData))
    }
}

// MARK: - SilentAudioPlayer State Tests

final class SilentAudioPlayerStateTests: XCTestCase {

    @MainActor
    func testInitialStateIsNotPlaying() {
        let player = SilentAudioPlayer()
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testStopFromStoppedStateDoesNotCrash() {
        let player = SilentAudioPlayer()
        XCTAssertFalse(player.isPlaying)
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testStopResetsIsPlayingToFalse() {
        let player = SilentAudioPlayer()
        // Even if start fails (no audio route in tests), stop should be safe
        player.start()
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
}

// MARK: - BackgroundKeepAliveManager Tests

final class BackgroundKeepAliveManagerTests: XCTestCase {

    private let testSuiteKey = BackgroundKeepAliveManager.modeKey

    override func tearDown() {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: testSuiteKey)
        super.tearDown()
    }

    // MARK: Mode Key

    func testModeKeyIsExpectedString() {
        XCTAssertEqual(BackgroundKeepAliveManager.modeKey, "backgroundKeepAliveMode")
    }

    // MARK: Default Mode

    @MainActor
    func testDefaultModeIsOff() {
        UserDefaults.standard.removeObject(forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertEqual(manager.mode, .off)
    }

    // MARK: Mode Persistence

    @MainActor
    func testSetModePersistsToUserDefaults() {
        let manager = BackgroundKeepAliveManager()
        manager.mode = .silentAudio
        let stored = UserDefaults.standard.string(forKey: testSuiteKey)
        XCTAssertEqual(stored, "silentAudio")
    }

    @MainActor
    func testModeReadsFromUserDefaults() {
        UserDefaults.standard.set("liveActivity", forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertEqual(manager.mode, .liveActivity)
    }

    @MainActor
    func testInvalidStoredValueDefaultsToOff() {
        UserDefaults.standard.set("garbage", forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertEqual(manager.mode, .off)
    }

    @MainActor
    func testMissingKeyDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertEqual(manager.mode, .off)
    }

    // MARK: Mode Round-Trip

    @MainActor
    func testModeRoundTrip() {
        let manager = BackgroundKeepAliveManager()
        for mode in BackgroundKeepAliveMode.allCases {
            manager.mode = mode
            XCTAssertEqual(manager.mode, mode)
        }
    }

    // MARK: Deactivate Safety

    @MainActor
    func testDeactivateFromCleanStateDoesNotCrash() {
        let manager = BackgroundKeepAliveManager()
        manager.deactivate()
        // Should not crash
    }

    @MainActor
    func testDoubleDeactivateDoesNotCrash() {
        let manager = BackgroundKeepAliveManager()
        manager.deactivate()
        manager.deactivate()
    }

    // MARK: Activate with Off Mode

    @MainActor
    func testActivateWithOffModeIsNoOp() {
        UserDefaults.standard.removeObject(forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        // Should not crash and should do nothing
        manager.activate(runningJobCount: 5)
    }

    // MARK: onJobsChanged with Off Mode

    @MainActor
    func testOnJobsChangedWithOffModeIsNoOp() {
        UserDefaults.standard.removeObject(forKey: testSuiteKey)
        let manager = BackgroundKeepAliveManager()
        manager.onJobsChanged(runningCount: 3)
        manager.onJobsChanged(runningCount: 0)
    }

    // MARK: Setting Mode Calls Deactivate

    @MainActor
    func testSettingModeCallsDeactivate() {
        let manager = BackgroundKeepAliveManager()
        // Start in silentAudio mode
        UserDefaults.standard.set("silentAudio", forKey: testSuiteKey)
        // Switch to liveActivity — should deactivate previous
        manager.mode = .liveActivity
        // No crash, mode updated
        XCTAssertEqual(manager.mode, .liveActivity)
    }
}

// MARK: - CronActivityAttributes Tests

final class CronActivityAttributesTests: XCTestCase {

    // MARK: ContentState Codable

    func testContentStateEncodeDecode() throws {
        let state = CronActivityAttributes.ContentState(
            runningJobCount: 3,
            statusText: "Running daily report…"
        )
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            CronActivityAttributes.ContentState.self,
            from: encoded
        )
        XCTAssertEqual(decoded.runningJobCount, 3)
        XCTAssertEqual(decoded.statusText, "Running daily report…")
    }

    func testContentStateDecodesFromJSON() throws {
        let json = """
        {"runningJobCount": 5, "statusText": "Processing…"}
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(
            CronActivityAttributes.ContentState.self,
            from: json
        )
        XCTAssertEqual(state.runningJobCount, 5)
        XCTAssertEqual(state.statusText, "Processing…")
    }

    // MARK: ContentState Hashable

    func testContentStateEquality() {
        let a = CronActivityAttributes.ContentState(runningJobCount: 2, statusText: "Running")
        let b = CronActivityAttributes.ContentState(runningJobCount: 2, statusText: "Running")
        XCTAssertEqual(a, b)
    }

    func testContentStateInequalityByCount() {
        let a = CronActivityAttributes.ContentState(runningJobCount: 1, statusText: "Running")
        let b = CronActivityAttributes.ContentState(runningJobCount: 2, statusText: "Running")
        XCTAssertNotEqual(a, b)
    }

    func testContentStateInequalityByStatus() {
        let a = CronActivityAttributes.ContentState(runningJobCount: 1, statusText: "Running")
        let b = CronActivityAttributes.ContentState(runningJobCount: 1, statusText: "Done")
        XCTAssertNotEqual(a, b)
    }

    func testContentStateHashConsistency() {
        let state = CronActivityAttributes.ContentState(runningJobCount: 4, statusText: "Test")
        let hash1 = state.hashValue
        let hash2 = state.hashValue
        XCTAssertEqual(hash1, hash2)
    }

    func testEqualStatesHaveEqualHashes() {
        let a = CronActivityAttributes.ContentState(runningJobCount: 3, statusText: "Same")
        let b = CronActivityAttributes.ContentState(runningJobCount: 3, statusText: "Same")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testContentStateWorksInSet() {
        let s1 = CronActivityAttributes.ContentState(runningJobCount: 1, statusText: "A")
        let s2 = CronActivityAttributes.ContentState(runningJobCount: 2, statusText: "B")
        let s3 = CronActivityAttributes.ContentState(runningJobCount: 1, statusText: "A") // duplicate
        let set: Set = [s1, s2, s3]
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - CronLiveActivityManager State Tests

final class CronLiveActivityManagerStateTests: XCTestCase {

    @MainActor
    func testInitialStateIsInactive() {
        let manager = CronLiveActivityManager()
        XCTAssertFalse(manager.isActive)
    }

    @MainActor
    func testStopFromInactiveStateDoesNotCrash() {
        let manager = CronLiveActivityManager()
        XCTAssertFalse(manager.isActive)
        manager.stop()
        XCTAssertFalse(manager.isActive)
    }

    @MainActor
    func testUpdateWithNoActivityDoesNotCrash() {
        let manager = CronLiveActivityManager()
        manager.update(runningJobCount: 5, statusText: "test")
        // No crash — silently returns when no current activity
    }

    @MainActor
    func testDoubleStopDoesNotCrash() {
        let manager = CronLiveActivityManager()
        manager.stop()
        manager.stop()
        XCTAssertFalse(manager.isActive)
    }
}

// MARK: - CronScheduler KeepAlive Integration Tests

final class CronSchedulerKeepAliveTests: XCTestCase {

    private var container: ModelContainer!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    func testKeepAliveManagerIsNilByDefault() {
        let scheduler = CronScheduler(modelContainer: container)
        XCTAssertNil(scheduler.keepAliveManager)
        scheduler.stop()
    }

    @MainActor
    func testKeepAliveManagerCanBeSet() {
        let scheduler = CronScheduler(modelContainer: container)
        let manager = BackgroundKeepAliveManager()
        scheduler.keepAliveManager = manager
        XCTAssertNotNil(scheduler.keepAliveManager)
        scheduler.stop()
    }

    @MainActor
    func testSchedulerStartDoesNotRequireKeepAliveManager() {
        let scheduler = CronScheduler(modelContainer: container)
        XCTAssertNil(scheduler.keepAliveManager)
        scheduler.start()
        XCTAssertTrue(scheduler.isRunning)
        scheduler.stop()
    }

    @MainActor
    func testSchedulerRunningJobsStartEmpty() {
        let scheduler = CronScheduler(modelContainer: container)
        let manager = BackgroundKeepAliveManager()
        scheduler.keepAliveManager = manager
        scheduler.start()
        XCTAssertTrue(scheduler.runningJobIds.isEmpty)
        scheduler.stop()
    }

    @MainActor
    func testPauseResumeWithKeepAliveManager() {
        let scheduler = CronScheduler(modelContainer: container)
        let manager = BackgroundKeepAliveManager()
        scheduler.keepAliveManager = manager
        scheduler.start()
        scheduler.pause()
        scheduler.resume()
        XCTAssertTrue(scheduler.isRunning)
        scheduler.stop()
    }
}

// MARK: - Info.plist Capability Tests

final class BackgroundKeepAliveInfoPlistTests: XCTestCase {

    /// Verify that the `audio` background mode is declared in Info.plist.
    func testAudioBackgroundModeIsRegistered() {
        let bundle = Bundle(for: CronScheduler.self)
        guard let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            XCTFail("UIBackgroundModes not found in Info.plist")
            return
        }
        XCTAssertTrue(modes.contains("audio"),
                      "Info.plist must declare 'audio' in UIBackgroundModes for silent playback. Found: \(modes)")
    }

    /// Verify that Live Activities support is declared.
    func testNSSupportsLiveActivitiesIsTrue() {
        let bundle = Bundle(for: CronScheduler.self)
        let supports = bundle.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool
        XCTAssertEqual(supports, true,
                       "Info.plist must set NSSupportsLiveActivities to true")
    }

    /// Existing background modes should still be present.
    func testExistingBackgroundModesPreserved() {
        let bundle = Bundle(for: CronScheduler.self)
        guard let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            XCTFail("UIBackgroundModes not found")
            return
        }
        XCTAssertTrue(modes.contains("fetch"), "fetch mode should be preserved")
        XCTAssertTrue(modes.contains("processing"), "processing mode should be preserved")
    }
}
