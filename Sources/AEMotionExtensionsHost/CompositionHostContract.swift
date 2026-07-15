#if canImport(UIKit)
import Foundation
import UIKit
import AEMotionExtensionsCore

@MainActor
enum CompositionHostCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case readSelection
    case readLayerIdentity
    case readComposition
    case mutateSelection
    case previewComposition
    case invalidatePreview
    case structuralPrecompose
    case structuralParenting
    case structuralMatte
    case blendModes
    case channelAlpha
}

struct HostTimelineFrame: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func contains(_ point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

struct HostLayerHandle: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let displayName: String
    let isLocked: Bool
    let isCompatible: Bool
    let timelineFrame: HostTimelineFrame?
}

struct HostCompositionSnapshot: Codable, Equatable, Sendable {
    let selectionIdentity: String
    let compositionID: UUID
    let layers: [HostLayerHandle]
    let selectedLayerIDs: [UUID]
    let playheadTime: Double
    let revision: UInt64

    var hasStableSelection: Bool {
        !selectionIdentity.isEmpty
            && Set(layers.map(\.id)).count == layers.count
            && Set(selectedLayerIDs).isSubset(of: Set(layers.map(\.id)))
            && playheadTime.isFinite
    }
}

@MainActor
protocol CompositionHostMutationAdapter: AnyObject {
    var verifiedCapabilities: Set<CompositionHostCapability> { get }
    var selectionIdentity: String { get }
    func snapshot() -> HostCompositionSnapshot?
    func readCompositionDocument() -> CompositionDocument?
    func setSelectedLayerIDs(_ ids: [UUID]) -> Bool
    func preview(document: CompositionDocument) -> Bool
    func commit(intent: CompositionCommandIntent) -> Bool
    func rollback() -> Bool
    func invalidatePreview()
    func verifyPostcondition(for intent: CompositionCommandIntent) -> Bool
}

@MainActor
final class CompositionHostSession {
    let adapter: CompositionHostMutationAdapter
    let timelineView: UIView
    let viewerView: UIView

    init(adapter: CompositionHostMutationAdapter, timelineView: UIView, viewerView: UIView) {
        self.adapter = adapter
        self.timelineView = timelineView
        self.viewerView = viewerView
    }
}
#endif
