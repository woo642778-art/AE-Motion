import Foundation

final class ExtensionDiagnosticsLog: @unchecked Sendable {
    private let lock = NSLock()
    private let component: String
    private var entries: [String] = []

    init(component: String) {
        self.component = component
    }

    func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        lock.lock()
        entries.append("[\(timestamp)] \(message)")
        if entries.count > 300 {
            entries.removeFirst(entries.count - 300)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return (["AE Motion Extensions Diagnostics", "Component: \(component)", ""] + snapshot)
            .joined(separator: "\n")
    }
}
