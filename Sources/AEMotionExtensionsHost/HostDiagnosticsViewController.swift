#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import Darwin

final class HostDiagnosticsViewController: UIViewController {
    private let output = UITextView()
    private var report = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native Host Diagnostics"
        view.backgroundColor = .systemBackground
        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        output.heightAnchor.constraint(equalToConstant: 520).isActive = true
        let scan = ExtensionUI.button("Scan Runtime", action: UIAction { [weak self] _ in self?.scan() })
        let share = ExtensionUI.button("Share Report", action: UIAction { [weak self] action in
            guard let self else { return }
            ExtensionUI.share(text: self.report, from: self, source: action.sender as? UIView)
        })
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("This report is used to discover the private speed/timeline bridge needed for direct application to the selected Alight Motion layer."), scan, share, output
        ]), in: self)
        scan()
    }

    private func scan() {
        let names = [
            "AlightMotion.EditSpeedVC", "_TtC12AlightMotion11EditSpeedVC",
            "AlightMotion.EditSpeedVM", "_TtC12AlightMotion11EditSpeedVM",
            "AlightMotion.ProjectEditVC", "_TtC12AlightMotion13ProjectEditVC",
            "AlightMotion.TimelineRetimeInteraction", "_TtC12AlightMotion25TimelineRetimeInteraction",
            "AlightMotion.KeyframeView", "_TtC12AlightMotion12KeyframeView",
        ]
        var lines: [String] = ["AE Motion Native Host Diagnostics", "iOS: \(UIDevice.current.systemVersion)", ""]
        var seen = Set<ObjectIdentifier>()
        for name in names {
            guard let cls = NSClassFromString(name) else { continue }
            let identifier = ObjectIdentifier(cls)
            guard seen.insert(identifier).inserted else { continue }
            lines.append("CLASS \(NSStringFromClass(cls))")
            var methodCount: UInt32 = 0
            if let methods = class_copyMethodList(cls, &methodCount) {
                for index in 0..<Int(methodCount) {
                    lines.append("  M \(NSStringFromSelector(method_getName(methods[index])))")
                }
                free(methods)
            }
            var ivarCount: UInt32 = 0
            if let ivars = class_copyIvarList(cls, &ivarCount) {
                for index in 0..<Int(ivarCount) {
                    if let name = ivar_getName(ivars[index]) {
                        lines.append("  I \(String(cString: name))")
                    }
                }
                free(ivars)
            }
            lines.append("")
        }
        report = lines.joined(separator: "\n")
        output.text = report
    }
}
#endif
