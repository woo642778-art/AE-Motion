import Foundation

public enum ToolPlacement: String, Codable, CaseIterable, Sendable {
    case extensionsHub, timeline, graph, layer, viewer, clip, color, audio, project
}

public enum ToolPlacementRegistry {
    private static let placements: [String: ToolPlacement] = [
        "speed.remap": .timeline, "easing.curve": .graph, "animation.core": .graph,
        "cutout.person": .layer, "depth.map": .viewer, "dead.frames": .clip,
        "camera.shake": .layer, "color.palette": .color, "preset.library": .project,
        "resource.hub": .extensionsHub, "host.diagnostics": .extensionsHub, "effects.integrity": .extensionsHub,
        "project.reliability": .project, "random.values": .extensionsHub, "expression.helper": .extensionsHub,
        "bpm.frames": .extensionsHub, "layer.offset": .extensionsHub,
    ]
    public static func placement(for toolID: String) -> ToolPlacement { placements[toolID] ?? .extensionsHub }
    public static var contextualToolIDs: Set<String> { Set(placements.compactMap { $0.value == .extensionsHub ? nil : $0.key }) }
    public static func contextualToolIDs(for placements: Set<ToolPlacement>) -> [String] { ToolRegistry.all.filter { placements.contains(placement(for: $0.id)) }.map(\.id) }
}

public enum CollectionProxyForwardingPolicy {
    public static func mayForward(selectorName: String) -> Bool { selectorName.range(of: "indexpath", options: .caseInsensitive) == nil }
}
