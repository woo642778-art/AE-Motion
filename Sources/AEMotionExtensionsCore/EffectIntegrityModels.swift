import Foundation

public enum EffectIntegrityStatus: String, Codable, CaseIterable, Sendable {
    case existingWorking
    case existingBroken
    case duplicate
    case placeholder
    case unsupportedDependency
    case cleanRoomCandidate
    case implementedUnverified
    case implementedVerified
    case rejected
}

public struct EffectIntegrityFinding: Codable, Equatable, Sendable {
    public let code: String
    public let severity: String
    public let message: String

    public init(code: String, severity: String, message: String) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct EffectIntegrityRecord: Codable, Equatable, Sendable {
    public let effectID: String
    public let name: String
    public let fileName: String
    public let category: String
    public let status: EffectIntegrityStatus
    public let descriptorSHA256: String
    public let shaderSHA256: String?
    public let parameterSignature: String
    public let dependencies: [String]
    public let resources: [String]
    public let findings: [EffectIntegrityFinding]
    public let quarantineReason: String?

    public init(
        effectID: String,
        name: String,
        fileName: String,
        category: String,
        status: EffectIntegrityStatus,
        descriptorSHA256: String,
        shaderSHA256: String?,
        parameterSignature: String,
        dependencies: [String],
        resources: [String],
        findings: [EffectIntegrityFinding],
        quarantineReason: String?
    ) {
        self.effectID = effectID
        self.name = name
        self.fileName = fileName
        self.category = category
        self.status = status
        self.descriptorSHA256 = descriptorSHA256
        self.shaderSHA256 = shaderSHA256
        self.parameterSignature = parameterSignature
        self.dependencies = dependencies
        self.resources = resources
        self.findings = findings
        self.quarantineReason = quarantineReason
    }
}

public struct EffectIntegrityReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let sourceAppVersion: String
    public let sourceBuild: String
    public let records: [EffectIntegrityRecord]

    public init(
        schemaVersion: Int,
        generatedAt: String,
        sourceAppVersion: String,
        sourceBuild: String,
        records: [EffectIntegrityRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.sourceAppVersion = sourceAppVersion
        self.sourceBuild = sourceBuild
        self.records = records
    }
}

public struct EffectIntegritySummary: Equatable, Sendable {
    public let totalCount: Int
    public let visibleCount: Int
    public let quarantinedCount: Int

    public init(records: [EffectIntegrityRecord]) {
        totalCount = records.count
        visibleCount = records.filter { EffectVisibilityPolicy.isVisible($0.status) }.count
        quarantinedCount = totalCount - visibleCount
    }
}
