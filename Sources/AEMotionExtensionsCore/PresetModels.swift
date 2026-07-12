import Foundation

public enum PresetKind: String, CaseIterable, Codable, Sendable {
    case effect
    case motion
    case velocity
    case graph
    case color
    case text
    case transition
    case effectGroup
    case audioReactive
    case editableTemplate
    case editRecipe
}

public enum PresetValueType: String, CaseIterable, Codable, Sendable {
    case number
    case integer
    case boolean
    case text
    case choice
    case color
    case point
    case angle
    case size
    case rectangle
    case gradient
    case curve
    case layerReference
    case maskReference
    case mapReference
    case audioBandReference
    case seed
    case qualityLevel
}

public struct PresetColor: Equatable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct PresetPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PresetSize: Equatable, Sendable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PresetRectangle: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PresetGradientStop: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var location: Double
    public var color: PresetColor

    public init(id: UUID = UUID(), location: Double, color: PresetColor) {
        self.id = id
        self.location = location
        self.color = color
    }
}

public struct PresetGradient: Equatable, Sendable, Codable {
    public var stops: [PresetGradientStop]

    public init(stops: [PresetGradientStop]) {
        self.stops = stops
    }
}

public enum PresetQualityLevel: String, CaseIterable, Codable, Sendable {
    case draft
    case preview
    case high
    case final
}

public enum PresetInterpolation: String, Codable, Sendable {
    case hold
    case linear
    case bezier
}

public struct PresetKeyframe: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var time: Double
    public var value: Double
    public var incomingSlope: Double?
    public var outgoingSlope: Double?
    public var interpolation: PresetInterpolation

    public init(
        id: UUID = UUID(),
        time: Double,
        value: Double,
        incomingSlope: Double? = nil,
        outgoingSlope: Double? = nil,
        interpolation: PresetInterpolation = .bezier
    ) {
        self.id = id
        self.time = time
        self.value = value
        self.incomingSlope = incomingSlope
        self.outgoingSlope = outgoingSlope
        self.interpolation = interpolation
    }
}

public struct KeyframeCurve: Equatable, Sendable, Codable {
    public var points: [PresetKeyframe]
    public var normalizedTime: Bool

    public init(points: [PresetKeyframe], normalizedTime: Bool = true) {
        self.points = points
        self.normalizedTime = normalizedTime
    }
}

public enum PresetValue: Equatable, Sendable, Codable {
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case text(String)
    case choice(String)
    case color(PresetColor)
    case point(PresetPoint)
    case angle(Double)
    case size(PresetSize)
    case rectangle(PresetRectangle)
    case gradient(PresetGradient)
    case curve(KeyframeCurve)
    case layerReference(String)
    case maskReference(String)
    case mapReference(String)
    case audioBandReference(String)
    case seed(Int)
    case qualityLevel(PresetQualityLevel)

    public var type: PresetValueType {
        switch self {
        case .number: return .number
        case .integer: return .integer
        case .boolean: return .boolean
        case .text: return .text
        case .choice: return .choice
        case .color: return .color
        case .point: return .point
        case .angle: return .angle
        case .size: return .size
        case .rectangle: return .rectangle
        case .gradient: return .gradient
        case .curve: return .curve
        case .layerReference: return .layerReference
        case .maskReference: return .maskReference
        case .mapReference: return .mapReference
        case .audioBandReference: return .audioBandReference
        case .seed: return .seed
        case .qualityLevel: return .qualityLevel
        }
    }

    public var numberValue: Double? {
        switch self {
        case .number(let value), .angle(let value): return value
        case .integer(let value), .seed(let value): return Double(value)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .text(let value), .choice(let value), .layerReference(let value),
             .maskReference(let value), .mapReference(let value), .audioBandReference(let value):
            return value
        case .qualityLevel(let value): return value.rawValue
        default: return nil
        }
    }

    public var displayString: String {
        switch self {
        case .number(let value): return String(format: "%.4g", value)
        case .integer(let value): return String(value)
        case .boolean(let value): return value ? "On" : "Off"
        case .text(let value), .choice(let value): return value
        case .color(let value):
            return String(format: "rgba(%.3f, %.3f, %.3f, %.3f)", value.red, value.green, value.blue, value.alpha)
        case .point(let value): return String(format: "(%.3f, %.3f)", value.x, value.y)
        case .angle(let value): return String(format: "%.3f°", value)
        case .size(let value): return String(format: "%.3f × %.3f", value.width, value.height)
        case .rectangle(let value):
            return String(format: "x %.3f · y %.3f · %.3f × %.3f", value.x, value.y, value.width, value.height)
        case .gradient(let value): return "\(value.stops.count) gradient stops"
        case .curve(let value): return "\(value.points.count) keyframes"
        case .layerReference(let value): return "Layer: \(value)"
        case .maskReference(let value): return "Mask: \(value)"
        case .mapReference(let value): return "Map: \(value)"
        case .audioBandReference(let value): return "Audio: \(value)"
        case .seed(let value): return "Seed \(value)"
        case .qualityLevel(let value): return value.rawValue.capitalized
        }
    }
}

public struct PresetParameter: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var value: PresetValue
    public var defaultValue: PresetValue?
    public var minimum: Double?
    public var maximum: Double?
    public var options: [String]
    public var keyframeable: Bool
    public var group: String?
    public var help: String?

    public init(
        id: String,
        name: String,
        value: PresetValue,
        defaultValue: PresetValue? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        options: [String] = [],
        keyframeable: Bool = false,
        group: String? = nil,
        help: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.options = options
        self.keyframeable = keyframeable
        self.group = group
        self.help = help
    }
}

public struct PresetMacroBinding: Equatable, Sendable, Codable {
    public var parameterID: String
    public var component: String?
    public var outputMinimum: Double
    public var outputMaximum: Double
    public var inverted: Bool
    public var clamp: Bool

    public init(
        parameterID: String,
        component: String? = nil,
        outputMinimum: Double,
        outputMaximum: Double,
        inverted: Bool = false,
        clamp: Bool = true
    ) {
        self.parameterID = parameterID
        self.component = component
        self.outputMinimum = outputMinimum
        self.outputMaximum = outputMaximum
        self.inverted = inverted
        self.clamp = clamp
    }
}

public struct PresetMacro: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var minimum: Double
    public var maximum: Double
    public var defaultValue: Double
    public var bindings: [PresetMacroBinding]

    public init(
        id: String,
        name: String,
        minimum: Double,
        maximum: Double,
        defaultValue: Double,
        bindings: [PresetMacroBinding]
    ) {
        self.id = id
        self.name = name
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
        self.bindings = bindings
    }
}

public struct PresetDependency: Equatable, Sendable, Codable {
    public var name: String
    public var minimumVersion: String?
    public var optional: Bool

    public init(name: String, minimumVersion: String? = nil, optional: Bool = false) {
        self.name = name
        self.minimumVersion = minimumVersion
        self.optional = optional
    }
}

public struct DependencyManifest: Equatable, Sendable, Codable {
    public var fonts: [PresetDependency]
    public var effects: [PresetDependency]
    public var media: [PresetDependency]
    public var models: [PresetDependency]

    public init(
        fonts: [PresetDependency] = [],
        effects: [PresetDependency] = [],
        media: [PresetDependency] = [],
        models: [PresetDependency] = []
    ) {
        self.fonts = fonts
        self.effects = effects
        self.media = media
        self.models = models
    }
}

public enum CompatibilityRuleKind: String, Codable, Sendable {
    case minimumAppVersion
    case maximumAppVersion
    case minimumIOSVersion
    case target
    case aspectRatio
    case frameRate
    case colorDepth
    case feature
}

public struct CompatibilityRule: Equatable, Sendable, Codable {
    public var kind: CompatibilityRuleKind
    public var value: String
    public var required: Bool

    public init(kind: CompatibilityRuleKind, value: String, required: Bool = true) {
        self.kind = kind
        self.value = value
        self.required = required
    }
}

public struct PresetMediaSlot: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var required: Bool
    public var acceptedTypes: [String]
    public var defaultResource: String?

    public init(
        id: String,
        name: String,
        required: Bool = true,
        acceptedTypes: [String] = [],
        defaultResource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.required = required
        self.acceptedTypes = acceptedTypes
        self.defaultResource = defaultResource
    }
}

public struct PresetResponsiveTime: Equatable, Sendable, Codable {
    public var introDuration: Double
    public var outroDuration: Double
    public var minimumMiddleDuration: Double
    public var loopMiddle: Bool

    public init(
        introDuration: Double = 0,
        outroDuration: Double = 0,
        minimumMiddleDuration: Double = 0,
        loopMiddle: Bool = false
    ) {
        self.introDuration = introDuration
        self.outroDuration = outroDuration
        self.minimumMiddleDuration = minimumMiddleDuration
        self.loopMiddle = loopMiddle
    }
}

public struct EditableTemplateDefinition: Equatable, Sendable, Codable {
    public var exposedParameterIDs: [String]
    public var lockedParameterIDs: [String]
    public var mediaSlots: [PresetMediaSlot]
    public var responsiveTime: PresetResponsiveTime?

    public init(
        exposedParameterIDs: [String] = [],
        lockedParameterIDs: [String] = [],
        mediaSlots: [PresetMediaSlot] = [],
        responsiveTime: PresetResponsiveTime? = nil
    ) {
        self.exposedParameterIDs = exposedParameterIDs
        self.lockedParameterIDs = lockedParameterIDs
        self.mediaSlots = mediaSlots
        self.responsiveTime = responsiveTime
    }
}

public struct PresetDocument: Equatable, Sendable, Codable, Identifiable {
    public var schemaVersion: String
    public var id: String
    public var name: String
    public var summary: String
    public var author: String
    public var kind: PresetKind
    public var targets: [String]
    public var tags: [String]
    public var parameters: [PresetParameter]
    public var macros: [PresetMacro]
    public var dependencies: DependencyManifest
    public var compatibility: [CompatibilityRule]
    public var template: EditableTemplateDefinition?
    public var previewImagePNG: Data?
    public var createdAt: String
    public var modifiedAt: String
    public var extensions: [String: String]

    public init(
        schemaVersion: String = "1.0",
        id: String,
        name: String,
        summary: String = "",
        author: String = "",
        kind: PresetKind,
        targets: [String] = [],
        tags: [String] = [],
        parameters: [PresetParameter] = [],
        macros: [PresetMacro] = [],
        dependencies: DependencyManifest = .init(),
        compatibility: [CompatibilityRule] = [],
        template: EditableTemplateDefinition? = nil,
        previewImagePNG: Data? = nil,
        createdAt: String = "",
        modifiedAt: String = "",
        extensions: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.author = author
        self.kind = kind
        self.targets = targets
        self.tags = tags
        self.parameters = parameters
        self.macros = macros
        self.dependencies = dependencies
        self.compatibility = compatibility
        self.template = template
        self.previewImagePNG = previewImagePNG
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.extensions = extensions
    }

    public func parameter(id: String) -> PresetParameter? {
        parameters.first { $0.id == id }
    }

    public mutating func setParameter(_ parameter: PresetParameter) {
        if let index = parameters.firstIndex(where: { $0.id == parameter.id }) {
            parameters[index] = parameter
        } else {
            parameters.append(parameter)
        }
    }
}
