import Foundation

public enum BlendModeGroup: String, Codable, CaseIterable, Sendable {
    case normal
    case darken
    case lighten
    case contrast
    case inversion
    case component
    case utility
}

public enum BlendReferenceSupport: String, Codable, Sendable {
    case implemented
    case requiresSeed
    case requiresHostVerification
}

public struct BlendModeDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var group: BlendModeGroup
    public var referenceSupport: BlendReferenceSupport

    public init(
        id: String,
        displayName: String,
        group: BlendModeGroup,
        referenceSupport: BlendReferenceSupport = .implemented
    ) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.referenceSupport = referenceSupport
    }
}

public enum BlendModeCatalogue {
    public static let all: [BlendModeDescriptor] = [
        .init(id: "normal", displayName: "Normal", group: .normal),
        .init(id: "dissolve", displayName: "Dissolve", group: .normal, referenceSupport: .requiresSeed),
        .init(id: "dancing-dissolve", displayName: "Dancing Dissolve", group: .normal, referenceSupport: .requiresSeed),

        .init(id: "darken", displayName: "Darken", group: .darken),
        .init(id: "multiply", displayName: "Multiply", group: .darken),
        .init(id: "color-burn", displayName: "Color Burn", group: .darken),
        .init(id: "classic-color-burn", displayName: "Classic Color Burn", group: .darken, referenceSupport: .requiresHostVerification),
        .init(id: "linear-burn", displayName: "Linear Burn", group: .darken),
        .init(id: "darker-color", displayName: "Darker Color", group: .darken),

        .init(id: "add", displayName: "Add", group: .lighten),
        .init(id: "lighten", displayName: "Lighten", group: .lighten),
        .init(id: "screen", displayName: "Screen", group: .lighten),
        .init(id: "color-dodge", displayName: "Color Dodge", group: .lighten),
        .init(id: "classic-color-dodge", displayName: "Classic Color Dodge", group: .lighten, referenceSupport: .requiresHostVerification),
        .init(id: "linear-dodge", displayName: "Linear Dodge", group: .lighten),
        .init(id: "lighter-color", displayName: "Lighter Color", group: .lighten),

        .init(id: "overlay", displayName: "Overlay", group: .contrast),
        .init(id: "soft-light", displayName: "Soft Light", group: .contrast),
        .init(id: "hard-light", displayName: "Hard Light", group: .contrast),
        .init(id: "linear-light", displayName: "Linear Light", group: .contrast),
        .init(id: "vivid-light", displayName: "Vivid Light", group: .contrast),
        .init(id: "pin-light", displayName: "Pin Light", group: .contrast),
        .init(id: "hard-mix", displayName: "Hard Mix", group: .contrast),

        .init(id: "difference", displayName: "Difference", group: .inversion),
        .init(id: "classic-difference", displayName: "Classic Difference", group: .inversion, referenceSupport: .requiresHostVerification),
        .init(id: "exclusion", displayName: "Exclusion", group: .inversion),
        .init(id: "subtract", displayName: "Subtract", group: .inversion),
        .init(id: "divide", displayName: "Divide", group: .inversion),

        .init(id: "hue", displayName: "Hue", group: .component),
        .init(id: "saturation", displayName: "Saturation", group: .component),
        .init(id: "color", displayName: "Color", group: .component),
        .init(id: "luminosity", displayName: "Luminosity", group: .component),

        .init(id: "stencil-alpha", displayName: "Stencil Alpha", group: .utility, referenceSupport: .requiresHostVerification),
        .init(id: "stencil-luma", displayName: "Stencil Luma", group: .utility, referenceSupport: .requiresHostVerification),
        .init(id: "silhouette-alpha", displayName: "Silhouette Alpha", group: .utility, referenceSupport: .requiresHostVerification),
        .init(id: "silhouette-luma", displayName: "Silhouette Luma", group: .utility, referenceSupport: .requiresHostVerification),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func descriptor(id: String) -> BlendModeDescriptor? {
        byID[id]
    }

    public static func modes(in group: BlendModeGroup) -> [BlendModeDescriptor] {
        all.filter { $0.group == group }
    }
}
