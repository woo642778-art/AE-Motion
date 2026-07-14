import XCTest
@testable import AEMotionExtensionsCore

final class ContextualEditingTests: XCTestCase {
    func testPreviewTransactionCommitKeepsLatestValue() throws {
        var applied: [Double] = []
        let transaction = PreviewTransaction(initialValue: 1.0) { applied.append($0) }
        try transaction.begin()
        try transaction.update(1.5)
        try transaction.update(2.0)
        try transaction.commit()
        XCTAssertEqual(transaction.state, .committed)
        XCTAssertEqual(transaction.currentValue, 2.0)
        XCTAssertEqual(applied, [1.5, 2.0])
    }

    func testPreviewTransactionCancelRestoresInitialValue() throws {
        var applied: [Double] = []
        let transaction = PreviewTransaction(initialValue: 1.0) { applied.append($0) }
        try transaction.begin()
        try transaction.update(3.0)
        try transaction.cancel()
        XCTAssertEqual(transaction.state, .cancelled)
        XCTAssertEqual(transaction.currentValue, 1.0)
        XCTAssertEqual(applied, [3.0, 1.0])
    }

    func testSelectionChangeCancelsActiveTransaction() throws {
        var applied: [Float] = []
        let transaction = PreviewTransaction(initialValue: 0.25 as Float) { applied.append($0) }
        try transaction.begin()
        try transaction.update(0.75)
        try transaction.selectionDidChange()
        XCTAssertEqual(transaction.state, .cancelled)
        XCTAssertEqual(applied.last, 0.25)
    }
}
