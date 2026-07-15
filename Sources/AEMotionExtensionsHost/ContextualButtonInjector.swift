#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import AEMotionExtensionsCore

nonisolated(unsafe) private var contextualButtonsKey: UInt8 = 0
nonisolated(unsafe) private var utilitiesButtonKey: UInt8 = 0
nonisolated(unsafe) private var compositionEditingControllerKey: UInt8 = 0
nonisolated(unsafe) private var compositionButtonKey: UInt8 = 0

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
        installCompositionEditingIfNeeded(in: presenter)
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

    static func installCompositionEditingIfNeeded(in presenter: UIViewController) {
        guard objc_getAssociatedObject(presenter, &compositionEditingControllerKey) == nil else { return }
        let required: Set<CompositionHostCapability> = [
            .readSelection,
            .readLayerIdentity,
            .readComposition,
            .mutateSelection,
            .previewComposition,
            .invalidatePreview,
        ]
        guard let session = CompositionHostBridge.resolve(in: presenter, requiring: required) else { return }
        let featureCapabilities: Set<CompositionHostCapability> = [
            .structuralPrecompose,
            .structuralParenting,
            .structuralMatte,
            .blendModes,
            .channelAlpha,
        ]
        guard !session.adapter.verifiedCapabilities.intersection(featureCapabilities).isEmpty else { return }

        let controller = CompositionEditingController(session: session, presenter: presenter)
        controller.install()
        objc_setAssociatedObject(
            presenter,
            &compositionEditingControllerKey,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "aemotion.composition.inspector"
        button.accessibilityLabel = "Compositing"
        button.setImage(UIImage(systemName: "square.3.layers.3d"), for: .normal)
        button.addTarget(controller, action: #selector(CompositionEditingController.presentInspectorForCurrentSelection), for: .touchUpInside)
        let item = UIBarButtonItem(customView: button)
        var items = presenter.navigationItem.rightBarButtonItems ?? []
        items.append(item)
        presenter.navigationItem.rightBarButtonItems = items
        objc_setAssociatedObject(presenter, &compositionButtonKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func installUtilitiesButtonIfNeeded(in presenter: UIViewController) {
        removeLegacyEditingButton(from: presenter)
        guard objc_getAssociatedObject(presenter, &utilitiesButtonKey) == nil else { return }
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
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "aemotion.install.utilities"
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(title: "AE motion", children: actions + [hub])
        let item = UIBarButtonItem(customView: button)
        var items = presenter.navigationItem.rightBarButtonItems ?? []
        items.append(item)
        presenter.navigationItem.rightBarButtonItems = items
        objc_setAssociatedObject(presenter, &utilitiesButtonKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func removeLegacyEditingButton(from presenter: UIViewController) {
        presenter.navigationItem.rightBarButtonItems = presenter.navigationItem.rightBarButtonItems?.filter { item in
            guard let control = item.customView as? UIControl else { return true }
            return control.accessibilityIdentifier != "aemotion.install.project.tools"
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
}
#endif
