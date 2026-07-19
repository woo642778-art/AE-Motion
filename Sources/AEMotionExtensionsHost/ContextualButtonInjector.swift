#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import AEMotionExtensionsCore

nonisolated(unsafe) private var contextualButtonsKey: UInt8 = 0
nonisolated(unsafe) private var utilitiesButtonKey: UInt8 = 0
private let utilitiesPositionKey = "aemotion.utilities.button.normalizedPosition"

@MainActor
enum ContextualButtonInjector {
    private static let descriptors: [ContextualToolDescriptor] = [
        .init(id: "aemotion.context.transform", title: "Motion", context: .transform, systemImage: "move.3d"),
        .init(id: "aemotion.context.graph", title: "Graph", context: .graph, systemImage: "chart.xyaxis.line"),
        .init(id: "aemotion.context.speed", title: "Velocity", context: .speed, systemImage: "speedometer"),
        .init(id: "aemotion.context.effect", title: "Live", context: .effect, systemImage: "slider.horizontal.3"),
    ]

    static func installRuntimeHook() -> Bool {
        guard let cls = RuntimeResolver.projectEditorControllerClass(),
              let original = class_getInstanceMethod(cls, #selector(UIViewController.viewDidLayoutSubviews)),
              let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.aemotion_context_viewDidLayoutSubviews)) else {
            return false
        }
        let added = class_addMethod(
            cls,
            #selector(UIViewController.viewDidLayoutSubviews),
            method_getImplementation(replacement),
            method_getTypeEncoding(replacement)
        )
        if added {
            class_replaceMethod(
                cls,
                #selector(UIViewController.aemotion_context_viewDidLayoutSubviews),
                method_getImplementation(original),
                method_getTypeEncoding(original)
            )
        } else {
            method_exchangeImplementations(original, replacement)
        }
        return true
    }

    static func install(in presenter: UIViewController) {
        installPass(in: presenter)
        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak presenter] in
                guard let presenter else { return }
                installPass(in: presenter)
            }
        }
    }

    private static func installPass(in presenter: UIViewController) {
        var installed = objc_getAssociatedObject(presenter, &contextualButtonsKey) as? [String: UIButton] ?? [:]
        let sessions = HostEditingContextBridge.resolveAll(in: presenter)
        for descriptor in descriptors {
            guard installed[descriptor.id] == nil,
                  let session = sessions[descriptor.context] else { continue }
            let button = makeButton(descriptor: descriptor, session: session, presenter: presenter)
            place(button: button, beside: session.anchorView)
            installed[descriptor.id] = button
        }
        objc_setAssociatedObject(presenter, &contextualButtonsKey, installed, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func makeButton(
        descriptor: ContextualToolDescriptor,
        session: HostEditingSession,
        presenter: UIViewController
    ) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: descriptor.systemImage)
        configuration.title = descriptor.title
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak presenter, weak adapter = session.adapter] _ in
            guard let presenter, let adapter else { return }
            let controller = ContextualEditingViewController(
                adapter: adapter,
                descriptor: descriptor,
                hostController: presenter
            )
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .pageSheet
            if let sheet = navigation.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = true
                sheet.largestUndimmedDetentIdentifier = .medium
            }
            presenter.present(navigation, animated: true)
        })
        button.accessibilityIdentifier = descriptor.id
        button.accessibilityLabel = descriptor.title
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return button
    }

    private static func place(button: UIButton, beside anchor: UIView) {
        if let row = anchor as? UIStackView, row.axis == .horizontal {
            row.addArrangedSubview(button)
            return
        }
        if let row = anchor.superview as? UIStackView, row.axis == .horizontal {
            row.addArrangedSubview(button)
            return
        }
        guard let container = anchor.superview ?? anchor.window else { return }
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: anchor.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: anchor.topAnchor, constant: -4),
        ])
    }

    static func installUtilitiesButtonIfNeeded(in presenter: UIViewController) {
        removeLegacyEditingButton(from: presenter)
        if UIDevice.current.userInterfaceIdiom == .phone {
            installFloatingUtilitiesButtonIfNeeded(in: presenter)
        } else {
            installNavigationUtilitiesButtonIfNeeded(in: presenter)
        }
    }

    private static func utilityMenu(for presenter: UIViewController) -> UIMenu {
        let actions = ["preset.library", "effects.integrity", "project.reliability", "host.diagnostics"].compactMap { toolID -> UIAction? in
            guard let descriptor = ToolRegistry.all.first(where: { $0.id == toolID }) else { return nil }
            return UIAction(title: descriptor.title) { [weak presenter] _ in
                guard let presenter else { return }
                ToolControllerFactory.present(toolID, from: presenter)
            }
        }
        let hub = UIAction(title: "Extensions & Scripts", image: UIImage(systemName: "puzzlepiece.extension")) { [weak presenter] _ in
            guard let presenter else { return }
            let navigation = UINavigationController(rootViewController: ExtensionsViewController(style: .insetGrouped))
            navigation.modalPresentationStyle = .pageSheet
            presenter.present(navigation, animated: true)
        }
        return UIMenu(title: "AE motion", children: actions + [hub])
    }

    private static func installNavigationUtilitiesButtonIfNeeded(in presenter: UIViewController) {
        guard objc_getAssociatedObject(presenter, &utilitiesButtonKey) == nil else { return }
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "aemotion.install.utilities"
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = utilityMenu(for: presenter)
        let item = UIBarButtonItem(customView: button)
        var items = presenter.navigationItem.rightBarButtonItems ?? []
        items.append(item)
        presenter.navigationItem.rightBarButtonItems = items
        objc_setAssociatedObject(presenter, &utilitiesButtonKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func installFloatingUtilitiesButtonIfNeeded(in presenter: UIViewController) {
        if let existing = objc_getAssociatedObject(presenter, &utilitiesButtonKey) as? UIButton {
            clampFloatingButton(existing, in: presenter.view)
            return
        }

        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "aemotion.install.utilities"
        button.accessibilityLabel = "AE motion"
        button.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.94)
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 5
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.frame.size = CGSize(width: 44, height: 44)
        button.showsMenuAsPrimaryAction = true
        button.menu = utilityMenu(for: presenter)
        button.addGestureRecognizer(UIPanGestureRecognizer(target: presenter, action: #selector(UIViewController.aemotion_dragUtilitiesButton(_:))))
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: presenter, action: #selector(UIViewController.aemotion_resetUtilitiesButton(_:))))
        presenter.view.addSubview(button)
        restoreFloatingButton(button, in: presenter.view)
        objc_setAssociatedObject(presenter, &utilitiesButtonKey, button, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    fileprivate static func moveFloatingButton(_ button: UIButton, translation: CGPoint, in container: UIView, ended: Bool) {
        button.center = CGPoint(x: button.center.x + translation.x, y: button.center.y + translation.y)
        clampFloatingButton(button, in: container)
        if ended { saveFloatingButton(button, in: container) }
    }

    fileprivate static func resetFloatingButton(_ button: UIButton, in container: UIView) {
        button.center = defaultCenter(in: container, size: button.bounds.size)
        clampFloatingButton(button, in: container)
        saveFloatingButton(button, in: container)
    }

    private static func defaultCenter(in container: UIView, size: CGSize) -> CGPoint {
        let safe = container.safeAreaLayoutGuide.layoutFrame
        return CGPoint(x: safe.minX + size.width / 2 + 10, y: safe.maxY - size.height / 2 - 72)
    }

    private static func clampFloatingButton(_ button: UIButton, in container: UIView) {
        let safe = container.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 8, dy: 8)
        guard safe.width > 0, safe.height > 0 else { return }
        let halfW = button.bounds.width / 2
        let halfH = button.bounds.height / 2
        button.center = CGPoint(
            x: min(max(button.center.x, safe.minX + halfW), safe.maxX - halfW),
            y: min(max(button.center.y, safe.minY + halfH), safe.maxY - halfH)
        )
    }

    private static func restoreFloatingButton(_ button: UIButton, in container: UIView) {
        let value = UserDefaults.standard.string(forKey: utilitiesPositionKey)
        let parts = value?.split(separator: ",").compactMap { Double($0) } ?? []
        let safe = container.safeAreaLayoutGuide.layoutFrame
        if parts.count == 2, safe.width > 0, safe.height > 0 {
            button.center = CGPoint(x: safe.minX + safe.width * parts[0], y: safe.minY + safe.height * parts[1])
        } else {
            button.center = defaultCenter(in: container, size: button.bounds.size)
        }
        clampFloatingButton(button, in: container)
    }

    private static func saveFloatingButton(_ button: UIButton, in container: UIView) {
        let safe = container.safeAreaLayoutGuide.layoutFrame
        guard safe.width > 0, safe.height > 0 else { return }
        let x = min(max((button.center.x - safe.minX) / safe.width, 0), 1)
        let y = min(max((button.center.y - safe.minY) / safe.height, 0), 1)
        UserDefaults.standard.set("\(x),\(y)", forKey: utilitiesPositionKey)
    }

    private static func removeLegacyEditingButton(from presenter: UIViewController) {
        presenter.navigationItem.rightBarButtonItems = presenter.navigationItem.rightBarButtonItems?.filter { item in
            guard let control = item.customView as? UIControl else { return true }
            let identifier = control.accessibilityIdentifier
            return identifier != "aemotion.install.project.tools" && identifier != "aemotion.install.utilities"
        }
    }
}

extension UIViewController {
    @objc fileprivate func aemotion_context_viewDidLayoutSubviews() {
        self.aemotion_context_viewDidLayoutSubviews()
        guard String(describing: type(of: self)).contains("ProjectEditVC") else { return }
        ContextualButtonInjector.install(in: self)
        ContextualButtonInjector.installUtilitiesButtonIfNeeded(in: self)
    }

    @objc fileprivate func aemotion_dragUtilitiesButton(_ recognizer: UIPanGestureRecognizer) {
        guard let button = recognizer.view as? UIButton else { return }
        let translation = recognizer.translation(in: view)
        recognizer.setTranslation(.zero, in: view)
        ContextualButtonInjector.moveFloatingButton(
            button,
            translation: translation,
            in: view,
            ended: recognizer.state == .ended || recognizer.state == .cancelled
        )
    }

    @objc fileprivate func aemotion_resetUtilitiesButton(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let button = recognizer.view as? UIButton else { return }
        ContextualButtonInjector.resetFloatingButton(button, in: view)
    }
}
#endif