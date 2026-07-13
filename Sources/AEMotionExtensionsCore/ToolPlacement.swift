import Foundation

public enum ToolPlacement: String, Codable, CaseIterable, Sendable {
    case extensionsHub
    case timeline
    case graph
    case layer
    case viewer
    case clip
    case color
    case audio
    case project
}

public enum ToolPlacementRegistry {
    private static let placements: [String: ToolPlacement] = [
        "speed.remap": .timeline,
        "easing.curve": .graph,
        "cutout.person": .layer,
        "depth.map": .viewer,
        "dead.frames": .clip,
        "camera.shake": .layer,
        "color.palette": .color,
        "preset.library": .project,
        "resource.hub": .extensionsHub,
        "host.diagnostics": .extensionsHub,
        "random.values": .extensionsHub,
        "expression.helper": .extensionsHub,
        "bpm.frames": .extensionsHub,
        "layer.offset": .extensionsHub,
    ]

    public static func placement(for toolID: String) -> ToolPlacement {
        placements[toolID] ?? .extensionsHub
    }

    public static var contextualToolIDs: Set<String> {
        Set(placements.compactMap { entry in
            entry.value == .extensionsHub ? nil : entry.key
        })
    }

    public static func contextualToolIDs(for placements: Set<ToolPlacement>) -> [String] {
        ToolRegistry.all
            .filter { placements.contains(placement(for: $0.id)) }
            .map(\.id)
    }
}

/// Determines which Objective-C collection view callbacks are safe to forward
/// without translating an index path first.
public enum CollectionProxyForwardingPolicy {
    public static func mayForward(selectorName: String) -> Bool {
        selectorName.range(of: "indexpath", options: .caseInsensitive) == nil
    }
}
