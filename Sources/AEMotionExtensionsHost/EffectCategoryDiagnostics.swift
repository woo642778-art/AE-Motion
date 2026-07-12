#if canImport(UIKit)
import Foundation
import AEMotionExtensionsCore

struct EffectCategoryIntegrityReport: Sendable {
    var directory: String
    var totalFiles: Int
    var categoryCounts: [String: Int]
    var parseFailures: [String]
    var duplicateIDs: [String]
    var transformAliases: Int
    var distortAliases: Int

    var lines: [String] {
        var output = [
            "Directory: \(directory)",
            "Effect XML files: \(totalFiles)",
        ]
        for key in categoryCounts.keys.sorted() {
            output.append("Category \(key): \(categoryCounts[key, default: 0])")
        }
        output.append("Move/Transform alias-bearing effects: \(transformAliases)")
        output.append("Distortion/Warp alias-bearing effects: \(distortAliases)")
        output.append("Duplicate effect IDs: \(duplicateIDs.count)")
        if !duplicateIDs.isEmpty { output.append("  \(duplicateIDs.sorted().joined(separator: ", "))") }
        output.append("XML opening-tag parse failures: \(parseFailures.count)")
        if !parseFailures.isEmpty { output.append("  \(parseFailures.sorted().joined(separator: ", "))") }
        if categoryCounts["transform", default: 0] == 0 {
            output.append("WARNING: Move/Transform is empty. Preserve the native XML category key 'transform'.")
        }
        if categoryCounts["distort", default: 0] == 0 {
            output.append("WARNING: Distortion/Warp is empty. Preserve the native XML category key 'distort'.")
        }
        return output
    }
}

enum EffectCategoryDiagnostics {
    static func scan(bundle: Bundle = .main) -> EffectCategoryIntegrityReport {
        let directory = bundle.resourceURL?.appendingPathComponent("BuiltinEffects", isDirectory: true)
        guard let directory else {
            return .init(directory: "missing", totalFiles: 0, categoryCounts: [:], parseFailures: ["Bundle resource URL unavailable"], duplicateIDs: [], transformAliases: 0, distortAliases: 0)
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "xml" } ?? []

        let tagExpression = try? NSRegularExpression(pattern: #"<effect\b[^>]*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let attributeExpression = try? NSRegularExpression(pattern: #"([A-Za-z_:][\w:.-]*)\s*=\s*([\"'])(.*?)\2"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        var counts: [String: Int] = [:]
        var failures: [String] = []
        var seenIDs = Set<String>()
        var duplicates = Set<String>()
        var transformAliases = 0
        var distortAliases = 0

        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let tagExpression,
                  let tagRange = tagExpression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.range,
                  let swiftRange = Range(tagRange, in: text),
                  let attributeExpression else {
                failures.append(file.lastPathComponent)
                continue
            }
            let tag = String(text[swiftRange])
            var attributes: [String: String] = [:]
            for match in attributeExpression.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard match.numberOfRanges >= 4,
                      let nameRange = Range(match.range(at: 1), in: tag),
                      let valueRange = Range(match.range(at: 3), in: tag) else { continue }
                attributes[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
            }
            let category = EffectSearchMetadata.normalizedCategory(attributes["category"])
            counts[category, default: 0] += 1
            if let id = attributes["id"], !seenIDs.insert(id).inserted { duplicates.insert(id) }
            let tags = (attributes["tags"] ?? "").lowercased()
            if category == "transform" && tags.contains("move") && tags.contains("transform") { transformAliases += 1 }
            if category == "distort" && tags.contains("distortion") && tags.contains("warp") { distortAliases += 1 }
        }

        return .init(
            directory: directory.path,
            totalFiles: files.count,
            categoryCounts: counts,
            parseFailures: failures,
            duplicateIDs: Array(duplicates),
            transformAliases: transformAliases,
            distortAliases: distortAliases
        )
    }
}
#endif
