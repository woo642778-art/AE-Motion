#if canImport(UIKit)
import Foundation
import UIKit
import AEMotionExtensionsCore

@MainActor
final class CompositionLivePreviewCoordinator: NSObject {
    private weak var adapter: CompositionHostMutationAdapter?
    private var transaction: CompositionTransaction?
    private var displayLink: CADisplayLink?
    private var pendingDocument: CompositionDocument?
    private weak var temporaryOverlay: UIView?
    private var isFinishing = false

    var isActive: Bool { transaction?.state == .active }
    var currentDocument: CompositionDocument? { transaction?.currentDocument }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
    }

    func begin(session: CompositionHostSession) throws {
        if isActive { cancel(reason: .hostContractInvalidated) }
        guard session.adapter.verifiedCapabilities.contains(.previewComposition),
              let snapshot = session.adapter.snapshot(),
              snapshot.hasStableSelection,
              let document = session.adapter.readCompositionDocument() else {
            throw CompositionTransactionError.invalidDocument
        }

        let transaction = CompositionTransaction(
            initialDocument: document,
            selectionIdentity: snapshot.selectionIdentity
        )
        try transaction.begin()
        adapter = session.adapter
        self.transaction = transaction
        attachTemporaryOverlay(to: session.viewerView)
        startDisplayLink()
    }

    func update(_ document: CompositionDocument) {
        guard isActive else { return }
        pendingDocument = document
    }

    func commit(label: String, affectedCompositionID: UUID) async -> Bool {
        guard isActive, let transaction, let adapter else { return false }
        displayLink?.invalidate()
        displayLink = nil

        if let pending = takePendingDocument(), !applyPreview(pending) {
            cancel(reason: .previewFailed)
            return false
        }

        let intent: CompositionCommandIntent
        do {
            intent = try transaction.commit(label: label, affectedCompositionID: affectedCompositionID)
        } catch {
            cancel(reason: .hostContractInvalidated)
            return false
        }

        guard adapter.commit(intent: intent), adapter.verifyPostcondition(for: intent) else {
            _ = adapter.rollback()
            try? transaction.restoreAfterFailedCommit(reason: .commitPostconditionFailed)
            finish()
            return false
        }

        adapter.invalidatePreview()
        finish()
        return true
    }

    func cancel(reason: CompositionRollbackReason = .userCancelled) {
        guard !isFinishing else { return }
        pendingDocument = nil
        if transaction?.state == .active {
            try? transaction?.cancel(reason: reason)
        } else if transaction?.state == .committed,
                  reason == .hostContractInvalidated || reason == .commitPostconditionFailed {
            try? transaction?.restoreAfterFailedCommit(reason: reason)
        }
        _ = adapter?.rollback()
        adapter?.invalidatePreview()
        finish()
    }

    func selectionDidChange(to identity: String) {
        guard let transaction, identity != transaction.selectionIdentity else { return }
        try? transaction.selectionDidChange(to: identity)
        _ = adapter?.rollback()
        finish()
    }

    func refreshSelectionFromHost() {
        guard let identity = adapter?.snapshot()?.selectionIdentity else {
            cancel(reason: .hostContractInvalidated)
            return
        }
        selectionDidChange(to: identity)
    }

    func hostContractDidInvalidate() {
        cancel(reason: .hostContractInvalidated)
    }

    @objc private func flushPending() {
        guard isActive, let pending = takePendingDocument() else { return }
        if !applyPreview(pending) {
            cancel(reason: .previewFailed)
        }
    }

    @objc private func applicationDidEnterBackground() {
        cancel(reason: .appBackgrounded)
    }

    private func applyPreview(_ document: CompositionDocument) -> Bool {
        guard let transaction, let adapter else { return false }
        do {
            try transaction.replaceCurrentDocument(with: document)
        } catch {
            return false
        }
        guard adapter.preview(document: document) else { return false }
        adapter.invalidatePreview()
        return true
    }

    private func takePendingDocument() -> CompositionDocument? {
        defer { pendingDocument = nil }
        return pendingDocument
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(flushPending))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func attachTemporaryOverlay(to viewer: UIView) {
        temporaryOverlay?.removeFromSuperview()
        let overlay = UIView(frame: viewer.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.accessibilityIdentifier = "aemotion.composition.preview-transaction"
        viewer.addSubview(overlay)
        temporaryOverlay = overlay
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        displayLink?.invalidate()
        displayLink = nil
        pendingDocument = nil
        temporaryOverlay?.removeFromSuperview()
        temporaryOverlay = nil
        transaction = nil
        adapter = nil
        isFinishing = false
    }
}
#endif
