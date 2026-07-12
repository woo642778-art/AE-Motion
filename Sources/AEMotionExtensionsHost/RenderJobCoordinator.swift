#if canImport(UIKit)
import Foundation
import UIKit

final class RenderCancellationToken: @unchecked Sendable {
    enum Reason: String, Sendable {
        case user
        case memoryPressure
    }

    private let lock = NSLock()
    private var storedReason: Reason?

    var reason: Reason? {
        lock.lock()
        defer { lock.unlock() }
        return storedReason
    }

    var isCancelled: Bool { reason != nil }

    func cancel(reason: Reason = .user) {
        lock.lock()
        if storedReason == nil { storedReason = reason }
        lock.unlock()
    }

    func checkCancellation() throws {
        guard let reason else { return }
        switch reason {
        case .user:
            throw RenderJobError.cancelled
        case .memoryPressure:
            throw RenderJobError.memoryPressure
        }
    }
}

enum RenderJobError: Error, LocalizedError, Sendable {
    case alreadyRunning
    case cancelled
    case memoryPressure
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Another render is already running. Cancel it or wait for it to finish."
        case .cancelled:
            return "The render was cancelled."
        case .memoryPressure:
            return "The render was stopped because iOS reported memory pressure. Try a shorter clip or lower-resolution source."
        case .failed(let message):
            return message
        }
    }
}

enum RenderTemporaryFiles {
    private static let prefix = "AE-Motion-"
    private static let staleAge: TimeInterval = 24 * 60 * 60

    static func makeURL(label: String, pathExtension: String = "mov") -> URL {
        let safeLabel = label.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(safeLabel)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanupStaleFiles(now: Date = Date()) {
        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= staleAge {
                remove(url)
            }
        }
    }
}

@MainActor
final class RenderJobCoordinator: NSObject {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias Operation = @Sendable (RenderCancellationToken, @escaping ProgressHandler) throws -> Void
    typealias Completion = @MainActor (Result<Void, RenderJobError>) -> Void

    private weak var owner: UIViewController?
    private weak var progressView: UIProgressView?
    private weak var statusLabel: UILabel?
    private weak var cancelButton: UIButton?
    private var activeTask: Task<Void, Never>?
    private var activeToken: RenderCancellationToken?
    private var activeControls: [UIControl] = []
    private var activeOutputURL: URL?
    private var memoryWarningRequested = false

    init(owner: UIViewController, progressView: UIProgressView, statusLabel: UILabel) {
        self.owner = owner
        self.progressView = progressView
        self.statusLabel = statusLabel
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(memoryWarningReceived),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    var isRunning: Bool { activeTask != nil }

    func start(
        name: String,
        outputURL: URL,
        controls: [UIControl],
        cancelButton: UIButton,
        initialStatus: String,
        operation: @escaping Operation,
        completion: @escaping Completion
    ) {
        guard activeTask == nil else {
            statusLabel?.text = RenderJobError.alreadyRunning.localizedDescription
            if let owner {
                ExtensionUI.alert(
                    title: "Render already running",
                    message: RenderJobError.alreadyRunning.localizedDescription,
                    from: owner
                )
            }
            return
        }

        let token = RenderCancellationToken()
        activeToken = token
        activeControls = controls
        activeOutputURL = outputURL
        self.cancelButton = cancelButton
        memoryWarningRequested = false

        controls.forEach { $0.isEnabled = false }
        cancelButton.isEnabled = true
        progressView?.progress = 0
        statusLabel?.text = initialStatus

        let progress: ProgressHandler = { [weak self] value in
            Task { @MainActor in
                guard let self, self.activeToken === token else { return }
                self.progressView?.progress = Float(min(1, max(0, value)))
            }
        }

        activeTask = Task { @MainActor [weak self] in
            let result: Result<Void, RenderJobError> = await Task.detached(priority: .userInitiated) {
                do {
                    try token.checkCancellation()
                    try operation(token, progress)
                    try token.checkCancellation()
                    return .success(())
                } catch let error as RenderJobError {
                    return .failure(error)
                } catch {
                    return .failure(.failed(error.localizedDescription))
                }
            }.value

            guard let self, self.activeToken === token else { return }
            self.finish(result: result, name: name, completion: completion)
        }
    }

    func cancel() {
        guard let token = activeToken else { return }
        token.cancel(reason: .user)
        statusLabel?.text = "Cancelling render…"
        cancelButton?.isEnabled = false
    }

    func outputWasConsumed(_ url: URL) {
        guard activeOutputURL == url || url.lastPathComponent.hasPrefix("AE-Motion-") else { return }
        RenderTemporaryFiles.remove(url)
        if activeOutputURL == url { activeOutputURL = nil }
    }

    @objc private func memoryWarningReceived() {
        guard let token = activeToken else { return }
        memoryWarningRequested = true
        token.cancel(reason: .memoryPressure)
        statusLabel?.text = "Stopping render because iOS reported memory pressure…"
        cancelButton?.isEnabled = false
    }

    private func finish(
        result: Result<Void, RenderJobError>,
        name: String,
        completion: Completion
    ) {
        activeTask = nil
        activeToken = nil
        activeControls.forEach { $0.isEnabled = true }
        activeControls.removeAll()
        cancelButton?.isEnabled = false

        switch result {
        case .success:
            progressView?.progress = 1
        case .failure:
            if let output = activeOutputURL {
                RenderTemporaryFiles.remove(output)
            }
            activeOutputURL = nil
        }

        if memoryWarningRequested, case .failure(.cancelled) = result {
            completion(.failure(.memoryPressure))
        } else {
            completion(result)
        }
    }
}
#endif
