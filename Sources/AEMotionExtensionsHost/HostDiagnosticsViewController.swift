#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import Darwin

@MainActor
final class HostDiagnosticsViewController: UIViewController {
    private let output = UITextView()
    private var report = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native Host Diagnostics 2"
        view.backgroundColor = .systemBackground
        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 560).isActive = true

        let scanButton = ExtensionUI.button("Scan Runtime", action: UIAction { [weak self] _ in self?.scan() })
        let share = ExtensionUI.secondaryButton("Share Report", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.report, from: self, source: action.sender as? UIView)
        })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Run this while a project and video layer are selected. The report includes method type encodings and the live controller hierarchy needed for direct speed-keyframe and timeline integration."),
            scanButton,
            share,
            output,
        ]), in: self)
        scan()
    }

    private func scan() {
        var lines: [String] = [
            "AE Motion Native Host Diagnostics 2",
            "iOS: \(UIDevice.current.systemVersion)",
            "App: \(Bundle.main.bundleIdentifier ?? "unknown") \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")",
            "",
            "=== LIVE VIEW CONTROLLERS ===",
        ]

        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
        for (index, window) in windows.enumerated() {
            lines.append("WINDOW[\(index)] level=\(window.windowLevel.rawValue) key=\(window.isKeyWindow)")
            if let root = window.rootViewController {
                var visited = Set<ObjectIdentifier>()
                appendController(root, depth: 1, lines: &lines, visited: &visited)
            }
        }

        lines.append("")
        lines.append("=== MATCHING RUNTIME CLASSES ===")
        let keywords = ["Speed", "Retime", "Timeline", "Keyframe", "ProjectEdit", "Layer", "Curve", "Easing"]
        var count: UInt32 = 0
        guard let classes = objc_copyClassList(&count) else {
            lines.append("objc_copyClassList failed")
            report = lines.joined(separator: "\n")
            output.text = report
            return
        }
        defer { free(unsafeBitCast(classes, to: UnsafeMutableRawPointer.self)) }

        var matches: [AnyClass] = []
        for index in 0..<Int(count) {
            let cls: AnyClass = classes[index]
            let name = NSStringFromClass(cls)
            guard name.hasPrefix("AlightMotion.") || name.hasPrefix("_TtC12AlightMotion") else { continue }
            if keywords.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                matches.append(cls)
            }
        }
        matches.sort { NSStringFromClass($0) < NSStringFromClass($1) }
        for cls in matches {
            appendClass(cls, lines: &lines)
        }

        report = lines.joined(separator: "\n")
        output.text = report
    }

    private func appendController(
        _ controller: UIViewController,
        depth: Int,
        lines: inout [String],
        visited: inout Set<ObjectIdentifier>
    ) {
        let identifier = ObjectIdentifier(controller)
        guard visited.insert(identifier).inserted else { return }
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)VC \(NSStringFromClass(type(of: controller))) title=\(controller.title ?? "nil")")

        if let navigation = controller as? UINavigationController {
            for child in navigation.viewControllers {
                appendController(child, depth: depth + 1, lines: &lines, visited: &visited)
            }
        }
        if let tab = controller as? UITabBarController {
            for child in tab.viewControllers ?? [] {
                appendController(child, depth: depth + 1, lines: &lines, visited: &visited)
            }
        }
        for child in controller.children {
            appendController(child, depth: depth + 1, lines: &lines, visited: &visited)
        }
        if let presented = controller.presentedViewController {
            lines.append("\(indent)  PRESENTED")
            appendController(presented, depth: depth + 2, lines: &lines, visited: &visited)
        }
    }

    private func appendClass(_ cls: AnyClass, lines: inout [String]) {
        lines.append("")
        lines.append("CLASS \(NSStringFromClass(cls))")
        if let superclass = class_getSuperclass(cls) {
            lines.append("  SUPER \(NSStringFromClass(superclass))")
        }

        var propertyCount: UInt32 = 0
        if let properties = class_copyPropertyList(cls, &propertyCount) {
            defer { free(properties) }
            for index in 0..<Int(propertyCount) {
                let property = properties[index]
                let name = String(cString: property_getName(property))
                let attributes = property_getAttributes(property).map { String(cString: $0) } ?? ""
                lines.append("  P \(name) :: \(attributes)")
            }
        }

        var ivarCount: UInt32 = 0
        if let ivars = class_copyIvarList(cls, &ivarCount) {
            defer { free(ivars) }
            for index in 0..<Int(ivarCount) {
                let ivar = ivars[index]
                let name = ivar_getName(ivar).map { String(cString: $0) } ?? "?"
                let type = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? "?"
                lines.append("  I \(name) :: \(type) offset=\(ivar_getOffset(ivar))")
            }
        }

        var methodCount: UInt32 = 0
        if let methods = class_copyMethodList(cls, &methodCount) {
            defer { free(methods) }
            for index in 0..<Int(methodCount) {
                let method = methods[index]
                let selector = NSStringFromSelector(method_getName(method))
                let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? "?"
                lines.append("  M -[\(selector)] :: \(encoding)")
            }
        }

        if let meta = object_getClass(cls) {
            var classMethodCount: UInt32 = 0
            if let methods = class_copyMethodList(meta, &classMethodCount) {
                defer { free(methods) }
                for index in 0..<Int(classMethodCount) {
                    let method = methods[index]
                    let selector = NSStringFromSelector(method_getName(method))
                    let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? "?"
                    lines.append("  M +[\(selector)] :: \(encoding)")
                }
            }
        }
    }
}
#endif
