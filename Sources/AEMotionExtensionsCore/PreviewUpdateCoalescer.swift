import Foundation

public actor PreviewUpdateCoalescer<Value: Sendable> {
    private var pending: Value?

    public init() {}

    public func enqueue(_ value: Value) {
        pending = value
    }

    public func takePending() -> Value? {
        defer { pending = nil }
        return pending
    }

    public func flush(_ deliver: @Sendable (Value) -> Void) {
        guard let value = pending else { return }
        pending = nil
        deliver(value)
    }

    public func finish(_ deliver: @Sendable (Value) -> Void) {
        flush(deliver)
    }
}
