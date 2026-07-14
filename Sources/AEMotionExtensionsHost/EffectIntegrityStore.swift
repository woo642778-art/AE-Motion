#if canImport(UIKit)
import Foundation
import AEMotionExtensionsCore

enum EffectIntegrityLoadResult {
    case loaded(EffectIntegrityReport)
    case missing
    case malformed
}

enum EffectIntegrityStore {
    static func load(bundle: Bundle = .main) -> EffectIntegrityReport? {
        guard case let .loaded(report) = loadResult(bundle: bundle) else { return nil }
        return report
    }

    static func loadResult(bundle: Bundle = .main) -> EffectIntegrityLoadResult {
        guard let root = bundle.resourceURL?
            .appendingPathComponent("AEMotionDiagnostics", isDirectory: true) else {
            return .missing
        }
        let url = root.appendingPathComponent("effect-integrity.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder().decode(EffectIntegrityReport.self, from: data),
              report.schemaVersion == 1 else {
            return .malformed
        }
        return .loaded(report)
    }

    static func summary(_ report: EffectIntegrityReport) -> EffectIntegritySummary {
        EffectIntegritySummary(records: report.records)
    }
}
#endif
