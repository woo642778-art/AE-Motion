#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum ToolBuildResult {
    case ready(UIViewController)
    case unavailable(title: String, reason: String)
}

@MainActor
enum ToolControllerFactory {
    static func buildResult(for toolID: String) -> ToolBuildResult {
        let title = ToolRegistry.all.first(where: { $0.id == toolID })?.title ?? toolID
        switch toolID {
        case "speed.remap": return .ready(SpeedRemapStudioViewController())
        case "easing.curve": return .ready(EasingCurveViewController())
        case "cutout.person": return .ready(PersonCutoutStudioViewController())
        case "depth.map": return .ready(DepthMapStudioViewController())
        case "dead.frames": return .ready(DeadFrameCleanerViewController())
        case "camera.shake": return .ready(CameraShakeViewController())
        case "random.values": return .ready(RandomValuesViewController())
        case "expression.helper": return .ready(ExpressionHelperViewController())
        case "preset.library": return .ready(PresetLibraryViewController())
        case "resource.hub": return .ready(ResourceHubViewController())
        case "bpm.frames": return .ready(BPMCalculatorViewController())
        case "color.palette": return .ready(ColorPaletteViewController())
        case "layer.offset": return .ready(LayerOffsetViewController())
        case "effects.integrity": return .ready(EffectIntegrityViewController(style: .insetGrouped))
        case "project.reliability": return .ready(ProjectReliabilityViewController())
        case "host.diagnostics": return .ready(HostDiagnosticsViewController())
        default:
            return .unavailable(
                title: title,
                reason: "This utility is not included in the current source-built framework."
            )
        }
    }

    static func controller(for toolID: String) -> UIViewController? {
        if case .ready(let controller) = buildResult(for: toolID) {
            return controller
        }
        return nil
    }

    static func descriptor(for toolID: String) -> ToolDescriptor? {
        guard SafeToolRegistry.independentToolIDs.contains(toolID) else { return nil }
        return ToolRegistry.all.first { $0.id == toolID }
    }

    static func present(_ toolID: String, from presenter: UIViewController) {
        ToolPresentationGuard.present(toolID, from: presenter)
    }
}
#endif
