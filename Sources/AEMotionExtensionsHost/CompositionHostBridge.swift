#if canImport(UIKit)
import Foundation
import UIKit
import AEMotionExtensionsCore

@MainActor
enum CompositionHostBridge {
    private enum SelectorName {
        static let capabilities = "aemotionCompositionCapabilities"
        static let snapshot = "aemotionCompositionSnapshotJSON"
        static let document = "aemotionCompositionDocumentJSON"
        static let supportedBlendModes = "aemotionSupportedBlendModeIdentifiers"
        static let setSelection = "aemotionSetSelectedLayerIdentifiersJSON:"
        static let preview = "aemotionPreviewCompositionDocumentJSON:"
        static let commit = "aemotionCommitCompositionIntentJSON:"
        static let rollback = "aemotionRollbackCompositionPreview"
        static let verify = "aemotionVerifyCompositionIntentJSON:"
        static let invalidate = "aemotionInvalidateCompositionPreview"
        static let timelineView = "aemotionTimelineView"
        static let viewerView = "aemotionViewerView"
    }

    static func resolve(
        in controller: UIViewController,
        requiring required: Set<CompositionHostCapability>
    ) -> CompositionHostSession? {
        guard let expectedClass = RuntimeResolver.projectEditorControllerClass(),
              controller.isKind(of: expectedClass) else { return nil }
        guard let adapter = SelectorCompositionHostAdapter(controller: controller),
              required.isSubset(of: adapter.verifiedCapabilities),
              let timeline = object(controller, selector: SelectorName.timelineView) as? UIView,
              let viewer = object(controller, selector: SelectorName.viewerView) as? UIView,
              timeline.window != nil,
              viewer.window != nil,
              let snapshot = adapter.snapshot(),
              snapshot.hasStableSelection,
              let document = adapter.readCompositionDocument() else {
            return nil
        }
        guard document.compositions.contains(where: { $0.id == snapshot.compositionID }) else { return nil }
        do {
            try CompositionValidator.validate(document)
        } catch {
            return nil
        }
        return CompositionHostSession(adapter: adapter, timelineView: timeline, viewerView: viewer)
    }

    private static func object(_ controller: UIViewController, selector name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard controller.responds(to: selector) else { return nil }
        return controller.perform(selector)?.takeUnretainedValue()
    }

    @MainActor
    private final class SelectorCompositionHostAdapter: CompositionHostMutationAdapter {
        private weak var controller: UIViewController?
        let verifiedCapabilities: Set<CompositionHostCapability>
        let supportedBlendModeIDs: Set<String>
        private(set) var selectionIdentity: String

        init?(controller: UIViewController) {
            self.controller = controller
            guard let raw = CompositionHostBridge.object(controller, selector: SelectorName.capabilities) as? [String] else {
                return nil
            }
            let capabilities = Set(raw.compactMap(CompositionHostCapability.init(rawValue:)))
            guard capabilities.contains(.readSelection),
                  capabilities.contains(.readLayerIdentity),
                  capabilities.contains(.readComposition),
                  capabilities.contains(.invalidatePreview) else {
                return nil
            }
            if capabilities.contains(.blendModes) {
                guard let rawIDs = CompositionHostBridge.object(
                    controller,
                    selector: SelectorName.supportedBlendModes
                ) as? [String] else { return nil }
                let verifiedIDs = Set(rawIDs.filter { BlendModeCatalogue.descriptor(id: $0) != nil })
                guard !verifiedIDs.isEmpty else { return nil }
                supportedBlendModeIDs = verifiedIDs
            } else {
                supportedBlendModeIDs = []
            }
            verifiedCapabilities = capabilities
            selectionIdentity = ""
            guard let initial = snapshot(), initial.hasStableSelection else { return nil }
            selectionIdentity = initial.selectionIdentity
        }

        func snapshot() -> HostCompositionSnapshot? {
            guard let controller,
                  let data = CompositionHostBridge.object(controller, selector: SelectorName.snapshot) as? Data,
                  let value = try? JSONDecoder().decode(HostCompositionSnapshot.self, from: data),
                  value.hasStableSelection else { return nil }
            selectionIdentity = value.selectionIdentity
            return value
        }

        func readCompositionDocument() -> CompositionDocument? {
            guard let controller,
                  let data = CompositionHostBridge.object(controller, selector: SelectorName.document) as? Data,
                  let document = try? JSONDecoder().decode(CompositionDocument.self, from: data),
                  (try? CompositionValidator.validate(document)) != nil else { return nil }
            return document
        }

        func setSelectedLayerIDs(_ ids: [UUID]) -> Bool {
            guard verifiedCapabilities.contains(.mutateSelection),
                  let data = try? JSONEncoder().encode(ids) else { return false }
            return callBoolean(SelectorName.setSelection, object: data)
        }

        func preview(document: CompositionDocument) -> Bool {
            guard verifiedCapabilities.contains(.previewComposition),
                  let data = try? JSONEncoder().encode(document) else { return false }
            return callBoolean(SelectorName.preview, object: data)
        }

        func commit(intent: CompositionCommandIntent) -> Bool {
            guard let data = try? JSONEncoder().encode(intent) else { return false }
            let committed = callBoolean(SelectorName.commit, object: data)
            if committed { invalidatePreview() }
            return committed
        }

        func rollback() -> Bool {
            let restored = callBoolean(SelectorName.rollback, object: nil)
            if restored { invalidatePreview() }
            return restored
        }

        func invalidatePreview() {
            guard let controller else { return }
            let selector = NSSelectorFromString(SelectorName.invalidate)
            guard controller.responds(to: selector) else { return }
            _ = controller.perform(selector)
        }

        func verifyPostcondition(for intent: CompositionCommandIntent) -> Bool {
            guard let data = try? JSONEncoder().encode(intent),
                  callBoolean(SelectorName.verify, object: data),
                  let nativeDocument = readCompositionDocument() else { return false }
            return nativeDocument == intent.finalDocument
        }

        private func callBoolean(_ selectorName: String, object: AnyObject?) -> Bool {
            guard let controller else { return false }
            let selector = NSSelectorFromString(selectorName)
            guard controller.responds(to: selector) else { return false }
            let result: Unmanaged<AnyObject>?
            if let object {
                result = controller.perform(selector, with: object)
            } else {
                result = controller.perform(selector)
            }
            return (result?.takeUnretainedValue() as? NSNumber)?.boolValue == true
        }
    }
}
#endif
