import Foundation

public struct RenderDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum RenderSizePolicy {
    public static let maximumLongEdge = 3_840
    public static let maximumPixelCount = 8_294_400

    public static func constrained(
        width: Int,
        height: Int,
        maximumLongEdge: Int = maximumLongEdge,
        maximumPixelCount: Int = maximumPixelCount
    ) -> RenderDimensions {
        let sourceWidth = max(2, width)
        let sourceHeight = max(2, height)
        let longEdge = max(sourceWidth, sourceHeight)
        let area = Double(sourceWidth) * Double(sourceHeight)

        let edgeScale = min(1, Double(maximumLongEdge) / Double(longEdge))
        let areaScale = min(1, sqrt(Double(maximumPixelCount) / max(1, area)))
        let scale = min(edgeScale, areaScale)

        func evenFloor(_ value: Double) -> Int {
            let floored = max(2, Int(floor(value)))
            return floored.isMultiple(of: 2) ? floored : floored - 1
        }

        return RenderDimensions(
            width: evenFloor(Double(sourceWidth) * scale),
            height: evenFloor(Double(sourceHeight) * scale)
        )
    }
}

public enum EffectSearchMetadata {
    /// These are the native XML category keys used by the target Alight Motion build.
    /// The visible labels are Move/Transform and Distortion/Warp, but the data keys are
    /// `transform` and `distort`. Replacing them with `move`/`warp` empties those tabs.
    private static let supportedCategories: Set<String> = [
        "color", "drawing", "blur", "distort", "procedural", "3d",
        "transform", "repeat", "matte", "opacity", "text",
    ]

    public static func normalizedCategory(_ rawValue: String?) -> String {
        let value = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let compact = value
            .replacingOccurrences(of: "&", with: "/")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "/")

        if supportedCategories.contains(value) { return value }

        switch compact {
        case "move", "transform", "move/transform", "transform/move":
            return "transform"
        case "warp", "distort", "distortion", "distortion/warp", "distort/warp", "warp/distortion", "warp/distort":
            return "distort"
        case "lighting", "light", "glow", "edge":
            return "drawing"
        case "stylize", "style", "generator", "generate", "other", "":
            return "procedural"
        case "colour", "grading", "colorgrading":
            return "color"
        case "mask", "matte/mask", "mattemask":
            return "matte"
        case "transition":
            return "distort"
        default:
            return "procedural"
        }
    }

    public static func normalizedTags(
        name: String,
        id: String,
        existing: String?,
        category: String? = nil
    ) -> String {
        var ordered: [String] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            let value = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !value.isEmpty, seen.insert(value).inserted else { return }
            ordered.append(value)
        }

        let separators = CharacterSet.alphanumerics.inverted
        for value in (existing ?? "").components(separatedBy: CharacterSet(charactersIn: ",;")) { add(value) }
        for value in name.components(separatedBy: separators) { add(value) }
        let idTokens = id.components(separatedBy: separators).filter { token in
            !["com", "alightcreative", "effects", "effect"].contains(token.lowercased())
        }
        for value in idTokens { add(value) }

        let searchable = ([name, id, existing ?? "", category ?? ""].joined(separator: " ")).lowercased()
        if searchable.contains("bcc") || searchable.contains("boris") {
            ["bcc", "bbc", "boris", "borisfx", "boris fx", "continuum"].forEach(add)
        }

        switch normalizedCategory(category) {
        case "transform":
            ["move", "transform", "move transform", "move/transform"].forEach(add)
        case "distort":
            ["distort", "distortion", "warp", "distortion warp", "distortion/warp"].forEach(add)
        default:
            break
        }

        return ordered.joined(separator: ",")
    }
}
