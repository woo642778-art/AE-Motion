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
    private static let supportedCategories: Set<String> = [
        "color", "drawing", "blur", "warp", "procedural", "3d",
        "move", "repeat", "matte", "opacity", "text",
    ]

    public static func normalizedCategory(_ rawValue: String?) -> String {
        let value = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if supportedCategories.contains(value) { return value }

        switch value {
        case "lighting", "light", "glow", "edge":
            return "drawing"
        case "stylize", "style", "generator", "generate":
            return "procedural"
        case "distort", "distortion", "transform", "transition":
            return "warp"
        case "colour", "grading", "color grading":
            return "color"
        case "mask", "matte/mask", "matte-mask":
            return "matte"
        default:
            return "procedural"
        }
    }

    public static func normalizedTags(
        name: String,
        id: String,
        existing: String?
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
        for value in (existing ?? "").components(separatedBy: CharacterSet(charactersIn: ",;")) {
            add(value)
        }
        for value in name.components(separatedBy: separators) { add(value) }
        let idTokens = id.components(separatedBy: separators).filter { token in
            !["com", "alightcreative", "effects", "effect"].contains(token.lowercased())
        }
        for value in idTokens { add(value) }

        let searchable = ([name, id, existing ?? ""].joined(separator: " ")).lowercased()
        if searchable.contains("bcc") || searchable.contains("boris") {
            ["bcc", "bbc", "boris", "borisfx", "boris fx", "continuum"].forEach(add)
        }

        return ordered.joined(separator: ",")
    }
}
