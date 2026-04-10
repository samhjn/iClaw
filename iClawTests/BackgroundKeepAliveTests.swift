import XCTest
import SwiftData
@testable import iClaw

// MARK: - BackgroundKeepAliveManager Tests

final class BackgroundKeepAliveManagerTests: XCTestCase {

    private let testKey = BackgroundKeepAliveManager.enabledKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    // MARK: Enabled Key

    func testEnabledKeyIsExpectedString() {
        XCTAssertEqual(BackgroundKeepAliveManager.enabledKey, "backgroundKeepAliveEnabled")
    }

    // MARK: Default State

    @MainActor
    func testDefaultIsDisabled() {
        UserDefaults.standard.removeObject(forKey: testKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertFalse(manager.isEnabled)
    }

    // MARK: Persistence

    @MainActor
    func testEnablePersistsToUserDefaults() {
        let manager = BackgroundKeepAliveManager()
        manager.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: testKey))
    }

    @MainActor
    func testDisablePersistsToUserDefaults() {
        let manager = BackgroundKeepAliveManager()
        manager.isEnabled = true
        manager.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: testKey))
    }

    @MainActor
    func testReadsFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: testKey)
        let manager = BackgroundKeepAliveManager()
        XCTAssertTrue(manager.isEnabled)
    }

    // MARK: Round-Trip

    @MainActor
    func testRoundTrip() {
        let manager = BackgroundKeepAliveManager()
        manager.isEnabled = true
        XCTAssertTrue(manager.isEnabled)
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
    }

    // MARK: Deactivate Safety

    @MainActor
    func testDeactivateFromCleanStateDoesNotCrash() {
        let manager = BackgroundKeepAliveManager()
        manager.deactivate()
    }

    @MainActor
    func testDoubleDeactivateDoesNotCrash() {
        let manager = BackgroundKeepAliveManager()
        manager.deactivate()
        manager.deactivate()
    }

    // MARK: Activate When Disabled

    @MainActor
    func testActivateWhenDisabledIsNoOp() {
        UserDefaults.standard.removeObject(forKey: testKey)
        let manager = BackgroundKeepAliveManager()
        manager.activate(runningJobCount: 5)
    }

    // MARK: onJobsChanged When Disabled

    @MainActor
    func testOnJobsChangedWhenDisabledIsNoOp() {
        UserDefaults.standard.removeObject(forKey: testKey)
        let manager = BackgroundKeepAliveManager()
        manager.onJobsChanged(runningCount: 3)
        manager.onJobsChanged(runningCount: 0)
    }

    // MARK: Disabling Calls Deactivate

    @MainActor
    func testDisablingCallsDeactivate() {
        let manager = BackgroundKeepAliveManager()
        manager.isEnabled = true
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
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

    /// Verify that Live Activities support is declared.
    func testNSSupportsLiveActivitiesIsTrue() {
        let bundle = Bundle(for: CronScheduler.self)
        let supports = bundle.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool
        XCTAssertEqual(supports, true,
                       "Info.plist must set NSSupportsLiveActivities to true")
    }

    /// Audio background mode should NOT be present (removed for review safety).
    func testAudioBackgroundModeIsNotPresent() {
        let bundle = Bundle(for: CronScheduler.self)
        guard let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            XCTFail("UIBackgroundModes not found in Info.plist")
            return
        }
        XCTAssertFalse(modes.contains("audio"),
                       "audio background mode should not be declared. Found: \(modes)")
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
