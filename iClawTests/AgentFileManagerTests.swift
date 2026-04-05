import XCTest
@testable import iClaw

final class AgentFileManagerTests: XCTestCase {

    private var fm: AgentFileManager!
    private var testAgentId: UUID!

    override func setUp() {
        super.setUp()
        fm = AgentFileManager.shared
        testAgentId = UUID()
    }

    override func tearDown() {
        fm.cleanupAgentFiles(agentId: testAgentId)
        fm = nil
        testAgentId = nil
        super.tearDown()
    }

    // MARK: - File CRUD

    func testWriteReadDeleteCycle() throws {
        let name = "test.txt"
        let content = Data("Hello, World!".utf8)

        try fm.writeFile(agentId: testAgentId, name: name, data: content)
        XCTAssertTrue(fm.fileExists(agentId: testAgentId, name: name))

        let read = try fm.readFile(agentId: testAgentId, name: name)
        XCTAssertEqual(read, content)

        try fm.deleteFile(agentId: testAgentId, name: name)
        XCTAssertFalse(fm.fileExists(agentId: testAgentId, name: name))
    }

    func testListFiles() throws {
        try fm.writeFile(agentId: testAgentId, name: "a.txt", data: Data("a".utf8))
        try fm.writeFile(agentId: testAgentId, name: "b.json", data: Data("{}".utf8))

        let list = fm.listFiles(agentId: testAgentId)
        XCTAssertEqual(list.count, 2)

        let names = Set(list.map(\.name))
        XCTAssertTrue(names.contains("a.txt"))
        XCTAssertTrue(names.contains("b.json"))
    }

    func testListFilesEmpty() {
        let list = fm.listFiles(agentId: testAgentId)
        XCTAssertTrue(list.isEmpty)
    }

    func testFileInfo() throws {
        let data = Data("test data".utf8)
        try fm.writeFile(agentId: testAgentId, name: "info.txt", data: data)

        let info = fm.fileInfo(agentId: testAgentId, name: "info.txt")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "info.txt")
        XCTAssertEqual(info?.size, Int64(data.count))
        XCTAssertFalse(info?.isImage ?? true)
    }

    func testImageFileDetection() throws {
        try fm.writeFile(agentId: testAgentId, name: "photo.jpg", data: Data([0xFF, 0xD8, 0xFF]))
        let info = fm.fileInfo(agentId: testAgentId, name: "photo.jpg")
        XCTAssertTrue(info?.isImage ?? false)
    }

    func testReadNonExistentFile() {
        XCTAssertThrowsError(try fm.readFile(agentId: testAgentId, name: "nope.txt")) { error in
            XCTAssertTrue(error is FileToolError)
        }
    }

    func testDeleteNonExistentFile() {
        XCTAssertThrowsError(try fm.deleteFile(agentId: testAgentId, name: "nope.txt")) { error in
            XCTAssertTrue(error is FileToolError)
        }
    }

    // MARK: - Path Traversal Protection

    func testUnsafeFilenameRejected() {
        XCTAssertFalse(AgentFileManager.isSafeFilename("../etc/passwd"))
        XCTAssertFalse(AgentFileManager.isSafeFilename(".."))
        XCTAssertFalse(AgentFileManager.isSafeFilename("."))
        XCTAssertFalse(AgentFileManager.isSafeFilename("foo/bar"))
        XCTAssertFalse(AgentFileManager.isSafeFilename(""))
        XCTAssertFalse(AgentFileManager.isSafeFilename("a\0b"))

        XCTAssertThrowsError(try fm.writeFile(agentId: testAgentId, name: "../escape.txt", data: Data())) { error in
            if case FileToolError.unsafeFilename = error {} else {
                XCTFail("Expected unsafeFilename error")
            }
        }
    }

    func testSafeFilenames() {
        XCTAssertTrue(AgentFileManager.isSafeFilename("hello.txt"))
        XCTAssertTrue(AgentFileManager.isSafeFilename("data (1).json"))
        XCTAssertTrue(AgentFileManager.isSafeFilename("图片.png"))
        XCTAssertTrue(AgentFileManager.isSafeFilename("file-name_v2.tar.gz"))
    }

    // MARK: - File Reference

    func testMakeAndParseFileReference() {
        let agentId = UUID()
        let ref = AgentFileManager.makeFileReference(agentId: agentId, filename: "test.png")
        XCTAssertTrue(ref.hasPrefix("agentfile://"))

        let parsed = AgentFileManager.parseFileReference(ref)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.0, agentId)
        XCTAssertEqual(parsed?.1, "test.png")
    }

    func testParseInvalidReference() {
        XCTAssertNil(AgentFileManager.parseFileReference("https://example.com"))
        XCTAssertNil(AgentFileManager.parseFileReference("agentfile://"))
        XCTAssertNil(AgentFileManager.parseFileReference("agentfile://not-a-uuid/file.txt"))
        XCTAssertNil(AgentFileManager.parseFileReference("agentfile://\(UUID().uuidString)/"))
        XCTAssertNil(AgentFileManager.parseFileReference("agentfile://\(UUID().uuidString)/../etc"))
    }

    // MARK: - Image Save and Load

    func testSaveAndLoadImage() {
        let imageData = Data(repeating: 0xFF, count: 100)
        guard let ref = fm.saveImage(imageData, mimeType: "image/png", agentId: testAgentId) else {
            XCTFail("saveImage returned nil"); return
        }

        XCTAssertTrue(ref.hasPrefix("agentfile://"))

        let loaded = fm.loadImageData(from: ref)
        XCTAssertEqual(loaded, imageData)
    }

    func testLoadImageFromMissingRef() {
        let fakeRef = AgentFileManager.makeFileReference(agentId: testAgentId, filename: "nonexistent.png")
        XCTAssertNil(fm.loadImageData(from: fakeRef))
    }

    // MARK: - Cleanup

    func testCleanupAgentFiles() throws {
        try fm.writeFile(agentId: testAgentId, name: "a.txt", data: Data("a".utf8))
        try fm.writeFile(agentId: testAgentId, name: "b.txt", data: Data("b".utf8))
        XCTAssertEqual(fm.listFiles(agentId: testAgentId).count, 2)

        fm.cleanupAgentFiles(agentId: testAgentId)
        XCTAssertTrue(fm.listFiles(agentId: testAgentId).isEmpty)
    }

    func testCleanupOrphanDirectories() throws {
        let orphanId = UUID()
        try fm.writeFile(agentId: orphanId, name: "orphan.txt", data: Data("x".utf8))
        try fm.writeFile(agentId: testAgentId, name: "keep.txt", data: Data("x".utf8))

        fm.cleanupOrphanDirectories(knownAgentIds: [testAgentId])

        XCTAssertTrue(fm.listFiles(agentId: orphanId).isEmpty)
        XCTAssertFalse(fm.listFiles(agentId: testAgentId).isEmpty)
    }

    // MARK: - Overwrite

    func testOverwriteExistingFile() throws {
        try fm.writeFile(agentId: testAgentId, name: "data.txt", data: Data("v1".utf8))
        try fm.writeFile(agentId: testAgentId, name: "data.txt", data: Data("v2".utf8))

        let read = try fm.readFile(agentId: testAgentId, name: "data.txt")
        XCTAssertEqual(String(data: read, encoding: .utf8), "v2")
        XCTAssertEqual(fm.listFiles(agentId: testAgentId).count, 1)
    }

    // MARK: - resolveAgentId

    @MainActor
    func testResolveAgentIdForMainAgent() {
        let agent = Agent(name: "Main")
        XCTAssertEqual(fm.resolveAgentId(for: agent), agent.id)
    }

    @MainActor
    func testResolveAgentIdForSubAgent() {
        let parent = Agent(name: "Parent")
        let child = Agent(name: "Child")
        parent.subAgents.append(child)
        XCTAssertEqual(fm.resolveAgentId(for: child), parent.id)
    }

    @MainActor
    func testResolveAgentIdForDeepNesting() {
        let root = Agent(name: "Root")
        let mid = Agent(name: "Mid")
        let leaf = Agent(name: "Leaf")
        root.subAgents.append(mid)
        mid.subAgents.append(leaf)
        XCTAssertEqual(fm.resolveAgentId(for: leaf), root.id)
    }
}
