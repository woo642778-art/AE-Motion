import Foundation

public enum SafeToolAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public struct SafeToolRegistryEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let availability: SafeToolAvailability

    public init(id: String, title: String, subtitle: String, availability: SafeToolAvailability) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.availability = availability
    }
}

public enum SafeToolRegistry {
    public static let independentToolIDs: Set<String> = [
        "random.values",
        "expression.helper",
        "preset.library",
        "resource.hub",
        "bpm.frames",
        "layer.offset",
        "effects.integrity",
        "project.reliability",
        "host.diagnostics",
    ]

    public static func snapshot(
        descriptors: [ToolDescriptor] = ToolRegistry.all,
        unavailableReasons: [String: String] = [:]
    ) -> [SafeToolRegistryEntry] {
        descriptors.compactMap { descriptor in
            guard independentToolIDs.contains(descriptor.id) else { return nil }
            let availability: SafeToolAvailability
            if let reason = unavailableReasons[descriptor.id], !reason.isEmpty {
                availability = .unavailable(reason: reason)
            } else {
                availability = .available
            }
            return SafeToolRegistryEntry(
                id: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                availability: availability
            )
        }
    }
}
