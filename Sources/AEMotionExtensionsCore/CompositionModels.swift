import Foundation

public struct CompositionTimeRange: Codable, Equatable, Sendable {
    public var start: Double
    public var duration: Double

    public var end: Double { start + duration }

    public init(start: Double, duration: Double) {
        self.start = start
        self.duration = duration
    }
}

public struct CompositionTransform: Codable, Equatable, Sendable {
    public var positionX: Double
    public var positionY: Double
    public var anchorX: Double
    public var anchorY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotationDegrees: Double
    public var opacity: Double

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        anchorX: Double = 0,
        anchorY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotationDegrees: Double = 0,
        opacity: Double = 1
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
    }

    public static let identity = CompositionTransform()
}

public enum CompositionLayerKind: Codable, Equatable, Sendable {
    case video
    case image
    case shape
    case text
    case audio
    case null
    case precomposition(UUID)
}

public enum MatteMode: String, Codable, CaseIterable, Sendable {
    case alpha
    case alphaInverted
    case luma
    case lumaInverted
}

public struct MatteBinding: Codable, Equatable, Sendable {
    public var sourceLayerID: UUID
    public var mode: MatteMode

    public init(sourceLayerID: UUID, mode: MatteMode) {
        self.sourceLayerID = sourceLayerID
        self.mode = mode
    }
}

public struct ParentBinding: Codable, Equatable, Sendable {
    public var parentLayerID: UUID

    public init(parentLayerID: UUID) {
        self.parentLayerID = parentLayerID
    }
}

public struct CompositionLayer: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: CompositionLayerKind
    public var timeRange: CompositionTimeRange
    public var transform: CompositionTransform
    public var blendModeID: String
    public var alphaInterpretation: AlphaInterpretation
    public var channelMapping: ChannelMapping
    public var matte: MatteBinding?
    public var parent: ParentBinding?
    public var isEnabled: Bool
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: CompositionLayerKind,
        timeRange: CompositionTimeRange,
        transform: CompositionTransform = .identity,
        blendModeID: String = "normal",
        alphaInterpretation: AlphaInterpretation = .straight,
        channelMapping: ChannelMapping = .identity,
        matte: MatteBinding? = nil,
        parent: ParentBinding? = nil,
        isEnabled: Bool = true,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.timeRange = timeRange
        self.transform = transform
        self.blendModeID = blendModeID
        self.alphaInterpretation = alphaInterpretation
        self.channelMapping = channelMapping
        self.matte = matte
        self.parent = parent
        self.isEnabled = isEnabled
        self.metadata = metadata
    }
}

public struct Composition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var duration: Double
    public var frameRate: Double
    public var width: Int
    public var height: Int
    public var layers: [CompositionLayer]

    public init(
        id: UUID = UUID(),
        name: String,
        duration: Double,
        frameRate: Double = 30,
        width: Int = 1920,
        height: Int = 1080,
        layers: [CompositionLayer] = []
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.layers = layers
    }
}

public struct CompositionDocument: Codable, Equatable, Sendable {
    public var rootCompositionID: UUID
    public var compositions: [Composition]

    public init(rootCompositionID: UUID, compositions: [Composition]) {
        self.rootCompositionID = rootCompositionID
        self.compositions = compositions
    }
}
