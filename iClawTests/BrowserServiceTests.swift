import XCTest
@testable import iClaw

final class BrowserErrorTests: XCTestCase {

    // MARK: - BrowserError Descriptions

    func testInvalidURLError() {
        let error = BrowserError.invalidURL("not-a-url")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not-a-url"))
    }

    func testNavigationTimeoutError() {
        let error = BrowserError.navigationTimeout
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("timeout") ||
                      error.errorDescription!.lowercased().contains("timed out"))
    }

    func testCannotGoBackError() {
        let error = BrowserError.cannotGoBack
        XCTAssertNotNil(error.errorDescription)
    }

    func testCannotGoForwardError() {
        let error = BrowserError.cannotGoForward
        XCTAssertNotNil(error.errorDescription)
    }

    func testJavaScriptError() {
        let error = BrowserError.javaScriptError("ReferenceError: foo is not defined")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("ReferenceError"))
    }

    func testElementNotFoundError() {
        let error = BrowserError.elementNotFound("Element not found: #missing")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("#missing"))
    }

    func testWaitTimeoutError() {
        let error = BrowserError.waitTimeout(".loading-spinner", 10)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(".loading-spinner"))
        XCTAssertTrue(error.errorDescription!.contains("10"))
    }
}

// MARK: - BrowserService Lock Mechanism

@MainActor
final class BrowserServiceLockTests: XCTestCase {

    func testInitialStateUnlocked() {
        let service = BrowserService.shared
        service.forceReleaseLock()
        XCTAssertFalse(service.isAgentControlled)
        XCTAssertNil(service.lockedBySessionId)
        XCTAssertNil(service.lockedByAgentName)
    }

    func testAcquireLockSuccess() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let sessionId = UUID()
        let error = service.acquireLock(sessionId: sessionId, agentName: "TestAgent")
        XCTAssertNil(error, "Should acquire lock successfully")
        XCTAssertTrue(service.isAgentControlled)
        XCTAssertEqual(service.lockedBySessionId, sessionId)
        XCTAssertEqual(service.lockedByAgentName, "TestAgent")

        service.forceReleaseLock()
    }

    func testAcquireLockSameSession() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let sessionId = UUID()
        _ = service.acquireLock(sessionId: sessionId, agentName: "Agent1")
        let error = service.acquireLock(sessionId: sessionId, agentName: "Agent1")
        XCTAssertNil(error, "Same session should re-acquire lock")

        service.forceReleaseLock()
    }

    func testAcquireLockDifferentSessionFails() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let session1 = UUID()
        let session2 = UUID()
        _ = service.acquireLock(sessionId: session1, agentName: "Agent1")
        let error = service.acquireLock(sessionId: session2, agentName: "Agent2")
        XCTAssertNotNil(error, "Different session should fail to acquire lock")
        XCTAssertTrue(error!.contains("Error"))

        service.forceReleaseLock()
    }

    func testReleaseLock() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let sessionId = UUID()
        _ = service.acquireLock(sessionId: sessionId, agentName: "Agent")
        XCTAssertTrue(service.isAgentControlled)

        service.releaseLock(sessionId: sessionId)
        XCTAssertFalse(service.isAgentControlled)
    }

    func testReleaseLockWrongSession() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let session1 = UUID()
        let session2 = UUID()
        _ = service.acquireLock(sessionId: session1, agentName: "Agent1")

        service.releaseLock(sessionId: session2)
        XCTAssertTrue(service.isAgentControlled, "Wrong session should not release lock")

        service.forceReleaseLock()
    }

    func testForceReleaseLock() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let sessionId = UUID()
        _ = service.acquireLock(sessionId: sessionId, agentName: "Agent")
        service.forceReleaseLock()
        XCTAssertFalse(service.isAgentControlled)
        XCTAssertNil(service.lockedBySessionId)
    }

    func testRefreshLock() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let sessionId = UUID()
        _ = service.acquireLock(sessionId: sessionId, agentName: "Agent")
        service.refreshLock(sessionId: sessionId)
        XCTAssertTrue(service.isAgentControlled)

        service.forceReleaseLock()
    }

    func testRefreshLockWrongSession() {
        let service = BrowserService.shared
        service.forceReleaseLock()

        let session1 = UUID()
        let session2 = UUID()
        _ = service.acquireLock(sessionId: session1, agentName: "Agent1")

        service.refreshLock(sessionId: session2)
        XCTAssertEqual(service.lockedBySessionId, session1)

        service.forceReleaseLock()
    }
}
