import XCTest
@testable import AEMotionExtensionsCore

final class ProjectReliabilityTests: XCTestCase {
    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AEMotionTests-\(name)")
        try? FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }

    func testProjectDocumentRoundTripAndValidation() throws {
        let media = MediaReference(originalURL: "/tmp/source.mov")
        let clip = ProjectClip(mediaID: media.id, sourceDuration: 3)
        let effect = ProjectEffect(descriptorID: "com.aemotion.effect", name: "Effect")
        let layer = ProjectLayer(name: "Layer", duration: 3, clips: [clip], effects: [effect])
        let track = ProjectTrack(name: "Video", kind: .video, layers: [layer])
        let sequence = ProjectSequence(name: "Main", duration: 3, tracks: [track])
        let project = ProjectDocument(name: "Test", sequences: [sequence], media: [media])
        try ProjectValidator.validate(project)
        let data = try ProjectStore.encoder().encode(project)
        XCTAssertEqual(try ProjectStore.decoder().decode(ProjectDocument.self, from: data), project)
    }

    func testMigratesSchemaZeroDefaults() throws {
        let id = UUID(), now = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
        let raw = "{\"id\":\"\(id.uuidString)\",\"name\":\"Legacy\",\"createdAt\":\"\(now)\",\"modifiedAt\":\"\(now)\"}".data(using: .utf8)!
        let migrated = try ProjectSchemaMigrator.migrate(raw)
        let project = try ProjectStore.decoder().decode(ProjectDocument.self, from: migrated)
        XCTAssertEqual(project.schemaVersion, 1); XCTAssertEqual(project.lastAppliedCommandSequence, 0); XCTAssertTrue(project.metadata.isEmpty)
    }

    func testProjectStoreRejectsChecksumMismatch() async throws {
        let root = try temporaryDirectory(); let store = ProjectStore(rootURL: root)
        let project = ProjectDocument.empty(name: "Checksum")
        try await store.save(project)
        try Data("corrupt".utf8).write(to: await store.projectURL(for: project.id), options: .atomic)
        do { _ = try await store.load(project.id); XCTFail("Expected checksum mismatch") }
        catch let error as ProjectStoreError { XCTAssertEqual(error, .checksumMismatch) }
    }

    func testCommittedJournalReplaysAfterSimulatedCrash() async throws {
        let root = try temporaryDirectory(); let store = ProjectStore(rootURL: root.appendingPathComponent("Projects")); let journal = ProjectJournal(rootURL: root.appendingPathComponent("Journals")); let history = ProjectHistoryStore(rootURL: root.appendingPathComponent("History"))
        let project = ProjectDocument.empty(name: "Before"); try await store.save(project)
        let command = ProjectCommand(sequence: 1, mutation: .renameProject("After"), label: "Rename")
        try await journal.append(.init(phase: .prepared, command: command), projectID: project.id)
        try await journal.append(.init(phase: .committed, command: command), projectID: project.id)
        let session = ProjectSession(store: store, journal: journal, history: history)
        let recovered = try await session.open(project.id)
        XCTAssertEqual(recovered.name, "After"); XCTAssertEqual(recovered.lastAppliedCommandSequence, 1)
    }

    func testUndoRedoAndBranch() async throws {
        let root = try temporaryDirectory(); let store = ProjectStore(rootURL: root.appendingPathComponent("Projects")); let journal = ProjectJournal(rootURL: root.appendingPathComponent("Journals")); let history = ProjectHistoryStore(rootURL: root.appendingPathComponent("History"))
        let session = ProjectSession(store: store, journal: journal, history: history); let project = ProjectDocument.empty(name: "A")
        try await session.create(project); _ = try await session.perform(.renameProject("B"), label: "Rename")
        let undone = try await session.undo(); XCTAssertEqual(undone?.name, "A")
        let redone = try await session.redo(); XCTAssertEqual(redone?.name, "B")
        let branch = try await session.branch(name: "Branch"); XCTAssertNotEqual(branch.id, project.id); XCTAssertEqual(branch.metadata["parentProjectID"], project.id.uuidString)
    }

    func testHistoryRecoveryPointsPreserveBookmarks() async throws {
        let root = try temporaryDirectory(); let history = ProjectHistoryStore(rootURL: root, maximumSnapshots: 3)
        let project = ProjectDocument.empty(name: "P"); let now = Date()
        let bookmarked = ProjectSnapshot(projectID: project.id, createdAt: now.addingTimeInterval(-1200), label: "Bookmark", commandSequence: 0, isBookmark: true, document: project)
        try await history.save(bookmarked)
        for index in 1...5 { try await history.save(ProjectSnapshot(projectID: project.id, createdAt: now.addingTimeInterval(Double(-index * 60)), label: "S\(index)", commandSequence: UInt64(index), document: project)) }
        let values = try await history.list(projectID: project.id); XCTAssertTrue(values.contains { $0.id == bookmarked.id })
        let points = try await history.recoveryPoints(projectID: project.id, now: now); XCTAssertTrue(points.contains { $0.id == bookmarked.id })
    }

    func testProxyPolicyRespondsToThermalAndResolution() {
        XCTAssertEqual(ProxyPolicy.recommendedScale(width: 3840, height: 2160, mode: .balanced, thermal: .nominal), .quarter)
        XCTAssertEqual(ProxyPolicy.recommendedScale(width: 1920, height: 1080, mode: .maximumQuality, thermal: .nominal), .full)
        XCTAssertEqual(ProxyPolicy.recommendedScale(width: 1920, height: 1080, mode: .maximumQuality, thermal: .critical), .eighth)
    }

    func testCacheDetectsCorruptionAndEvictsLRU() async throws {
        let root = try temporaryDirectory(); let cache = ProjectCacheStore(rootURL: root, budgetBytes: 5)
        let first = root.appendingPathComponent("first.bin"), second = root.appendingPathComponent("second.bin")
        try Data([1,2,3]).write(to: first); try Data([4,5,6]).write(to: second)
        _ = try await cache.registerFile(at: first, kind: .proxy); _ = try await cache.registerFile(at: second, kind: .proxy)
        let summary = try await cache.summary(); XCTAssertLessThanOrEqual(summary.totalBytes, 5)
        let remaining = try await cache.allEntries().first!; try Data([9]).write(to: root.appendingPathComponent(remaining.relativePath))
        let corrupt = try await cache.validate(); XCTAssertEqual(corrupt, [remaining.id])
    }

    func testProjectDoctorRepairsMissingMediaAndUnsupportedEffect() throws {
        let media = MediaReference(originalURL: "/definitely/missing.mov")
        let effect = ProjectEffect(descriptorID: "missing.effect", name: "Missing")
        let layer = ProjectLayer(name: "Layer", duration: 1, effects: [effect])
        let project = ProjectDocument(name: "Doctor", sequences: [.init(name: "Main", duration: 1, tracks: [.init(name: "V", kind: .video, layers: [layer])])], media: [media])
        let report = ProjectDoctor.inspect(project, availableEffectIDs: ["available.effect"])
        XCTAssertTrue(report.findings.contains { $0.code == .missingMedia }); XCTAssertTrue(report.findings.contains { $0.code == .unsupportedEffect })
        let repaired = ProjectDoctor.repairedCopy(project, report: report)
        XCTAssertEqual(repaired.media[0].availability, .offline); XCTAssertFalse(repaired.sequences[0].tracks[0].layers[0].effects[0].isEnabled)
    }

    func testRecoverySelfTest() async throws { let passed = try await ProjectRecoverySelfTest.run(in: temporaryDirectory()); XCTAssertTrue(passed) }
}
