#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

@MainActor
final class HostDiagnosticsViewController: UIViewController {
    private let output = UITextView()
    private let status = ExtensionUI.label("No scan has been run. This version does not scan the entire Objective-C runtime.")
    private var report = ""

    private let candidateClassNames = [
        "AlightMotion.ProjectEditVC",
        "AlightMotion.EditSpeedVC",
        "AlightMotion.EditSpeedVM",
        "AlightMotion.EditSpeedPopupVC",
        "AlightMotion.EditSpeedControlPanelVC",
        "AlightMotion.TimelineViewController",
        "AlightMotion.TimelineView",
        "AlightMotion.TimelineRetimeInteraction",
        "AlightMotion.TimelineLeftSpeedHandler",
        "AlightMotion.TimelineRightSpeedHandler",
        "AlightMotion.EditEasingPanelVC",
        "AlightMotion.EasingGraphView",
        "AlightMotion.KeyframeView",
    ]

    private let selectorKeywords = [
        "speed", "retime", "timeline", "keyframe", "easing", "curve",
        "layer", "media", "clip", "video", "import", "insert", "add"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native Host Diagnostics 3"
        view.backgroundColor = .systemBackground

        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 560).isActive = true
        output.text = "Tap Safe Scan while an Alight Motion project is open and a video layer is selected."

        let scanButton = ExtensionUI.button("Safe Scan", action: UIAction { [weak self] _ in
            self?.scanSafely()
        })
        let clearButton = ExtensionUI.secondaryButton("Clear", action: UIAction { [weak self] _ in
            self?.report = ""
            self?.output.text = ""
            self?.status.text = "Report cleared."
        })
        let buttons = ExtensionUI.horizontalStack([scanButton, clearButton])
        let share = ExtensionUI.secondaryButton("Share Report", action: UIAction { [weak self] action in
            guard let self else { return }
            guard !self.report.isEmpty else {
                ExtensionUI.alert(title: "No report", message: "Run Safe Scan first.", from: self)
                return
            }
            ExtensionUI.share(text: self.report, from: self, source: action.sender as? UIView)
        })

        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Crash-resistant diagnostics for timeline integration. It inspects only the live controller hierarchy and a fixed allowlist of speed/timeline classes; it no longer enumerates every runtime class."),
            buttons,
            share,
            status,
            output,
        ]), in: self)
    }

    private func scanSafely() {
        status.text = "Scanning live controllers and known host classes…"
        autoreleasepool {
            var lines: [String] = [
                "AE Motion Native Host Diagnostics 3",
                "iOS: \(UIDevice.current.systemVersion)",
                "App: \(Bundle.main.bundleIdentifier ?? "unknown") \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")",
                "Mode: allowlisted safe scan",
                "",
                "=== EFFECT CATEGORY INTEGRITY ===",
            ]
            lines.append(contentsOf: EffectCategoryDiagnostics.scan().lines)
            lines.append("")
            lines.append("=== LIVE VIEW CONTROLLERS ===")

            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter { !$0.isHidden }

            var activeControllers: [UIViewController] = []
            for (index, window) in windows.enumerated() {
                lines.append("WINDOW[\(index)] level=\(window.windowLevel.rawValue) key=\(window.isKeyWindow)")
                if let root = window.rootViewController {
                    var visited = Set<ObjectIdentifier>()
                    appendController(
                        root,
                        depth: 1,
                        lines: &lines,
                        visited: &visited,
                        collected: &activeControllers
                    )
                }
            }

            lines.append("")
            lines.append("=== ACTIVE CONTROLLER SELECTORS ===")
            for controller in deduplicated(activeControllers) {
                appendFilteredMethods(
                    of: type(of: controller),
                    heading: "ACTIVE \(NSStringFromClass(type(of: controller)))",
                    lines: &lines,
                    maxMethods: 120
                )
                appendKnownSelectorResponses(controller, lines: &lines)
            }

            lines.append("")
            lines.append("=== ALLOWLISTED HOST CLASSES ===")
            for name in candidateClassNames {
                guard let cls = NSClassFromString(name) else {
                    lines.append("MISSING \(name)")
                    continue
                }
                appendFilteredMethods(
                    of: cls,
                    heading: "CLASS \(name)",
                    lines: &lines,
                    maxMethods: 180
                )
            }

            report = lines.joined(separator: "\n")
            output.text = report
            status.text = "Safe scan complete: \(report.split(separator: "\n").count) lines."
        }
    }

    private func appendController(
        _ controller: UIViewController,
        depth: Int,
        lines: inout [String],
        visited: inout Set<ObjectIdentifier>,
        collected: inout [UIViewController]
    ) {
        guard depth <= 12 else { return }
        let identifier = ObjectIdentifier(controller)
        guard visited.insert(identifier).inserted else { return }
        collected.append(controller)
        let indent = String(repeating: "  ", count: depth)
        let name = NSStringFromClass(type(of: controller))
        lines.append("\(indent)VC \(name) title=\(controller.title ?? "nil") presented=\(controller.presentedViewController != nil)")

        if let navigation = controller as? UINavigationController {
            for child in navigation.viewControllers {
                appendController(child, depth: depth + 1, lines: &lines, visited: &visited, collected: &collected)
            }
        }
        if let tab = controller as? UITabBarController {
            for child in tab.viewControllers ?? [] {
                appendController(child, depth: depth + 1, lines: &lines, visited: &visited, collected: &collected)
            }
        }
        for child in controller.children {
            appendController(child, depth: depth + 1, lines: &lines, visited: &visited, collected: &collected)
        }
        if let presented = controller.presentedViewController {
            appendController(presented, depth: depth + 1, lines: &lines, visited: &visited, collected: &collected)
        }
    }

    private func appendFilteredMethods(
        of cls: AnyClass,
        heading: String,
        lines: inout [String],
        maxMethods: Int
    ) {
        lines.append("")
        lines.append(heading)
        var current: AnyClass? = cls
        var superclassDepth = 0

        while let type = current, superclassDepth < 4 {
            lines.append("  TYPE \(NSStringFromClass(type))")
            var count: UInt32 = 0
            if let methods = class_copyMethodList(type, &count) {
                defer { free(methods) }
                var emitted = 0
                for index in 0..<Int(count) {
                    let method = methods[index]
                    let selector = NSStringFromSelector(method_getName(method))
                    guard selectorKeywords.contains(where: {
                        selector.localizedCaseInsensitiveContains($0)
                    }) else { continue }
                    let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? "?"
                    lines.append("    -[\(selector)] :: \(encoding) argc=\(method_getNumberOfArguments(method))")
                    emitted += 1
                    if emitted >= maxMethods {
                        lines.append("    … method list truncated …")
                        break
                    }
                }
            }
            current = class_getSuperclass(type)
            superclassDepth += 1
        }
    }

    private func appendKnownSelectorResponses(
        _ controller: UIViewController,
        lines: inout [String]
    ) {
        let selectors = [
            "addLayerTapped",
            "addLayerTapped:",
            "addClip",
            "addClip:",
            "createNewVideo:",
            "selectMediaButton",
            "openURL:",
            "importMedia:",
            "insertMedia:",
            "addMedia:",
        ]
        for name in selectors {
            let selector = NSSelectorFromString(name)
            guard controller.responds(to: selector) else { continue }
            let method = class_getInstanceMethod(type(of: controller), selector)
            let encoding = method.flatMap(method_getTypeEncoding).map { String(cString: $0) } ?? "?"
            let arguments = method.map(method_getNumberOfArguments) ?? 0
            lines.append("  RESPONDS \(NSStringFromClass(type(of: controller))).\(name) :: \(encoding) argc=\(arguments)")
        }
    }

    private func deduplicated(_ controllers: [UIViewController]) -> [UIViewController] {
        var seen = Set<ObjectIdentifier>()
        return controllers.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
#endif
