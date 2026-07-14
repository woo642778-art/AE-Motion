import Foundation

public enum ProjectSchema {
    public static let currentVersion = 1
    public static let fileExtension = "aemotionproject"
}

public enum ProjectTrackKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case overlay
}

public enum ProjectInterpolation: String, Codable, CaseIterable, Sendable {
    case hold
    case linear
    case bezier
}

public enum ProjectMatteMode: String, Codable, CaseIterable, Sendable {
    case alpha
    case alphaInverted
    case luma
    case lumaInverted
}

public enum MediaAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case offline
    case missing
}

public enum CacheKind: String, Codable, CaseIterable, Sendable {
    case proxy
    case effect
    case analysis
    case thumbnail
}

public enum ProjectValue: Equatable, Sendable {
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case text(String)
    case point(x: Double, y: Double)
    case color(red: Double, green: Double, blue: Double, alpha: Double)
}

extension ProjectValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, number, integer, boolean, text, x, y, red, green, blue, alpha }
    private enum Kind: String, Codable { case number, integer, boolean, text, point, color }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .number: self = .number(try container.decode(Double.self, forKey: .number))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .integer))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .point:
            self = .point(x: try container.decode(Double.self, forKey: .x), y: try container.decode(Double.self, forKey: .y))
        case .color:
            self = .color(
                red: try container.decode(Double.self, forKey: .red),
                green: try container.decode(Double.self, forKey: .green),
                blue: try container.decode(Double.self, forKey: .blue),
                alpha: try container.decode(Double.self, forKey: .alpha)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .number(value):
            try container.encode(Kind.number, forKey: .type); try container.encode(value, forKey: .number)
        case let .integer(value):
            try container.encode(Kind.integer, forKey: .type); try container.encode(value, forKey: .integer)
        case let .boolean(value):
            try container.encode(Kind.boolean, forKey: .type); try container.encode(value, forKey: .boolean)
        case let .text(value):
            try container.encode(Kind.text, forKey: .type); try container.encode(value, forKey: .text)
        case let .point(x, y):
            try container.encode(Kind.point, forKey: .type); try container.encode(x, forKey: .x); try container.encode(y, forKey: .y)
        case let .color(red, green, blue, alpha):
            try container.encode(Kind.color, forKey: .type)
            try container.encode(red, forKey: .red); try container.encode(green, forKey: .green)
            try container.encode(blue, forKey: .blue); try container.encode(alpha, forKey: .alpha)
        }
    }
}

public struct ProjectKeyframe: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var time: Double
    public var value: ProjectValue
    public var interpolation: ProjectInterpolation

    public init(id: UUID = UUID(), time: Double, value: ProjectValue, interpolation: ProjectInterpolation = .linear) {
        self.id = id; self.time = time; self.value = value; self.interpolation = interpolation
    }
}

public struct ProjectProperty: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var value: ProjectValue
    public var keyframes: [ProjectKeyframe]

    public init(id: String, value: ProjectValue, keyframes: [ProjectKeyframe] = []) {
        self.id = id; self.value = value; self.keyframes = keyframes
    }
}

public struct ProjectEffect: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var descriptorID: String
    public var name: String
    public var isEnabled: Bool
    public var properties: [ProjectProperty]

    public init(id: UUID = UUID(), descriptorID: String, name: String, isEnabled: Bool = true, properties: [ProjectProperty] = []) {
        self.id = id; self.descriptorID = descriptorID; self.name = name; self.isEnabled = isEnabled; self.properties = properties
    }
}

public struct ProjectMask: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var points: [ProjectPoint]
    public var feather: Double
    public var opacity: Double

    public init(id: UUID = UUID(), name: String, points: [ProjectPoint] = [], feather: Double = 0, opacity: Double = 1) {
        self.id = id; self.name = name; self.points = points; self.feather = feather; self.opacity = opacity
    }
}

public struct ProjectPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct ProjectMatte: Codable, Equatable, Sendable {
    public var sourceLayerID: UUID
    public var mode: ProjectMatteMode
    public init(sourceLayerID: UUID, mode: ProjectMatteMode) { self.sourceLayerID = sourceLayerID; self.mode = mode }
}

public struct ProjectClip: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var mediaID: UUID
    public var sourceStart: Double
    public var sourceDuration: Double
    public var speed: Double

    public init(id: UUID = UUID(), mediaID: UUID, sourceStart: Double = 0, sourceDuration: Double, speed: Double = 1) {
        self.id = id; self.mediaID = mediaID; self.sourceStart = sourceStart; self.sourceDuration = sourceDuration; self.speed = speed
    }
}

public struct ProjectLayer: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var startTime: Double
    public var duration: Double
    public var isEnabled: Bool
    public var clips: [ProjectClip]
    public var effects: [ProjectEffect]
    public var properties: [ProjectProperty]
    public var masks: [ProjectMask]
    public var matte: ProjectMatte?

    public init(
        id: UUID = UUID(), name: String, startTime: Double = 0, duration: Double,
        isEnabled: Bool = true, clips: [ProjectClip] = [], effects: [ProjectEffect] = [],
        properties: [ProjectProperty] = [], masks: [ProjectMask] = [], matte: ProjectMatte? = nil
    ) {
        self.id = id; self.name = name; self.startTime = startTime; self.duration = duration
        self.isEnabled = isEnabled; self.clips = clips; self.effects = effects
        self.properties = properties; self.masks = masks; self.matte = matte
    }
}

public struct ProjectTrack: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ProjectTrackKind
    public var isMuted: Bool
    public var isLocked: Bool
    public var layers: [ProjectLayer]

    public init(id: UUID = UUID(), name: String, kind: ProjectTrackKind, isMuted: Bool = false, isLocked: Bool = false, layers: [ProjectLayer] = []) {
        self.id = id; self.name = name; self.kind = kind; self.isMuted = isMuted; self.isLocked = isLocked; self.layers = layers
    }
}

public struct ProjectSequence: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var duration: Double
    public var frameRate: Double
    public var width: Int
    public var height: Int
    public var tracks: [ProjectTrack]

    public init(id: UUID = UUID(), name: String, duration: Double, frameRate: Double = 30, width: Int = 1920, height: Int = 1080, tracks: [ProjectTrack] = []) {
        self.id = id; self.name = name; self.duration = duration; self.frameRate = frameRate; self.width = width; self.height = height; self.tracks = tracks
    }
}

public struct MediaReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var originalURL: String
    public var proxyURL: String?
    public var fingerprint: String?
    public var availability: MediaAvailability

    public init(id: UUID = UUID(), originalURL: String, proxyURL: String? = nil, fingerprint: String? = nil, availability: MediaAvailability = .available) {
        self.id = id; self.originalURL = originalURL; self.proxyURL = proxyURL; self.fingerprint = fingerprint; self.availability = availability
    }
}

public struct CacheReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: CacheKind
    public var relativePath: String
    public var sizeBytes: Int64
    public var checksum: String
    public var dependencyKeys: [String]
    public var createdAt: Date
    public var lastAccessedAt: Date

    public init(
        id: UUID = UUID(), kind: CacheKind, relativePath: String, sizeBytes: Int64,
        checksum: String, dependencyKeys: [String] = [], createdAt: Date = Date(), lastAccessedAt: Date = Date()
    ) {
        self.id = id; self.kind = kind; self.relativePath = relativePath; self.sizeBytes = sizeBytes
        self.checksum = checksum; self.dependencyKeys = dependencyKeys; self.createdAt = createdAt; self.lastAccessedAt = lastAccessedAt
    }
}

public struct ColorPipelineDescriptor: Codable, Equatable, Sendable {
    public var workingSpace: String
    public var bitDepth: Int
    public var linearLight: Bool
    public init(workingSpace: String = "Rec.709", bitDepth: Int = 8, linearLight: Bool = false) {
        self.workingSpace = workingSpace; self.bitDepth = bitDepth; self.linearLight = linearLight
    }
}

public struct AudioBus: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var gain: Double
    public var isMuted: Bool
    public init(id: UUID = UUID(), name: String = "Master", gain: Double = 1, isMuted: Bool = false) {
        self.id = id; self.name = name; self.gain = gain; self.isMuted = isMuted
    }
}

public struct RenderSettings: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var codec: String
    public var includeAlpha: Bool
    public init(width: Int = 1920, height: Int = 1080, frameRate: Double = 30, codec: String = "H.264", includeAlpha: Bool = false) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.codec = codec; self.includeAlpha = includeAlpha
    }
}

public struct ProjectDocument: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var sequences: [ProjectSequence]
    public var media: [MediaReference]
    public var caches: [CacheReference]
    public var colorPipeline: ColorPipelineDescriptor
    public var audioBuses: [AudioBus]
    public var renderSettings: RenderSettings
    public var lastAppliedCommandSequence: UInt64
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = ProjectSchema.currentVersion, id: UUID = UUID(), name: String,
        createdAt: Date = Date(), modifiedAt: Date = Date(), sequences: [ProjectSequence] = [],
        media: [MediaReference] = [], caches: [CacheReference] = [],
        colorPipeline: ColorPipelineDescriptor = .init(), audioBuses: [AudioBus] = [.init()],
        renderSettings: RenderSettings = .init(), lastAppliedCommandSequence: UInt64 = 0,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.sequences = sequences
        self.media = media; self.caches = caches; self.colorPipeline = colorPipeline
        self.audioBuses = audioBuses; self.renderSettings = renderSettings
        self.lastAppliedCommandSequence = lastAppliedCommandSequence; self.metadata = metadata
    }

    public static func empty(name: String = "Untitled Project") -> ProjectDocument {
        ProjectDocument(name: name)
    }
}

public enum ProjectValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case emptyName
    case invalidSequence(UUID)
    case duplicateIdentifier(UUID)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version): return "Unsupported project schema version: \(version)"
        case .emptyName: return "Project name cannot be empty."
        case let .invalidSequence(id): return "Sequence has invalid dimensions, duration, or frame rate: \(id)"
        case let .duplicateIdentifier(id): return "Duplicate project identifier: \(id)"
        }
    }
}

public enum ProjectValidator {
    public static func validate(_ document: ProjectDocument) throws {
        guard document.schemaVersion == ProjectSchema.currentVersion else { throw ProjectValidationError.unsupportedSchema(document.schemaVersion) }
        guard !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectValidationError.emptyName }
        var identifiers = Set<UUID>()
        func insert(_ id: UUID) throws {
            guard identifiers.insert(id).inserted else { throw ProjectValidationError.duplicateIdentifier(id) }
        }
        try insert(document.id)
        for media in document.media { try insert(media.id) }
        for cache in document.caches { try insert(cache.id) }
        for bus in document.audioBuses { try insert(bus.id) }
        for sequence in document.sequences {
            guard sequence.duration >= 0, sequence.frameRate > 0, sequence.width > 0, sequence.height > 0 else {
                throw ProjectValidationError.invalidSequence(sequence.id)
            }
            try insert(sequence.id)
            for track in sequence.tracks {
                try insert(track.id)
                for layer in track.layers {
                    try insert(layer.id)
                    for clip in layer.clips { try insert(clip.id) }
                    for effect in layer.effects { try insert(effect.id) }
                    for mask in layer.masks { try insert(mask.id) }
                    for property in layer.properties {
                        for keyframe in property.keyframes { try insert(keyframe.id) }
                    }
                }
            }
        }
    }
}
