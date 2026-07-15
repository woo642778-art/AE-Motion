import Foundation

public enum PrecomposeError: Error, Equatable {
    case compositionNotFound(UUID)
    case requiresAtLeastTwoLayers
    case selectedLayerMissing(UUID)
    case emptyName
    case invalidSelection
    case relationshipCrossesSelectionBoundary(layerID: UUID, relatedLayerID: UUID)
}

public struct PrecomposeRequest: Equatable, Sendable {
    public var compositionID: UUID
    public var selectedLayerIDs: [UUID]
    public var name: String

    public init(compositionID: UUID, selectedLayerIDs: [UUID], name: String) {
        self.compositionID = compositionID
        self.selectedLayerIDs = selectedLayerIDs
        self.name = name
    }
}

public struct PrecomposeResult: Equatable, Sendable {
    public var document: CompositionDocument
    public var childComposition: Composition
    public var precompLayer: CompositionLayer
    public var originalDocument: CompositionDocument

    public init(
        document: CompositionDocument,
        childComposition: Composition,
        precompLayer: CompositionLayer,
        originalDocument: CompositionDocument
    ) {
        self.document = document
        self.childComposition = childComposition
        self.precompLayer = precompLayer
        self.originalDocument = originalDocument
    }
}

public enum PrecomposeEngine {
    public static func precompose(
        document: CompositionDocument,
        request: PrecomposeRequest
    ) throws -> PrecomposeResult {
        try CompositionValidator.validate(document)
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PrecomposeError.emptyName }

        let selectedIDs = orderPreservingUnique(request.selectedLayerIDs)
        guard selectedIDs.count >= 2 else { throw PrecomposeError.requiresAtLeastTwoLayers }
        guard let compositionIndex = document.compositions.firstIndex(where: { $0.id == request.compositionID }) else {
            throw PrecomposeError.compositionNotFound(request.compositionID)
        }

        let source = document.compositions[compositionIndex]
        let selectedSet = Set(selectedIDs)
        for id in selectedIDs where !source.layers.contains(where: { $0.id == id }) {
            throw PrecomposeError.selectedLayerMissing(id)
        }
        try validateClosedRelationshipBoundary(layers: source.layers, selected: selectedSet)

        let selected = source.layers.filter { selectedSet.contains($0.id) }
        guard let start = selected.map(\.timeRange.start).min(),
              let end = selected.map(\.timeRange.end).max(),
              start.isFinite,
              end.isFinite,
              end >= start else {
            throw PrecomposeError.invalidSelection
        }

        let movedLayers = selected.map { layer -> CompositionLayer in
            var moved = layer
            moved.timeRange.start -= start
            return moved
        }
        let child = Composition(
            name: name,
            duration: end - start,
            frameRate: source.frameRate,
            width: source.width,
            height: source.height,
            layers: movedLayers
        )
        let precompLayer = CompositionLayer(
            name: name,
            kind: .precomposition(child.id),
            timeRange: .init(start: start, duration: end - start),
            transform: .identity
        )

        guard let firstSelectedIndex = source.layers.firstIndex(where: { selectedSet.contains($0.id) }) else {
            throw PrecomposeError.invalidSelection
        }
        let insertionIndex = source.layers[..<firstSelectedIndex].filter { !selectedSet.contains($0.id) }.count
        var parentLayers = source.layers.filter { !selectedSet.contains($0.id) }
        parentLayers.insert(precompLayer, at: insertionIndex)

        var updated = document
        updated.compositions[compositionIndex].layers = parentLayers
        updated.compositions.append(child)
        try CompositionValidator.validate(updated)

        return PrecomposeResult(
            document: updated,
            childComposition: child,
            precompLayer: precompLayer,
            originalDocument: document
        )
    }

    private static func orderPreservingUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func validateClosedRelationshipBoundary(
        layers: [CompositionLayer],
        selected: Set<UUID>
    ) throws {
        for layer in layers {
            let layerIsSelected = selected.contains(layer.id)
            for relatedID in [layer.parent?.parentLayerID, layer.matte?.sourceLayerID].compactMap({ $0 }) {
                guard layerIsSelected == selected.contains(relatedID) else {
                    throw PrecomposeError.relationshipCrossesSelectionBoundary(
                        layerID: layer.id,
                        relatedLayerID: relatedID
                    )
                }
            }
        }
    }
}
