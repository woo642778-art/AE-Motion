import Foundation

public enum AlphaInterpretation: String, Codable, CaseIterable, Sendable {
    case straight
    case premultiplied
}

public enum PixelChannel: String, Codable, CaseIterable, Sendable {
    case red
    case green
    case blue
    case alpha
}

public enum ChannelSource: String, Codable, CaseIterable, Sendable {
    case red
    case green
    case blue
    case alpha
    case luminance
    case zero
    case one
}

public enum ChannelOperation: Codable, Equatable, Sendable {
    case map(output: PixelChannel, source: ChannelSource)
    case setEnabled(PixelChannel, Bool)
    case invertAlpha(preserveRGB: Bool)
    case luminanceToAlpha(preserveRGB: Bool)
    case premultiply
    case unpremultiply
}

public enum ChannelProcessor {
    public static func process(_ pixel: PixelRGBA, operations: [ChannelOperation]) -> PixelRGBA {
        operations.reduce(pixel.clamped) { current, operation in
            apply(operation, to: current)
        }.clamped
    }

    public static func apply(_ operation: ChannelOperation, to pixel: PixelRGBA) -> PixelRGBA {
        var output = pixel.clamped
        switch operation {
        case let .map(channel, source):
            set(channel, value: value(of: source, in: output), in: &output)
        case let .setEnabled(channel, enabled):
            if !enabled { set(channel, value: channel == .alpha ? 1 : 0, in: &output) }
        case let .invertAlpha(preserveRGB):
            let oldAlpha = output.alpha
            let newAlpha = 1 - oldAlpha
            if !preserveRGB {
                output = rescalePremultipliedRGB(output, from: oldAlpha, to: newAlpha)
            }
            output.alpha = newAlpha
        case let .luminanceToAlpha(preserveRGB):
            let oldAlpha = output.alpha
            let newAlpha = PixelRGBA.unit(output.rec709Luminance)
            if !preserveRGB {
                output = rescalePremultipliedRGB(output, from: oldAlpha, to: newAlpha)
            }
            output.alpha = newAlpha
        case .premultiply:
            output.red *= output.alpha
            output.green *= output.alpha
            output.blue *= output.alpha
        case .unpremultiply:
            guard output.alpha > 1e-12 else {
                output.red = 0
                output.green = 0
                output.blue = 0
                return output
            }
            output.red /= output.alpha
            output.green /= output.alpha
            output.blue /= output.alpha
        }
        return output.clamped
    }

    private static func value(of source: ChannelSource, in pixel: PixelRGBA) -> Double {
        switch source {
        case .red: pixel.red
        case .green: pixel.green
        case .blue: pixel.blue
        case .alpha: pixel.alpha
        case .luminance: pixel.rec709Luminance
        case .zero: 0
        case .one: 1
        }
    }

    private static func set(_ channel: PixelChannel, value: Double, in pixel: inout PixelRGBA) {
        switch channel {
        case .red: pixel.red = value
        case .green: pixel.green = value
        case .blue: pixel.blue = value
        case .alpha: pixel.alpha = value
        }
    }

    private static func rescalePremultipliedRGB(_ pixel: PixelRGBA, from oldAlpha: Double, to newAlpha: Double) -> PixelRGBA {
        guard oldAlpha > 1e-12 else {
            return PixelRGBA(red: 0, green: 0, blue: 0, alpha: pixel.alpha)
        }
        let ratio = newAlpha / oldAlpha
        return PixelRGBA(
            red: pixel.red * ratio,
            green: pixel.green * ratio,
            blue: pixel.blue * ratio,
            alpha: pixel.alpha
        )
    }
}
