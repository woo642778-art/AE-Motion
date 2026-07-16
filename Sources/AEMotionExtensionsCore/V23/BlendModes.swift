import Foundation

public struct BlendModeID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }
}

public enum BlendModeGroup: String, Codable, CaseIterable, Sendable {
    case normal
    case darken
    case lighten
    case contrast
    case difference
    case hsl
    case matte
    case utility
}

public enum BlendEvaluationPolicy: String, Codable, Sendable {
    case deterministic
    case stochasticRequiresSeed
    case alphaTopology
}

public struct BlendModeDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: BlendModeID
    public let displayName: String
    public let group: BlendModeGroup
    public let policy: BlendEvaluationPolicy

    public init(id: BlendModeID, displayName: String, group: BlendModeGroup, policy: BlendEvaluationPolicy = .deterministic) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.policy = policy
    }
}

public enum BlendModeCatalog {
    public static let all: [BlendModeDescriptor] = [
        .init(id: "normal", displayName: "Normal", group: .normal),
        .init(id: "dissolve", displayName: "Dissolve", group: .normal, policy: .stochasticRequiresSeed),
        .init(id: "dancingDissolve", displayName: "Dancing Dissolve", group: .normal, policy: .stochasticRequiresSeed),
        .init(id: "darken", displayName: "Darken", group: .darken),
        .init(id: "multiply", displayName: "Multiply", group: .darken),
        .init(id: "colorBurn", displayName: "Color Burn", group: .darken),
        .init(id: "classicColorBurn", displayName: "Classic Color Burn", group: .darken),
        .init(id: "linearBurn", displayName: "Linear Burn", group: .darken),
        .init(id: "darkerColor", displayName: "Darker Color", group: .darken),
        .init(id: "add", displayName: "Add", group: .lighten),
        .init(id: "lighten", displayName: "Lighten", group: .lighten),
        .init(id: "screen", displayName: "Screen", group: .lighten),
        .init(id: "colorDodge", displayName: "Color Dodge", group: .lighten),
        .init(id: "classicColorDodge", displayName: "Classic Color Dodge", group: .lighten),
        .init(id: "linearDodge", displayName: "Linear Dodge (Add)", group: .lighten),
        .init(id: "lighterColor", displayName: "Lighter Color", group: .lighten),
        .init(id: "overlay", displayName: "Overlay", group: .contrast),
        .init(id: "softLight", displayName: "Soft Light", group: .contrast),
        .init(id: "hardLight", displayName: "Hard Light", group: .contrast),
        .init(id: "linearLight", displayName: "Linear Light", group: .contrast),
        .init(id: "vividLight", displayName: "Vivid Light", group: .contrast),
        .init(id: "pinLight", displayName: "Pin Light", group: .contrast),
        .init(id: "hardMix", displayName: "Hard Mix", group: .contrast),
        .init(id: "difference", displayName: "Difference", group: .difference),
        .init(id: "classicDifference", displayName: "Classic Difference", group: .difference),
        .init(id: "exclusion", displayName: "Exclusion", group: .difference),
        .init(id: "subtract", displayName: "Subtract", group: .difference),
        .init(id: "divide", displayName: "Divide", group: .difference),
        .init(id: "hue", displayName: "Hue", group: .hsl),
        .init(id: "saturation", displayName: "Saturation", group: .hsl),
        .init(id: "color", displayName: "Color", group: .hsl),
        .init(id: "luminosity", displayName: "Luminosity", group: .hsl),
        .init(id: "stencilAlpha", displayName: "Stencil Alpha", group: .matte, policy: .alphaTopology),
        .init(id: "stencilLuma", displayName: "Stencil Luma", group: .matte, policy: .alphaTopology),
        .init(id: "silhouetteAlpha", displayName: "Silhouette Alpha", group: .matte, policy: .alphaTopology),
        .init(id: "silhouetteLuma", displayName: "Silhouette Luma", group: .matte, policy: .alphaTopology),
        .init(id: "alphaAdd", displayName: "Alpha Add", group: .utility, policy: .alphaTopology),
        .init(id: "luminescentPremul", displayName: "Luminescent Premul", group: .utility, policy: .alphaTopology),
    ]

    public static func descriptor(for id: BlendModeID) -> BlendModeDescriptor? {
        all.first { $0.id == id }
    }

    public static func grouped(search query: String = "") -> [(group: BlendModeGroup, modes: [BlendModeDescriptor])] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return BlendModeGroup.allCases.compactMap { group in
            let modes = all.filter { descriptor in
                guard descriptor.group == group else { return false }
                return normalized.isEmpty
                    || descriptor.displayName.lowercased().contains(normalized)
                    || descriptor.id.rawValue.lowercased().contains(normalized)
            }
            return modes.isEmpty ? nil : (group, modes)
        }
    }
}

public enum BlendReferenceMath {
    public static func composite(source: PixelRGBA, backdrop: PixelRGBA, mode: BlendModeID) -> PixelRGBA {
        let source = source.clamped
        let backdrop = backdrop.clamped

        switch mode.rawValue {
        case "stencilAlpha":
            return PixelRGBA(red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: backdrop.alpha * source.alpha).clamped
        case "stencilLuma":
            return PixelRGBA(red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: backdrop.alpha * source.rec709Luminance * source.alpha).clamped
        case "silhouetteAlpha":
            return PixelRGBA(red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: backdrop.alpha * (1 - source.alpha)).clamped
        case "silhouetteLuma":
            return PixelRGBA(red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: backdrop.alpha * (1 - source.rec709Luminance * source.alpha)).clamped
        case "alphaAdd":
            return PixelRGBA(red: backdrop.red, green: backdrop.green, blue: backdrop.blue, alpha: min(1, backdrop.alpha + source.alpha)).clamped
        case "luminescentPremul":
            let luminanceAlpha = PixelRGBA.unit(source.rec709Luminance * source.alpha)
            return sourceOver(source: PixelRGBA(red: source.red, green: source.green, blue: source.blue, alpha: luminanceAlpha), backdrop: backdrop, mode: "normal")
        default:
            return sourceOver(source: source, backdrop: backdrop, mode: mode)
        }
    }

    private static func sourceOver(source: PixelRGBA, backdrop: PixelRGBA, mode: BlendModeID) -> PixelRGBA {
        let sourceAlpha = source.alpha
        let backdropAlpha = backdrop.alpha
        let outputAlpha = sourceAlpha + backdropAlpha * (1 - sourceAlpha)
        guard outputAlpha > 1e-12 else { return .clear }

        let blended = blend(backdrop: (backdrop.red, backdrop.green, backdrop.blue), source: (source.red, source.green, source.blue), mode: mode)
        let red = ((1 - sourceAlpha) * backdropAlpha * backdrop.red
            + (1 - backdropAlpha) * sourceAlpha * source.red
            + sourceAlpha * backdropAlpha * blended.0) / outputAlpha
        let green = ((1 - sourceAlpha) * backdropAlpha * backdrop.green
            + (1 - backdropAlpha) * sourceAlpha * source.green
            + sourceAlpha * backdropAlpha * blended.1) / outputAlpha
        let blue = ((1 - sourceAlpha) * backdropAlpha * backdrop.blue
            + (1 - backdropAlpha) * sourceAlpha * source.blue
            + sourceAlpha * backdropAlpha * blended.2) / outputAlpha
        return PixelRGBA(red: red, green: green, blue: blue, alpha: outputAlpha).clamped
    }

    private static func blend(
        backdrop b: (Double, Double, Double),
        source s: (Double, Double, Double),
        mode: BlendModeID
    ) -> (Double, Double, Double) {
        switch mode.rawValue {
        case "normal", "dissolve", "dancingDissolve": return s
        case "darken": return map2(b, s, min)
        case "multiply": return map2(b, s, *)
        case "colorBurn", "classicColorBurn": return map2(b, s, colorBurn)
        case "linearBurn": return map2(b, s) { max(0, $0 + $1 - 1) }
        case "darkerColor": return luminance(b) <= luminance(s) ? b : s
        case "add", "linearDodge": return map2(b, s) { min(1, $0 + $1) }
        case "lighten": return map2(b, s, max)
        case "screen": return map2(b, s) { 1 - (1 - $0) * (1 - $1) }
        case "colorDodge", "classicColorDodge": return map2(b, s, colorDodge)
        case "lighterColor": return luminance(b) >= luminance(s) ? b : s
        case "overlay": return map2(b, s) { overlay(backdrop: $0, source: $1) }
        case "softLight": return map2(b, s) { softLight(backdrop: $0, source: $1) }
        case "hardLight": return map2(b, s) { overlay(backdrop: $1, source: $0) }
        case "linearLight": return map2(b, s) { PixelRGBA.unit($0 + 2 * $1 - 1) }
        case "vividLight": return map2(b, s, vividLight)
        case "pinLight": return map2(b, s, pinLight)
        case "hardMix": return map2(b, s) { vividLight(backdrop: $0, source: $1) < 0.5 ? 0 : 1 }
        case "difference", "classicDifference": return map2(b, s) { abs($0 - $1) }
        case "exclusion": return map2(b, s) { $0 + $1 - 2 * $0 * $1 }
        case "subtract": return map2(b, s) { max(0, $0 - $1) }
        case "divide": return map2(b, s) { $1 <= 1e-12 ? 1 : min(1, $0 / $1) }
        case "hue": return setLum(setSat(s, saturation(b)), luminance(b))
        case "saturation": return setLum(setSat(b, saturation(s)), luminance(b))
        case "color": return setLum(s, luminance(b))
        case "luminosity": return setLum(b, luminance(s))
        default: return s
        }
    }

    private static func map2(
        _ lhs: (Double, Double, Double),
        _ rhs: (Double, Double, Double),
        _ operation: (Double, Double) -> Double
    ) -> (Double, Double, Double) {
        (PixelRGBA.unit(operation(lhs.0, rhs.0)), PixelRGBA.unit(operation(lhs.1, rhs.1)), PixelRGBA.unit(operation(lhs.2, rhs.2)))
    }

    private static func overlay(backdrop: Double, source: Double) -> Double {
        backdrop <= 0.5 ? 2 * backdrop * source : 1 - 2 * (1 - backdrop) * (1 - source)
    }

    private static func softLight(backdrop: Double, source: Double) -> Double {
        if source <= 0.5 {
            return backdrop - (1 - 2 * source) * backdrop * (1 - backdrop)
        }
        let d: Double
        if backdrop <= 0.25 {
            d = ((16 * backdrop - 12) * backdrop + 4) * backdrop
        } else {
            d = sqrt(backdrop)
        }
        return backdrop + (2 * source - 1) * (d - backdrop)
    }

    private static func colorBurn(_ backdrop: Double, _ source: Double) -> Double {
        source <= 1e-12 ? 0 : 1 - min(1, (1 - backdrop) / source)
    }

    private static func colorDodge(_ backdrop: Double, _ source: Double) -> Double {
        source >= 1 - 1e-12 ? 1 : min(1, backdrop / (1 - source))
    }

    private static func vividLight(backdrop: Double, source: Double) -> Double {
        source < 0.5 ? colorBurn(backdrop, 2 * source) : colorDodge(backdrop, 2 * source - 1)
    }

    private static func pinLight(backdrop: Double, source: Double) -> Double {
        source < 0.5 ? min(backdrop, 2 * source) : max(backdrop, 2 * source - 1)
    }

    private static func luminance(_ color: (Double, Double, Double)) -> Double {
        0.3 * color.0 + 0.59 * color.1 + 0.11 * color.2
    }

    private static func saturation(_ color: (Double, Double, Double)) -> Double {
        max(color.0, color.1, color.2) - min(color.0, color.1, color.2)
    }

    private static func clipColor(_ color: (Double, Double, Double)) -> (Double, Double, Double) {
        let lum = luminance(color)
        let minimum = min(color.0, color.1, color.2)
        let maximum = max(color.0, color.1, color.2)
        var result = color
        if minimum < 0 {
            let denominator = lum - minimum
            if abs(denominator) > 1e-12 {
                result = (
                    lum + ((result.0 - lum) * lum) / denominator,
                    lum + ((result.1 - lum) * lum) / denominator,
                    lum + ((result.2 - lum) * lum) / denominator
                )
            }
        }
        if maximum > 1 {
            let denominator = maximum - lum
            if abs(denominator) > 1e-12 {
                result = (
                    lum + ((result.0 - lum) * (1 - lum)) / denominator,
                    lum + ((result.1 - lum) * (1 - lum)) / denominator,
                    lum + ((result.2 - lum) * (1 - lum)) / denominator
                )
            }
        }
        return (PixelRGBA.unit(result.0), PixelRGBA.unit(result.1), PixelRGBA.unit(result.2))
    }

    private static func setLum(_ color: (Double, Double, Double), _ lum: Double) -> (Double, Double, Double) {
        let delta = lum - luminance(color)
        return clipColor((color.0 + delta, color.1 + delta, color.2 + delta))
    }

    private static func setSat(_ color: (Double, Double, Double), _ target: Double) -> (Double, Double, Double) {
        var values = [(value: color.0, index: 0), (value: color.1, index: 1), (value: color.2, index: 2)]
        values.sort { $0.value < $1.value }
        var output = [0.0, 0.0, 0.0]
        let minimum = values[0]
        let middle = values[1]
        let maximum = values[2]
        if maximum.value > minimum.value {
            output[middle.index] = ((middle.value - minimum.value) * target) / (maximum.value - minimum.value)
            output[maximum.index] = target
        }
        output[minimum.index] = 0
        return (output[0], output[1], output[2])
    }
}
