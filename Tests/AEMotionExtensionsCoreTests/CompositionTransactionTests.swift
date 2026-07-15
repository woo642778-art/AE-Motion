import XCTest
@testable import AEMotionExtensionsCore

final class CompositionTransactionTests: XCTestCase {
    func testCancelRestoresInitialGraphExactly() throws {
        let (initial, rootID) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "root:selection:1")
        try transaction.begin()
        try transaction.update { document in
            document.compositions[0].name = "Changed"
        }
        try transaction.cancel(reason: .userCancelled)

        XCTAssertEqual(transaction.currentDocument, initial)
        XCTAssertEqual(transaction.state, .cancelled)
        XCTAssertEqual(transaction.rollbackReason, .userCancelled)
        XCTAssertEqual(transaction.affectedCompositionID, rootID)
    }

    func testSelectionChangeCancelsActiveTransaction() throws {
        let (initial, _) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "one")
        try transaction.begin()
        try transaction.selectionDidChange(to: "two")

        XCTAssertEqual(transaction.state, .cancelled)
        XCTAssertEqual(transaction.rollbackReason, .selectionChanged)
        XCTAssertEqual(transaction.currentDocument, initial)
    }

    func testInvalidUpdateDoesNotReplaceCurrentDocument() throws {
        let (initial, _) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "one")
        try transaction.begin()

        XCTAssertThrowsError(try transaction.update { document in
            document.rootCompositionID = UUID()
        }) {
            XCTAssertEqual($0 as? CompositionTransactionError, .invalidDocument)
        }
        XCTAssertEqual(transaction.currentDocument, initial)
        XCTAssertEqual(transaction.state, .active)
    }

    func testCommitIsIdempotentAndProducesAtomicBeforeAfterIntent() throws {
        let (initial, rootID) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "one")
        try transaction.begin()
        try transaction.update { document in
            document.compositions[0].name = "Changed"
        }

        let first = try transaction.commit(label: "Rename", affectedCompositionID: rootID)
        let second = try transaction.commit(label: "Rename", affectedCompositionID: rootID)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.initialDocument, initial)
        XCTAssertEqual(first.finalDocument.compositions[0].name, "Changed")
        XCTAssertEqual(transaction.state, .committed)
    }

    func testBackgroundCancellationIsIdempotent() throws {
        let (initial, _) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "one")
        try transaction.begin()
        try transaction.cancel(reason: .appBackgrounded)
        try transaction.cancel(reason: .appBackgrounded)
        XCTAssertEqual(transaction.rollbackReason, .appBackgrounded)
        XCTAssertEqual(transaction.currentDocument, initial)
    }

    func testCommittedTransactionCannotBeCancelledOrUpdated() throws {
        let (initial, rootID) = makeDocument()
        let transaction = CompositionTransaction(initialDocument: initial, selectionIdentity: "one")
        try transaction.begin()
        _ = try transaction.commit(label: "Commit", affectedCompositionID: rootID)

        XCTAssertThrowsError(try transaction.cancel(reason: .userCancelled)) {
            XCTAssertEqual($0 as? CompositionTransactionError, .alreadyCommitted)
        }
        XCTAssertThrowsError(try transaction.update { _ in }) {
            XCTAssertEqual($0 as? CompositionTransactionError, .notActive)
        }
    }

    private func makeDocument() -> (CompositionDocument, UUID) {
        let root = Composition(name: "Root", duration: 5)
        return (CompositionDocument(rootCompositionID: root.id, compositions: [root]), root.id)
    }
}
