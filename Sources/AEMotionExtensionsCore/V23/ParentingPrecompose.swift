import Foundation

public enum ParentingError: Error, Equatable, Sendable {
    case missingComposition(CompositionID)
    case missingLayer(LayerID)
    case missingParent(LayerID)
    case selfParent
    case cycle
    case singularParentTransform
}

public enum ParentingResolver {
    public static func worldMatrix(
        for layerID: LayerID,
        in document: CompositionDocument,
        compositionID: CompositionID? = nil
    ) throws -> AffineTransform2D {
        let targetCompositionID = compositionID ?? document.rootCompositionID
        guard let composition = document.compositions[targetCompositionID] else {
            throw ParentingError.missingComposition(targetCompositionID)
        }
        let lookup = Dictionary(uniqueKeysWithValues: composition.layers.map { ($0.id, $0) })
        var active = Set<LayerID>()

        func resolve(_ id: LayerID) throws -> AffineTransform2D {
            guard let layer = lookup[id] else { throw ParentingError.missingLayer(id) }
            guard active.insert(id).inserted else { throw ParentingError.cycle }
            defer { active.remove(id) }
            guard let parentID = layer.parentID else { return layer.transform.localMatrix }
            guard lookup[parentID] != nil else { throw ParentingError.missingParent(parentID) }
            return try resolve(parentID).concatenating(layer.transform.localMatrix)
        }

        return try resolve(layerID)
    }

    public static func reparentPreservingWorldSpace(
        child childID: LayerID,
        newParent newParentID: LayerID?,
        document: CompositionDocument,
        compositionID: CompositionID? = nil
    ) throws -> CompositionDocument {
        let targetCompositionID = compositionID ?? document.rootCompositionID
        guard var composition = document.compositions[targetCompositionID] else {
            throw ParentingError.missingComposition(targetCompositionID)
        }
        guard let childIndex = composition.layers.firstIndex(where: { $0.id == childID }) else {
            throw ParentingError.missingLayer(childID)
        }
        if newParentID == childID { throw ParentingError.selfParent }
        if let newParentID, composition.layer(id: newParentID) == nil {
            throw ParentingError.missingParent(newParentID)
        }

        var probe = newParentID
        var visited = Set<LayerID>()
        while let current = probe {
            if current == childID { throw ParentingError.cycle }
            guard visited.insert(current).inserted else { throw ParentingError.cycle }
            probe = composition.layer(id: current)?.parentID
        }

        let oldWorld = try worldMatrix(for: childID, in: document, compositionID: targetCompositionID)
        let parentWorld: AffineTransform2D
        if let newParentID {
            parentWorld = try worldMatrix(for: newParentID, in: document, compositionID: targetCompositionID)
        } else {
            parentWorld = .identity
        }

        let inverse: AffineTransform2D
        do {
            inverse = try parentWorld.inverted()
        } catch {
            throw ParentingError.singularParentTransform
        }
        let newLocal = inverse.concatenating(oldWorld)
        let original = composition.layers[childIndex].transform
        composition.layers[childIndex].transform = try LayerTransform.decomposing(
            newLocal,
            preservingAnchorX: original.anchorX,
            anchorY: original.anchorY,
            opacity: original.opacity
        )
        composition.layers[childIndex].parentID = newParentID

        var result = document
        result.compositions[targetCompositionID] = composition
        return result
    }
}

public struct CompositionMutationResult: Equatable, Sendable {
    public let original: CompositionDocument
    public let updated: CompositionDocument
    public let affectedCompositionID: CompositionID
    public let createdCompositionID: CompositionID?
    public let replacementLayerID: LayerID?

    public init(
        original: CompositionDocument,
        updated: CompositionDocument,
        affectedCompositionID: CompositionID,
        createdCompositionID: CompositionID? = nil,
        replacementLayerID: LayerID? = nil
    ) {
        self.original = original
        self.updated = updated
        self.affectedCompositionID = affectedCompositionID
        self.createdCompositionID = createdCompositionID
        self.replacementLayerID = replacementLayerID
    }

    public func inverseDocument() -> CompositionDocument { original }
}

public enum PrecomposeCommandError: Error, Equatable, Sendable {
    case missingComposition(CompositionID)
    case requiresAtLeastTwoLayers
    case duplicateSelection(LayerID)
    case missingLayer(LayerID)
    case splitMatteDependency(layer: LayerID, matte: LayerID)
    case invalidResult(CompositionGraphValidationError)
}

public enum PrecomposeCommand {
    public static func apply(
        selection: [LayerID],
        name: String,
        in compositionID: CompositionID? = nil,
        to document: CompositionDocument
    ) throws -> CompositionMutationResult {
        let targetCompositionID = compositionID ?? document.rootCompositionID
        guard let originalComposition = document.compositions[targetCompositionID] else {
            throw PrecomposeCommandError.missingComposition(targetCompositionID)
        }
        guard selection.count >= 2 else { throw PrecomposeCommandError.requiresAtLeastTwoLayers }

        var selectedIDs = Set<LayerID>()
        for id in selection {
            guard selectedIDs.insert(id).inserted else { throw PrecomposeCommandError.duplicateSelection(id) }
            guard originalComposition.layer(id: id) != nil else { throw PrecomposeCommandError.missingLayer(id) }
        }

        try validateMatteClosure(in: originalComposition, selectedIDs: selectedIDs)

        let selectedEntries = originalComposition.layers.enumerated().filter { selectedIDs.contains($0.element.id) }
        guard let firstIndex = selectedEntries.map(\.offset).min(),
              let earliest = selectedEntries.map({ $0.element.timeRange.start }).min(),
              let latest = selectedEntries.map({ $0.element.timeRange.end }).max() else {
            throw PrecomposeCommandError.requiresAtLeastTwoLayers
        }

        let duration = latest - earliest
        let childID = CompositionID()
        let replacementID = LayerID()
        let childRange = try CompositionTimeRange(start: 0, duration: duration)
        let replacementRange = try CompositionTimeRange(start: earliest, duration: duration)

        var selectedLayers: [CompositionLayer] = []
        for (_, originalLayer) in selectedEntries {
            var layer = originalLayer
            layer.timeRange = try CompositionTimeRange(
                start: originalLayer.timeRange.start - earliest,
                duration: originalLayer.timeRange.duration
            )
            if let parentID = originalLayer.parentID, !selectedIDs.contains(parentID) {
                let world = try ParentingResolver.worldMatrix(
                    for: originalLayer.id,
                    in: document,
                    compositionID: targetCompositionID
                )
                layer.transform = try LayerTransform.decomposing(
                    world,
                    preservingAnchorX: originalLayer.transform.anchorX,
                    anchorY: originalLayer.transform.anchorY,
                    opacity: originalLayer.transform.opacity
                )
                layer.parentID = nil
            }
            selectedLayers.append(layer)
        }

        var remainingLayers: [CompositionLayer] = []
        for originalLayer in originalComposition.layers where !selectedIDs.contains(originalLayer.id) {
            var layer = originalLayer
            if let parentID = layer.parentID, selectedIDs.contains(parentID) {
                let world = try ParentingResolver.worldMatrix(
                    for: layer.id,
                    in: document,
                    compositionID: targetCompositionID
                )
                layer.transform = try LayerTransform.decomposing(
                    world,
                    preservingAnchorX: layer.transform.anchorX,
                    anchorY: layer.transform.anchorY,
                    opacity: layer.transform.opacity
                )
                layer.parentID = nil
            }
            remainingLayers.append(layer)
        }

        let insertionIndex = originalComposition.layers[..<firstIndex].filter { !selectedIDs.contains($0.id) }.count
        let replacement = CompositionLayer(
            id: replacementID,
            name: normalizedName(name),
            kind: .precomposition,
            sourceCompositionID: childID,
            timeRange: replacementRange,
            sourceTimeOffset: 0,
            transform: .identity,
            blendMode: "normal",
            isVisible: true,
            metadata: [
                "aemotion.precompose.autoTrim": "true",
                "aemotion.precompose.sourceLayerCount": String(selectedLayers.count),
            ]
        )
        remainingLayers.insert(replacement, at: min(insertionIndex, remainingLayers.count))

        let child = CompositionDefinition(
            id: childID,
            name: normalizedName(name),
            width: originalComposition.width,
            height: originalComposition.height,
            frameRate: originalComposition.frameRate,
            timeRange: childRange,
            layers: selectedLayers
        )
        var parent = originalComposition
        parent.layers = remainingLayers

        var updated = document
        updated.compositions[parent.id] = parent
        updated.compositions[child.id] = child

        if let error = CompositionGraphValidator.validate(updated).first {
            throw PrecomposeCommandError.invalidResult(error)
        }

        return CompositionMutationResult(
            original: document,
            updated: updated,
            affectedCompositionID: targetCompositionID,
            createdCompositionID: childID,
            replacementLayerID: replacementID
        )
    }

    private static func validateMatteClosure(
        in composition: CompositionDefinition,
        selectedIDs: Set<LayerID>
    ) throws {
        for layer in composition.layers {
            guard let matte = layer.trackMatte?.sourceLayerID else { continue }
            let targetSelected = selectedIDs.contains(layer.id)
            let matteSelected = selectedIDs.contains(matte)
            if targetSelected != matteSelected {
                throw PrecomposeCommandError.splitMatteDependency(layer: layer.id, matte: matte)
            }
        }
    }

    private static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Pre-comp" : trimmed
    }
}
