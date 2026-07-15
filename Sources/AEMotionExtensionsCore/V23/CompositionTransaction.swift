import Foundation

public enum CompositionTransactionState: String, Codable, Equatable, Sendable {
    case idle
    case active
    case committed
    case cancelled
}

public enum CompositionTransactionError: Error, Equatable, Sendable {
    case alreadyStarted
    case notActive
    case invalidGraph(CompositionGraphValidationError)
}

public final class CompositionTransaction {
    public private(set) var state: CompositionTransactionState = .idle
    public let original: CompositionDocument
    public private(set) var provisional: CompositionDocument
    private let apply: (CompositionDocument) -> Void

    public init(original: CompositionDocument, apply: @escaping (CompositionDocument) -> Void) {
        self.original = original
        self.provisional = original
        self.apply = apply
    }

    public func begin() throws {
        guard state == .idle else { throw CompositionTransactionError.alreadyStarted }
        state = .active
    }

    public func update(_ document: CompositionDocument) throws {
        guard state == .active else { throw CompositionTransactionError.notActive }
        if let first = CompositionGraphValidator.validate(document).first {
            throw CompositionTransactionError.invalidGraph(first)
        }
        provisional = document
        apply(document)
    }

    public func commit() throws -> CompositionDocument {
        guard state == .active else { throw CompositionTransactionError.notActive }
        state = .committed
        return provisional
    }

    @discardableResult
    public func cancel() throws -> CompositionDocument {
        guard state == .active else { throw CompositionTransactionError.notActive }
        provisional = original
        apply(original)
        state = .cancelled
        return original
    }

    public func selectionDidChange() throws {
        if state == .active { _ = try cancel() }
    }

    public func applicationDidEnterBackground() throws {
        if state == .active { _ = try cancel() }
    }
}

public actor CompositionPreviewCoalescer {
    private var pending: CompositionDocument?

    public init() {}

    public func enqueue(_ document: CompositionDocument) {
        pending = document
    }

    public func takePending() -> CompositionDocument? {
        defer { pending = nil }
        return pending
    }

    public func flush(_ apply: @Sendable (CompositionDocument) -> Void) {
        guard let document = takePending() else { return }
        apply(document)
    }

    public func cancel() {
        pending = nil
    }
}
