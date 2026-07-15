#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

/// Public, test-only entry points used by the standalone Simulator host app.
///
/// The production runtime hook remains fail-closed and unchanged. This bridge
/// only exposes existing AE Motion UI inside a clean app process so that CI can
/// launch it, interact with it, and detect regressions without repacking an IPA.
@MainActor
public enum AEMotionTestHostBridge {
    public static func makeExtensionsRootViewController() -> UIViewController {
        let extensionsController = ExtensionsViewController(style: .insetGrouped)
        let navigationController = UINavigationController(
            rootViewController: extensionsController
        )
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    public static var registeredToolCount: Int {
        ToolRegistry.all.count
    }

    public static var registeredToolIDs: [String] {
        ToolRegistry.all.map(\.id)
    }
}
#endif
