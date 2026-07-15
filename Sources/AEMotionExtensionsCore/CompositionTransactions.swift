import Foundation

public enum CompositionTransactionState: String, Codable, Equatable, Sendable {
    case idle
    case active
    case committed
    case cancelled
}

public enum CompositionRollbackReason: String, Codable, Equatable, Sendable {
    case userCancelled
    case selectionChanged
    case hostContractInvalidated
    case appBackgrounded
    case previewFailed
    case commitPostconditionFailed
}

public enum CompositionTransactionError: Error, Equatable {
    case alreadyStarted
    case notActive
    case invalidDocument
    case alreadyCommitted
    case commitIdentityMismatch
}

public struct CompositionCommandIntent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var affectedCompositionID: UUID
    public var initialDocument: CompositionDocument
    public var finalDocument: CompositionDocument

    public init(
        id: UUID = UUID(),
        label: String,
        affectedCompositionID: UUID,
        initialDocument: CompositionDocument,
        finalDocument: CompositionDocument
    ) {
        self.id = id
        self.label = label
        self.affectedCompositionID = affectedCompositionID
        self.initialDocument = initialDocument
        self.finalDocument = finalDocument
    }
}

public final class CompositionTransaction {
    public private(set) var state: CompositionTransactionState = .idle
    public private(set) var currentDocument: CompositionDocument
    public let initialDocument: CompositionDocument
    public let selectionIdentity: String
    public private(set) var rollbackReason: CompositionRollbackReason?
    public private(set) var affectedCompositionID: UUID

    private var committedIntent: CompositionCommandIntent?

    public init(initialDocument: CompositionDocument, selectionIdentity: String) {
        self.initialDocument = initialDocument
        self.currentDocument = initialDocument
        self.selectionIdentity = selectionIdentity
        self.affectedCompositionID = initialDocument.rootCompositionID
    }

    public func begin() throws {
        guard state == .idle else { throw CompositionTransactionError.alreadyStarted }
        try validate(initialDocument)
        state = .active
    }

    public func update(_ mutation: (inout CompositionDocument) throws -> Void) throws {
        guard state == .active else { throw CompositionTransactionError.notActive }
        var candidate = currentDocument
        try mutation(&candidate)
        try validate(candidate)
        currentDocument = candidate
    }

    public func replaceCurrentDocument(with candidate: CompositionDocument) throws {
        try update { document in document = candidate }
    }

    public func commit(label: String, affectedCompositionID: UUID) throws -> CompositionCommandIntent {
        if state == .committed {
            guard let committedIntent,
                  committedIntent.label == label,
                  committedIntent.affectedCompositionID == affectedCompositionID else {
                throw CompositionTransactionError.commitIdentityMismatch
            }
            return committedIntent
        }
        guard state == .active else { throw CompositionTransactionError.notActive }
        try validate(currentDocument)
        let intent = CompositionCommandIntent(
            label: label,
            affectedCompositionID: affectedCompositionID,
            initialDocument: initialDocument,
            finalDocument: currentDocument
        )
        self.affectedCompositionID = affectedCompositionID
        committedIntent = intent
        state = .committed
        return intent
    }

    public func cancel(reason: CompositionRollbackReason) throws {
        if state == .cancelled { return }
        guard state != .committed else { throw CompositionTransactionError.alreadyCommitted }
        guard state == .active else { throw CompositionTransactionError.notActive }
        currentDocument = initialDocument
        rollbackReason = reason
        state = .cancelled
    }

    public func selectionDidChange(to identity: String) throws {
        guard identity != selectionIdentity, state == .active else { return }
        try cancel(reason: .selectionChanged)
    }

    private func validate(_ document: CompositionDocument) throws {
        do {
            try CompositionValidator.validate(document)
        } catch {
            throw CompositionTransactionError.invalidDocument
        }
    }
}
