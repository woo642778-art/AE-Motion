import Foundation

public enum ProjectFindingSeverity: String, Codable, CaseIterable, Sendable { case info, warning, error, blocker }
public enum ProjectFindingCode: String, Codable, CaseIterable, Sendable {
    case outdatedSchema, duplicateIdentifier, invalidSequence, missingMedia, missingProxy, unsupportedEffect, missingCache, corruptCache, cacheOverBudget
}

public struct ProjectFinding: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var code: ProjectFindingCode
    public var severity: ProjectFindingSeverity
    public var message: String
    public var entityID: UUID?
    public init(id: UUID = UUID(), code: ProjectFindingCode, severity: ProjectFindingSeverity, message: String, entityID: UUID? = nil) {
        self.id = id; self.code = code; self.severity = severity; self.message = message; self.entityID = entityID
    }
}

public struct ProjectDoctorReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var findings: [ProjectFinding]
    public var blockers: Int { findings.filter { $0.severity == .blocker }.count }
    public var errors: Int { findings.filter { $0.severity == .error }.count }
}

public enum ProjectDoctor {
    public static func inspect(
        _ document: ProjectDocument,
        availableEffectIDs: Set<String> = [],
        cacheRoot: URL? = nil,
        cacheBudgetBytes: Int64? = nil,
        fileManager: FileManager = .default
    ) -> ProjectDoctorReport {
        var findings: [ProjectFinding] = []
        if document.schemaVersion != ProjectSchema.currentVersion {
            findings.append(.init(code: .outdatedSchema, severity: .blocker, message: "Project schema \(document.schemaVersion) must be migrated."))
        }
        var seen = Set<UUID>()
        func check(_ id: UUID) { if !seen.insert(id).inserted { findings.append(.init(code: .duplicateIdentifier, severity: .error, message: "Duplicate identifier: \(id)", entityID: id)) } }
        check(document.id)
        for media in document.media {
            check(media.id)
            let path = URL(fileURLWithPath: media.originalURL).path
            if !fileManager.fileExists(atPath: path) { findings.append(.init(code: .missingMedia, severity: .error, message: "Missing media: \(media.originalURL)", entityID: media.id)) }
            if let proxy = media.proxyURL, !fileManager.fileExists(atPath: URL(fileURLWithPath: proxy).path) { findings.append(.init(code: .missingProxy, severity: .warning, message: "Missing proxy: \(proxy)", entityID: media.id)) }
        }
        var cacheBytes: Int64 = 0
        for cache in document.caches {
            check(cache.id); cacheBytes += cache.sizeBytes
            if let cacheRoot {
                let url = cacheRoot.appendingPathComponent(cache.relativePath)
                guard let data = try? Data(contentsOf: url) else { findings.append(.init(code: .missingCache, severity: .warning, message: "Missing cache: \(cache.relativePath)", entityID: cache.id)); continue }
                if StableChecksum.hexDigest(data) != cache.checksum { findings.append(.init(code: .corruptCache, severity: .error, message: "Corrupt cache: \(cache.relativePath)", entityID: cache.id)) }
            }
        }
        if let cacheBudgetBytes, cacheBytes > cacheBudgetBytes { findings.append(.init(code: .cacheOverBudget, severity: .warning, message: "Project cache exceeds its budget by \(cacheBytes - cacheBudgetBytes) bytes.")) }
        for bus in document.audioBuses { check(bus.id) }
        for sequence in document.sequences {
            check(sequence.id)
            if sequence.duration < 0 || sequence.frameRate <= 0 || sequence.width <= 0 || sequence.height <= 0 {
                findings.append(.init(code: .invalidSequence, severity: .blocker, message: "Invalid sequence settings: \(sequence.name)", entityID: sequence.id))
            }
            for track in sequence.tracks {
                check(track.id)
                for layer in track.layers {
                    check(layer.id)
                    for clip in layer.clips { check(clip.id) }
                    for mask in layer.masks { check(mask.id) }
                    for effect in layer.effects {
                        check(effect.id)
                        if !availableEffectIDs.isEmpty && !availableEffectIDs.contains(effect.descriptorID) {
                            findings.append(.init(code: .unsupportedEffect, severity: .error, message: "Unsupported effect: \(effect.descriptorID)", entityID: effect.id))
                        }
                    }
                }
            }
        }
        return ProjectDoctorReport(generatedAt: Date(), findings: findings)
    }

    public static func repairedCopy(_ document: ProjectDocument, report: ProjectDoctorReport) -> ProjectDocument {
        var repaired = document
        let missingMedia = Set(report.findings.filter { $0.code == .missingMedia }.compactMap(\.entityID))
        let invalidCaches = Set(report.findings.filter { $0.code == .missingCache || $0.code == .corruptCache }.compactMap(\.entityID))
        let unsupportedEffects = Set(report.findings.filter { $0.code == .unsupportedEffect }.compactMap(\.entityID))
        repaired.media = repaired.media.map { media in var value = media; if missingMedia.contains(value.id) { value.availability = .offline }; return value }
        repaired.caches.removeAll { invalidCaches.contains($0.id) }
        repaired.sequences = repaired.sequences.map { sequence in
            var sequence = sequence
            sequence.tracks = sequence.tracks.map { track in
                var track = track
                track.layers = track.layers.map { layer in
                    var layer = layer
                    layer.effects = layer.effects.map { effect in var effect = effect; if unsupportedEffects.contains(effect.id) { effect.isEnabled = false }; return effect }
                    return layer
                }
                return track
            }
            return sequence
        }
        repaired.modifiedAt = Date(); repaired.metadata["projectDoctorRepair"] = ISO8601DateFormatter().string(from: repaired.modifiedAt)
        return repaired
    }
}
