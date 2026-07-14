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

public enum EffectQualificationStage: String, Codable, Sendable {
    case ci
    case device
}

public enum EffectQualificationDisposition: String, Codable, Sendable {
    case passed
    case failed
    case deviceQualificationRequired
    case timeout
    case crashed
}

public struct EffectVisualMetrics: Equatable, Codable, Sendable {
    public var topBlackRatio: Double
    public var bottomBlackRatio: Double
    public var leftBlackRatio: Double
    public var rightBlackRatio: Double
    public var transparentRatio: Double
    public var alphaLossRatio: Double

    public init(
        topBlackRatio: Double,
        bottomBlackRatio: Double,
        leftBlackRatio: Double,
        rightBlackRatio: Double,
        transparentRatio: Double,
        alphaLossRatio: Double
    ) {
        self.topBlackRatio = topBlackRatio
        self.bottomBlackRatio = bottomBlackRatio
        self.leftBlackRatio = leftBlackRatio
        self.rightBlackRatio = rightBlackRatio
        self.transparentRatio = transparentRatio
        self.alphaLossRatio = alphaLossRatio
    }

    public static let zero = EffectVisualMetrics(
        topBlackRatio: 0,
        bottomBlackRatio: 0,
        leftBlackRatio: 0,
        rightBlackRatio: 0,
        transparentRatio: 0,
        alphaLossRatio: 0
    )
}

public struct DeviceQualificationRecord: Equatable, Codable, Sendable {
    public var effectID: String
    public var descriptorSHA256: String
    public var hostVersion: String
    public var deviceClass: String
    public var stage: EffectQualificationStage
    public var disposition: EffectQualificationDisposition
    public var metrics: EffectVisualMetrics

    public init(
        effectID: String,
        descriptorSHA256: String,
        hostVersion: String,
        deviceClass: String,
        stage: EffectQualificationStage,
        disposition: EffectQualificationDisposition,
        metrics: EffectVisualMetrics
    ) {
        self.effectID = effectID
        self.descriptorSHA256 = descriptorSHA256
        self.hostVersion = hostVersion
        self.deviceClass = deviceClass
        self.stage = stage
        self.disposition = disposition
        self.metrics = metrics
    }
}

public enum EffectQualificationPolicy {
    public static func isEligibleForOther(
        effectID: String,
        descriptorSHA256: String,
        records: [DeviceQualificationRecord]
    ) -> Bool {
        records.contains {
            $0.effectID.caseInsensitiveCompare(effectID) == .orderedSame
                && $0.descriptorSHA256.lowercased() == descriptorSHA256.lowercased()
                && $0.stage == .device
                && $0.disposition == .passed
        }
    }
}
