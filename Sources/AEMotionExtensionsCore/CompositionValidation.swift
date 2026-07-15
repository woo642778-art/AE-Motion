import Foundation

public enum CompositionValidationError: Error, Equatable {
    case missingRootComposition(UUID)
    case duplicateIdentifier(UUID)
    case invalidComposition(UUID)
    case invalidLayerTimeRange(UUID)
    case missingMatteSource(layerID: UUID, sourceID: UUID)
    case missingParent(layerID: UUID, parentID: UUID)
    case missingPrecomposition(layerID: UUID, compositionID: UUID)
    case invalidLayerDependency(UUID)
    case compositionDependencyCycle
}

public enum CompositionValidator {
    public static func validate(_ document: CompositionDocument) throws {
        let compositionIDs = Set(document.compositions.map(\.id))
        guard compositionIDs.contains(document.rootCompositionID) else {
            throw CompositionValidationError.missingRootComposition(document.rootCompositionID)
        }

        var identifiers = Set<UUID>()
        for composition in document.compositions {
            guard identifiers.insert(composition.id).inserted else {
                throw CompositionValidationError.duplicateIdentifier(composition.id)
            }
            guard composition.duration.isFinite,
                  composition.duration >= 0,
                  composition.frameRate.isFinite,
                  composition.frameRate > 0,
                  composition.width > 0,
                  composition.height > 0 else {
                throw CompositionValidationError.invalidComposition(composition.id)
            }

            let layerIDs = Set(composition.layers.map(\.id))
            for layer in composition.layers {
                guard identifiers.insert(layer.id).inserted else {
                    throw CompositionValidationError.duplicateIdentifier(layer.id)
                }
                guard layer.timeRange.start.isFinite,
                      layer.timeRange.duration.isFinite,
                      layer.timeRange.duration >= 0 else {
                    throw CompositionValidationError.invalidLayerTimeRange(layer.id)
                }
                if let matte = layer.matte, !layerIDs.contains(matte.sourceLayerID) {
                    throw CompositionValidationError.missingMatteSource(
                        layerID: layer.id,
                        sourceID: matte.sourceLayerID
                    )
                }
                if let parent = layer.parent, !layerIDs.contains(parent.parentLayerID) {
                    throw CompositionValidationError.missingParent(
                        layerID: layer.id,
                        parentID: parent.parentLayerID
                    )
                }
                if case let .precomposition(compositionID) = layer.kind,
                   !compositionIDs.contains(compositionID) {
                    throw CompositionValidationError.missingPrecomposition(
                        layerID: layer.id,
                        compositionID: compositionID
                    )
                }
            }
            do {
                _ = try CompositionGraph(composition: composition)
            } catch {
                throw CompositionValidationError.invalidLayerDependency(composition.id)
            }
        }

        let compositionByID = Dictionary(uniqueKeysWithValues: document.compositions.map { ($0.id, $0) })
        var permanent = Set<UUID>()
        var temporary = Set<UUID>()
        func visit(_ compositionID: UUID) throws {
            if permanent.contains(compositionID) { return }
            guard temporary.insert(compositionID).inserted else {
                throw CompositionValidationError.compositionDependencyCycle
            }
            guard let composition = compositionByID[compositionID] else {
                throw CompositionValidationError.missingRootComposition(compositionID)
            }
            for layer in composition.layers {
                if case let .precomposition(childID) = layer.kind {
                    try visit(childID)
                }
            }
            temporary.remove(compositionID)
            permanent.insert(compositionID)
        }
        for composition in document.compositions {
            try visit(composition.id)
        }
    }
}
