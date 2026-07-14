import Foundation

public enum ContextualEditingContext: String, Codable, CaseIterable, Sendable {
    case transform
    case graph
    case speed
    case effect
}

public struct ContextualToolDescriptor: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let context: ContextualEditingContext
    public let systemImage: String

    public init(id: String, title: String, context: ContextualEditingContext, systemImage: String) {
        self.id = id
        self.title = title
        self.context = context
        self.systemImage = systemImage
    }
}

public enum PreviewTransactionState: String, Codable, Equatable, Sendable {
    case idle
    case active
    case committed
    case cancelled
}

public enum PreviewTransactionError: Error, Equatable {
    case alreadyStarted
    case notActive
}

public final class PreviewTransaction<Value: Equatable> {
    public private(set) var state: PreviewTransactionState = .idle
    public private(set) var currentValue: Value
    public let initialValue: Value
    private let apply: (Value) -> Void

    public init(initialValue: Value, apply: @escaping (Value) -> Void) {
        self.initialValue = initialValue
        self.currentValue = initialValue
        self.apply = apply
    }

    public func begin() throws {
        guard state == .idle else { throw PreviewTransactionError.alreadyStarted }
        state = .active
    }

    public func update(_ value: Value) throws {
        guard state == .active else { throw PreviewTransactionError.notActive }
        currentValue = value
        apply(value)
    }

    public func commit() throws {
        guard state == .active else { throw PreviewTransactionError.notActive }
        state = .committed
    }

    public func cancel() throws {
        guard state == .active else { throw PreviewTransactionError.notActive }
        currentValue = initialValue
        apply(initialValue)
        state = .cancelled
    }

    public func selectionDidChange() throws {
        if state == .active {
            try cancel()
        }
    }
}
