import Foundation
import XCTest
@testable import AEMotionExtensionsCore

private final class SendableIntBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

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

    func testCoalescerDeliversOnlyLatestPendingValueAndFinalFlush() async {
        let coalescer = PreviewUpdateCoalescer<Int>()
        let delivered = SendableIntBuffer()
        await coalescer.enqueue(1)
        await coalescer.enqueue(2)
        await coalescer.flush { delivered.append($0) }
        XCTAssertEqual(delivered.snapshot(), [2])
        await coalescer.enqueue(3)
        await coalescer.finish { delivered.append($0) }
        XCTAssertEqual(delivered.snapshot(), [2, 3])
    }

    func testOtherEligibilityRequiresPassingDeviceRecordForExactHash() {
        let record = DeviceQualificationRecord(
            effectID: "com.example.glow",
            descriptorSHA256: String(repeating: "a", count: 64),
            hostVersion: "6.2.42",
            deviceClass: "iPhone",
            stage: .device,
            disposition: .passed,
            metrics: .init(
                topBlackRatio: 0,
                bottomBlackRatio: 0,
                leftBlackRatio: 0,
                rightBlackRatio: 0,
                transparentRatio: 0.1,
                alphaLossRatio: 0
            )
        )
        XCTAssertTrue(EffectQualificationPolicy.isEligibleForOther(
            effectID: "com.example.glow",
            descriptorSHA256: String(repeating: "a", count: 64),
            records: [record]
        ))
        XCTAssertFalse(EffectQualificationPolicy.isEligibleForOther(
            effectID: "com.example.glow",
            descriptorSHA256: String(repeating: "b", count: 64),
            records: [record]
        ))
    }

    func testFailedOrRequiredRecordCannotEnterOther() {
        let hash = String(repeating: "c", count: 64)
        let dispositions: [EffectQualificationDisposition] = [
            .failed, .deviceQualificationRequired, .timeout, .crashed,
        ]
        for disposition in dispositions {
            let record = DeviceQualificationRecord(
                effectID: "com.example.fx",
                descriptorSHA256: hash,
                hostVersion: "6.2.42",
                deviceClass: "iPad",
                stage: .device,
                disposition: disposition,
                metrics: .zero
            )
            XCTAssertFalse(EffectQualificationPolicy.isEligibleForOther(
                effectID: "com.example.fx",
                descriptorSHA256: hash,
                records: [record]
            ))
        }
    }
}
