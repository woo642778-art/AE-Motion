import Foundation

public enum PresetMigrationError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedSchema(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let value):
            return "Preset schema \(value) is newer than the supported 1.0 schema."
        }
    }
}

public enum PresetMigrator {
    public static let currentSchemaVersion = "1.0"

    public static func migrate(_ source: PresetDocument) throws -> PresetDocument {
        if compareVersions(source.schemaVersion, currentSchemaVersion) == .orderedDescending {
            throw PresetMigrationError.unsupportedSchema(source.schemaVersion)
        }
        guard source.schemaVersion != currentSchemaVersion else { return source }

        var result = source
        result.extensions["migration.sourceSchema"] = source.schemaVersion
        result.schemaVersion = currentSchemaVersion
        result.targets = source.targets.map(normalizedTarget)
        if result.createdAt.isEmpty { result.createdAt = ISO8601DateFormatter().string(from: Date()) }
        result.modifiedAt = ISO8601DateFormatter().string(from: Date())
        return result
    }

    private static func normalizedTarget(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "speedremap", "speed-remap", "velocity": return "speed.remap"
        case "easingcurve", "easing-curve", "graph": return "easing.curve"
        case "camerashake", "camera-shake", "shake": return "camera.shake"
        default: return value
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}
