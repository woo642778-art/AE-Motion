#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
enum ToolControllerFactory {
    static func controller(for toolID: String) -> UIViewController? {
        switch toolID {
        case "speed.remap": return SpeedRemapStudioViewController()
        case "easing.curve": return EasingCurveViewController()
        case "cutout.person": return PersonCutoutStudioViewController()
        case "depth.map": return DepthMapStudioViewController()
        case "dead.frames": return DeadFrameCleanerViewController()
        case "camera.shake": return CameraShakeViewController()
        case "random.values": return RandomValuesViewController()
        case "expression.helper": return ExpressionHelperViewController()
        case "preset.library": return PresetLibraryViewController()
        case "resource.hub": return ResourceHubViewController()
        case "bpm.frames": return BPMCalculatorViewController()
        case "color.palette": return ColorPaletteViewController()
        case "layer.offset": return LayerOffsetViewController()
        case "effects.integrity": return EffectIntegrityViewController(style: .insetGrouped)
        case "project.reliability": return ProjectReliabilityViewController()
        case "host.diagnostics": return HostDiagnosticsViewController()
        default: return nil
        }
    }

    static func descriptor(for toolID: String) -> ToolDescriptor? {
        let placement = ToolPlacementRegistry.placement(for: toolID)
        guard placement == .extensionsHub || toolID == "preset.library" || toolID == "project.reliability" else {
            return nil
        }
        return ToolRegistry.all.first { $0.id == toolID }
    }

    static func present(_ toolID: String, from presenter: UIViewController) {
        guard let controller = controller(for: toolID) else {
            ExtensionUI.alert(
                title: "Tool unavailable",
                message: "This tool is not available in the current build.",
                from: presenter
            )
            return
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        presenter.present(navigation, animated: true)
    }
}
#endif
