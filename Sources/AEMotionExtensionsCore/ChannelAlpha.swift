import Foundation

public enum AlphaInterpretation: String, Codable, CaseIterable, Sendable {
    case straight
    case premultiplied
}

public enum ChannelSource: String, Codable, CaseIterable, Sendable {
    case red
    case green
    case blue
    case alpha
    case luminance
    case fullOn
    case fullOff
}

public struct ChannelMapping: Codable, Equatable, Sendable {
    public var red: ChannelSource
    public var green: ChannelSource
    public var blue: ChannelSource
    public var alpha: ChannelSource

    public init(
        red: ChannelSource = .red,
        green: ChannelSource = .green,
        blue: ChannelSource = .blue,
        alpha: ChannelSource = .alpha
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let identity = ChannelMapping()
}

public enum ChannelAlphaProcessor {
    public static func premultiply(_ value: RGBA) -> RGBA {
        let clamped = value.clamped()
        return RGBA(
            r: clamped.r * clamped.a,
            g: clamped.g * clamped.a,
            b: clamped.b * clamped.a,
            a: clamped.a
        )
    }

    public static func unpremultiply(_ value: RGBA) -> RGBA {
        let clamped = value.clamped()
        guard clamped.a > 0 else { return .clear }
        return RGBA(
            r: clamped.r / clamped.a,
            g: clamped.g / clamped.a,
            b: clamped.b / clamped.a,
            a: clamped.a
        ).clamped()
    }

    public static func map(_ value: RGBA, using mapping: ChannelMapping) -> RGBA {
        let input = value.clamped()
        return RGBA(
            r: component(mapping.red, from: input),
            g: component(mapping.green, from: input),
            b: component(mapping.blue, from: input),
            a: component(mapping.alpha, from: input)
        ).clamped()
    }

    public static func invertedAlpha(_ value: RGBA, preserveRGB: Bool) -> RGBA {
        let input = value.clamped()
        let alpha = 1 - input.a
        if preserveRGB {
            return RGBA(r: input.r, g: input.g, b: input.b, a: alpha)
        }
        return RGBA(r: alpha, g: alpha, b: alpha, a: alpha)
    }

    public static func preview(_ value: RGBA, channel: ChannelSource) -> RGBA {
        let component = component(channel, from: value.clamped())
        return RGBA(r: component, g: component, b: component, a: 1)
    }

    private static func component(_ source: ChannelSource, from value: RGBA) -> Double {
        switch source {
        case .red: return value.r
        case .green: return value.g
        case .blue: return value.b
        case .alpha: return value.a
        case .luminance: return 0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b
        case .fullOn: return 1
        case .fullOff: return 0
        }
    }
}
