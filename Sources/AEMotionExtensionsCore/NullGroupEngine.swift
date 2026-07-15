import Foundation

public enum NullGroupError: Error, Equatable {
    case compositionNotFound(UUID)
    case emptySelection
    case selectedLayerMissing(UUID)
    case emptyName
    case invalidTimeRange
}

public struct NullGroupRequest: Equatable, Sendable {
    public var compositionID: UUID
    public var selectedLayerIDs: [UUID]
    public var name: String

    public init(compositionID: UUID, selectedLayerIDs: [UUID], name: String) {
        self.compositionID = compositionID
        self.selectedLayerIDs = selectedLayerIDs
        self.name = name
    }
}

public struct NullGroupResult: Equatable, Sendable {
    public var document: CompositionDocument
    public var nullLayer: CompositionLayer
    public var originalDocument: CompositionDocument

    public init(
        document: CompositionDocument,
        nullLayer: CompositionLayer,
        originalDocument: CompositionDocument
    ) {
        self.document = document
        self.nullLayer = nullLayer
        self.originalDocument = originalDocument
    }
}

public enum NullGroupEngine {
    public static func group(
        document: CompositionDocument,
        request: NullGroupRequest
    ) throws -> NullGroupResult {
        try CompositionValidator.validate(document)
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NullGroupError.emptyName }
        let selectedIDs = orderPreservingUnique(request.selectedLayerIDs)
        guard !selectedIDs.isEmpty else { throw NullGroupError.emptySelection }
        guard let compositionIndex = document.compositions.firstIndex(where: { $0.id == request.compositionID }) else {
            throw NullGroupError.compositionNotFound(request.compositionID)
        }

        let source = document.compositions[compositionIndex]
        for id in selectedIDs where !source.layers.contains(where: { $0.id == id }) {
            throw NullGroupError.selectedLayerMissing(id)
        }
        let selectedSet = Set(selectedIDs)
        let selectedLayers = source.layers.filter { selectedSet.contains($0.id) }
        guard let start = selectedLayers.map(\.timeRange.start).min(),
              let end = selectedLayers.map(\.timeRange.end).max(),
              start.isFinite,
              end.isFinite,
              end >= start else {
            throw NullGroupError.invalidTimeRange
        }
        guard let insertionIndex = source.layers.firstIndex(where: { selectedSet.contains($0.id) }) else {
            throw NullGroupError.emptySelection
        }

        let graph = try CompositionGraph(composition: source)
        let worldTransforms = try selectedLayers.map { try graph.resolvedWorldTransform(layerID: $0.id) }
        let positionX = worldTransforms.map(\.matrix.tx).reduce(0, +) / Double(worldTransforms.count)
        let positionY = worldTransforms.map(\.matrix.ty).reduce(0, +) / Double(worldTransforms.count)
        let nullTransform = CompositionTransform(positionX: positionX, positionY: positionY)

        var updated = document
        let nullID = try CompositionMutationEngine.addNull(
            name: name,
            timeRange: .init(start: start, duration: end - start),
            transform: nullTransform,
            insertionIndex: insertionIndex,
            compositionID: request.compositionID,
            document: &updated
        )
        try CompositionMutationEngine.setParent(
            nullID,
            layerIDs: selectedIDs,
            compositionID: request.compositionID,
            document: &updated
        )
        try CompositionValidator.validate(updated)
        guard let nullLayer = updated.compositions[compositionIndex].layers.first(where: { $0.id == nullID }) else {
            throw NullGroupError.selectedLayerMissing(nullID)
        }
        return NullGroupResult(
            document: updated,
            nullLayer: nullLayer,
            originalDocument: document
        )
    }

    private static func orderPreservingUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
