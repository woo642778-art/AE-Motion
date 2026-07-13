import Foundation

public struct PresetApplicationCandidate: Equatable, Sendable, Identifiable {
    public var id: String { targetID }
    public let targetID: String
    public let title: String
    public let adapterID: String

    public init(targetID: String, title: String, adapterID: String) {
        self.targetID = targetID
        self.title = title
        self.adapterID = adapterID
    }
}

public enum PresetApplicationResolutionError: Error, LocalizedError, Equatable, Sendable {
    case targetNotDeclared(String)
    case unsupportedTarget(String)
    case noSupportedTarget

    public var errorDescription: String? {
        switch self {
        case .targetNotDeclared(let target):
            return "This preset does not declare target: \(target)"
        case .unsupportedTarget(let target):
            return "No runtime preset adapter is available for target: \(target)"
        case .noSupportedTarget:
            return "This preset does not contain a target supported by this release."
        }
    }
}

public enum PresetApplicationResolver {
    private static let supported: [PresetApplicationCandidate] = [
        .init(targetID: "speed.remap", title: "Speed Remap", adapterID: "adapter.speed-remap.v1"),
        .init(targetID: "easing.curve", title: "Easing Curve", adapterID: "adapter.easing-curve.v1"),
        .init(targetID: "camera.shake", title: "Camera Shake", adapterID: "adapter.camera-shake.v1"),
        .init(targetID: "color.palette", title: "Color Palette", adapterID: "adapter.color-palette.v1"),
    ]

    public static func candidates(for document: PresetDocument) -> [PresetApplicationCandidate] {
        var seen = Set<String>()
        var result: [PresetApplicationCandidate] = []

        for target in document.targets where seen.insert(target).inserted {
            if let candidate = supported.first(where: { $0.targetID == target }) {
                result.append(candidate)
            }
        }
        return result
    }

    public static func resolve(
        document: PresetDocument,
        requestedTarget: String
    ) throws -> PresetApplicationCandidate {
        guard document.targets.contains(requestedTarget) else {
            throw PresetApplicationResolutionError.targetNotDeclared(requestedTarget)
        }
        guard let candidate = supported.first(where: { $0.targetID == requestedTarget }) else {
            throw PresetApplicationResolutionError.unsupportedTarget(requestedTarget)
        }
        return candidate
    }

    public static func firstCandidate(for document: PresetDocument) throws -> PresetApplicationCandidate {
        guard let candidate = candidates(for: document).first else {
            throw PresetApplicationResolutionError.noSupportedTarget
        }
        return candidate
    }
}
