import Foundation

public struct RGBA: Codable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    public func clamped() -> RGBA {
        RGBA(r: clamp01(r), g: clamp01(g), b: clamp01(b), a: clamp01(a))
    }
}

public enum BlendMathError: Error, Equatable {
    case unknownMode(String)
    case referenceImplementationUnavailable(String)
}

public enum BlendMath {
    private struct RGB {
        var r: Double
        var g: Double
        var b: Double

        subscript(_ index: Int) -> Double {
            get {
                switch index {
                case 0: return r
                case 1: return g
                default: return b
                }
            }
            set {
                switch index {
                case 0: r = newValue
                case 1: g = newValue
                default: b = newValue
                }
            }
        }
    }

    public static func blend(
        source rawSource: RGBA,
        destination rawDestination: RGBA,
        modeID: String
    ) throws -> RGBA {
        guard let descriptor = BlendModeCatalogue.descriptor(id: modeID) else {
            throw BlendMathError.unknownMode(modeID)
        }
        guard descriptor.referenceSupport == .implemented else {
            throw BlendMathError.referenceImplementationUnavailable(modeID)
        }

        let source = rawSource.clamped()
        let destination = rawDestination.clamped()
        let sourceRGB = RGB(r: source.r, g: source.g, b: source.b)
        let destinationRGB = RGB(r: destination.r, g: destination.g, b: destination.b)
        let blended = try blendColor(source: sourceRGB, destination: destinationRGB, modeID: modeID)

        let sourceAlpha = source.a
        let destinationAlpha = destination.a
        let outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha)
        guard outputAlpha > 0 else { return .clear }

        func composite(
            _ sourceComponent: Double,
            _ destinationComponent: Double,
            _ blendComponent: Double
        ) -> Double {
            let premultiplied =
                sourceAlpha * (1 - destinationAlpha) * sourceComponent
                + sourceAlpha * destinationAlpha * blendComponent
                + destinationAlpha * (1 - sourceAlpha) * destinationComponent
            return premultiplied / outputAlpha
        }

        return RGBA(
            r: composite(source.r, destination.r, blended.r),
            g: composite(source.g, destination.g, blended.g),
            b: composite(source.b, destination.b, blended.b),
            a: outputAlpha
        ).clamped()
    }

    public static func luminosity(_ value: RGBA) -> Double {
        luminosity(RGB(r: value.r, g: value.g, b: value.b))
    }

    private static func blendColor(source s: RGB, destination d: RGB, modeID: String) throws -> RGB {
        switch modeID {
        case "normal":
            return s
        case "darken":
            return zip(s, d, min)
        case "multiply":
            return zip(s, d, *)
        case "color-burn":
            return zip(s, d) { source, destination in
                colorBurn(source: source, destination: destination)
            }
        case "linear-burn":
            return zip(s, d) { max(0, $0 + $1 - 1) }
        case "darker-color":
            return luminosity(s) <= luminosity(d) ? s : d
        case "add", "linear-dodge":
            return zip(s, d) { min(1, $0 + $1) }
        case "lighten":
            return zip(s, d, max)
        case "screen":
            return zip(s, d) { 1 - (1 - $0) * (1 - $1) }
        case "color-dodge":
            return zip(s, d) { source, destination in
                colorDodge(source: source, destination: destination)
            }
        case "lighter-color":
            return luminosity(s) >= luminosity(d) ? s : d
        case "overlay":
            return zip(s, d) { source, destination in
                overlay(source: source, destination: destination)
            }
        case "soft-light":
            return zip(s, d) { source, destination in
                softLight(source: source, destination: destination)
            }
        case "hard-light":
            return zip(s, d) { source, destination in
                overlay(source: destination, destination: source)
            }
        case "linear-light":
            return zip(s, d) { clamp01($1 + 2 * $0 - 1) }
        case "vivid-light":
            return zip(s, d) { source, destination in
                vividLight(source: source, destination: destination)
            }
        case "pin-light":
            return zip(s, d) { source, destination in
                source <= 0.5
                    ? min(destination, 2 * source)
                    : max(destination, 2 * source - 1)
            }
        case "hard-mix":
            return zip(s, d) {
                vividLight(source: $0, destination: $1) < 0.5 ? 0 : 1
            }
        case "difference":
            return zip(s, d) { abs($1 - $0) }
        case "exclusion":
            return zip(s, d) { $1 + $0 - 2 * $1 * $0 }
        case "subtract":
            return zip(s, d) { max(0, $1 - $0) }
        case "divide":
            return zip(s, d) { source, destination in
                source == 0 ? 1 : min(1, destination / source)
            }
        case "hue":
            return setLuminosity(setSaturation(s, saturation(d)), luminosity(d))
        case "saturation":
            return setLuminosity(setSaturation(d, saturation(s)), luminosity(d))
        case "color":
            return setLuminosity(s, luminosity(d))
        case "luminosity":
            return setLuminosity(d, luminosity(s))
        default:
            throw BlendMathError.referenceImplementationUnavailable(modeID)
        }
    }

    private static func colorBurn(source: Double, destination: Double) -> Double {
        source <= 0 ? 0 : 1 - min(1, (1 - destination) / source)
    }

    private static func colorDodge(source: Double, destination: Double) -> Double {
        source >= 1 ? 1 : min(1, destination / (1 - source))
    }

    private static func overlay(source: Double, destination: Double) -> Double {
        destination <= 0.5
            ? 2 * source * destination
            : 1 - 2 * (1 - source) * (1 - destination)
    }

    private static func softLight(source: Double, destination: Double) -> Double {
        if source <= 0.5 {
            return destination - (1 - 2 * source) * destination * (1 - destination)
        }
        let curve = destination <= 0.25
            ? ((16 * destination - 12) * destination + 4) * destination
            : sqrt(destination)
        return destination + (2 * source - 1) * (curve - destination)
    }

    private static func vividLight(source: Double, destination: Double) -> Double {
        source <= 0.5
            ? colorBurn(source: 2 * source, destination: destination)
            : colorDodge(source: 2 * source - 1, destination: destination)
    }

    private static func luminosity(_ value: RGB) -> Double {
        0.3 * value.r + 0.59 * value.g + 0.11 * value.b
    }

    private static func saturation(_ value: RGB) -> Double {
        max(value.r, value.g, value.b) - min(value.r, value.g, value.b)
    }

    private static func setLuminosity(_ value: RGB, _ target: Double) -> RGB {
        let delta = target - luminosity(value)
        return clipColor(RGB(r: value.r + delta, g: value.g + delta, b: value.b + delta))
    }

    private static func clipColor(_ value: RGB) -> RGB {
        var result = value
        let lum = luminosity(result)
        let minimum = min(result.r, result.g, result.b)
        let maximum = max(result.r, result.g, result.b)

        if minimum < 0 {
            let denominator = lum - minimum
            if denominator != 0 {
                result.r = lum + ((result.r - lum) * lum) / denominator
                result.g = lum + ((result.g - lum) * lum) / denominator
                result.b = lum + ((result.b - lum) * lum) / denominator
            }
        }
        if maximum > 1 {
            let denominator = maximum - lum
            if denominator != 0 {
                result.r = lum + ((result.r - lum) * (1 - lum)) / denominator
                result.g = lum + ((result.g - lum) * (1 - lum)) / denominator
                result.b = lum + ((result.b - lum) * (1 - lum)) / denominator
            }
        }
        return RGB(r: clamp01(result.r), g: clamp01(result.g), b: clamp01(result.b))
    }

    private static func setSaturation(_ value: RGB, _ target: Double) -> RGB {
        let sorted = [0, 1, 2].sorted { value[$0] < value[$1] }
        let minimumIndex = sorted[0]
        let middleIndex = sorted[1]
        let maximumIndex = sorted[2]
        var result = value
        let minimum = value[minimumIndex]
        let maximum = value[maximumIndex]

        if maximum > minimum {
            result[middleIndex] = ((value[middleIndex] - minimum) * target) / (maximum - minimum)
            result[maximumIndex] = target
        } else {
            result[middleIndex] = 0
            result[maximumIndex] = 0
        }
        result[minimumIndex] = 0
        return result
    }

    private static func zip(
        _ lhs: RGB,
        _ rhs: RGB,
        _ operation: (Double, Double) -> Double
    ) -> RGB {
        RGB(
            r: operation(lhs.r, rhs.r),
            g: operation(lhs.g, rhs.g),
            b: operation(lhs.b, rhs.b)
        )
    }
}

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
