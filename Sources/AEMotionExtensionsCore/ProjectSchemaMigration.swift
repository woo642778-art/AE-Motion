import Foundation

public enum ProjectMigrationError: Error, Equatable, LocalizedError {
    case invalidTopLevel
    case futureSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidTopLevel: return "Project data is not a JSON object."
        case let .futureSchema(version): return "Project schema \(version) is newer than this build supports."
        }
    }
}

public enum ProjectSchemaMigrator {
    public static func migrate(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        guard var dictionary = object as? [String: Any] else { throw ProjectMigrationError.invalidTopLevel }
        let version = dictionary["schemaVersion"] as? Int ?? 0
        guard version <= ProjectSchema.currentVersion else { throw ProjectMigrationError.futureSchema(version) }
        if version == ProjectSchema.currentVersion { return data }

        dictionary["schemaVersion"] = ProjectSchema.currentVersion

        let formatter = ISO8601DateFormatter()
        for key in ["createdAt", "modifiedAt"] {
            if let text = dictionary[key] as? String, let date = formatter.date(from: text) {
                dictionary[key] = date.timeIntervalSince1970
            }
        }
        dictionary["sequences"] = dictionary["sequences"] ?? []
        dictionary["media"] = dictionary["media"] ?? []
        dictionary["caches"] = dictionary["caches"] ?? []
        dictionary["audioBuses"] = dictionary["audioBuses"] ?? []
        dictionary["metadata"] = dictionary["metadata"] ?? [:]
        dictionary["lastAppliedCommandSequence"] = dictionary["lastAppliedCommandSequence"] ?? 0
        dictionary["colorPipeline"] = dictionary["colorPipeline"] ?? [
            "workingSpace": "Rec.709", "bitDepth": 8, "linearLight": false,
        ]
        dictionary["renderSettings"] = dictionary["renderSettings"] ?? [
            "width": 1920, "height": 1080, "frameRate": 30.0,
            "codec": "H.264", "includeAlpha": false,
        ]
        return try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
    }
}
