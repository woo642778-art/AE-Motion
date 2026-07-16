import Foundation

public enum TrackMatteMode: String, Codable, CaseIterable, Sendable {
    case alpha
    case alphaInverted
    case luma
    case lumaInverted
}

public struct TrackMatteBinding: Codable, Equatable, Sendable {
    public var sourceLayerID: LayerID
    public var mode: TrackMatteMode

    public init(sourceLayerID: LayerID, mode: TrackMatteMode) {
        self.sourceLayerID = sourceLayerID
        self.mode = mode
    }
}

public enum TrackMatteEvaluator {
    public static func coverage(for matte: PixelRGBA, mode: TrackMatteMode) -> Double {
        let matte = matte.clamped
        switch mode {
        case .alpha:
            return matte.alpha
        case .alphaInverted:
            return 1 - matte.alpha
        case .luma:
            return PixelRGBA.unit(matte.rec709Luminance * matte.alpha)
        case .lumaInverted:
            return 1 - PixelRGBA.unit(matte.rec709Luminance * matte.alpha)
        }
    }

    public static func apply(matte: PixelRGBA, to content: PixelRGBA, mode: TrackMatteMode) -> PixelRGBA {
        let factor = coverage(for: matte, mode: mode)
        return PixelRGBA(
            red: content.red,
            green: content.green,
            blue: content.blue,
            alpha: content.alpha * factor
        ).clamped
    }
}
