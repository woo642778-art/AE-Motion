#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class LivePreviewCoordinator: NSObject {
    private weak var adapter: HostControlMutationAdapter?
    private var transaction: PreviewTransaction<[Float]>?
    private var displayLink: CADisplayLink?
    private let coalescer = PreviewUpdateCoalescer<[Float]>()

    var isActive: Bool { transaction?.state == .active }

    func begin(adapter: HostControlMutationAdapter) throws {
        if isActive { cancel() }
        self.adapter = adapter
        let transaction = PreviewTransaction(initialValue: adapter.snapshot()) { [weak adapter] values in
            _ = adapter?.apply(values)
        }
        try transaction.begin()
        self.transaction = transaction
        let link = CADisplayLink(target: self, selector: #selector(flushPending))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func update(_ values: [Float]) {
        guard isActive else { return }
        Task { await coalescer.enqueue(values) }
    }

    @objc private func flushPending() {
        Task { @MainActor [weak self] in
            guard let self, let values = await self.coalescer.takePending() else { return }
            try? self.transaction?.update(values)
            self.adapter?.invalidatePreview()
        }
    }

    func commit() {
        guard isActive else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let values = await self.coalescer.takePending() {
                try? self.transaction?.update(values)
            }
            try? self.transaction?.commit()
            self.finish()
        }
    }

    func cancel() {
        guard isActive else { finish(); return }
        try? transaction?.cancel()
        adapter?.invalidatePreview()
        finish()
    }

    func selectionDidChange(to identity: ObjectIdentifier) {
        guard adapter?.selectionIdentity != identity else { return }
        try? transaction?.selectionDidChange()
        adapter?.invalidatePreview()
        finish()
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        transaction = nil
        adapter = nil
    }
}
#endif
