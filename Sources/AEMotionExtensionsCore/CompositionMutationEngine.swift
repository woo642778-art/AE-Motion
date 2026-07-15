import Foundation

public enum CompositionMutationError: Error, Equatable {
    case compositionNotFound(UUID)
    case layerNotFound(UUID)
    case unsupportedBlendMode(String)
    case emptySelection
    case emptyName
}

public enum CompositionMutationEngine {
    public static func setBlendMode(
        _ modeID: String,
        layerIDs: [UUID],
        compositionID: UUID,
        document: inout CompositionDocument
    ) throws {
        guard BlendModeCatalogue.descriptor(id: modeID) != nil else {
            throw CompositionMutationError.unsupportedBlendMode(modeID)
        }
        try mutateLayers(layerIDs: layerIDs, compositionID: compositionID, document: &document) {
            $0.blendModeID = modeID
        }
    }

    public static func setChannelMapping(
        _ mapping: ChannelMapping,
        alphaInterpretation: AlphaInterpretation,
        invertAlpha: Bool,
        layerIDs: [UUID],
        compositionID: UUID,
        document: inout CompositionDocument
    ) throws {
        try mutateLayers(layerIDs: layerIDs, compositionID: compositionID, document: &document) { layer in
            layer.channelMapping = mapping
            layer.alphaInterpretation = alphaInterpretation
            layer.isAlphaInverted = invertAlpha
        }
    }

    public static func setParent(
        _ parentID: UUID?,
        layerIDs: [UUID],
        compositionID: UUID,
        document: inout CompositionDocument
    ) throws {
        guard !layerIDs.isEmpty else { throw CompositionMutationError.emptySelection }
        var candidate = document
        let index = try compositionIndex(compositionID, in: candidate)
        var graph = try CompositionGraph(composition: candidate.compositions[index])
        for layerID in orderPreservingUnique(layerIDs) {
            guard graph.layer(id: layerID) != nil else { throw CompositionMutationError.layerNotFound(layerID) }
            try graph.setParent(layerID: layerID, parentID: parentID, preserveWorldTransform: true)
        }
        candidate.compositions[index] = graph.composition
        try CompositionValidator.validate(candidate)
        document = candidate
    }

    public static func setMatte(
        _ binding: MatteBinding?,
        layerIDs: [UUID],
        compositionID: UUID,
        document: inout CompositionDocument
    ) throws {
        guard !layerIDs.isEmpty else { throw CompositionMutationError.emptySelection }
        var candidate = document
        let index = try compositionIndex(compositionID, in: candidate)
        var graph = try CompositionGraph(composition: candidate.compositions[index])
        for layerID in orderPreservingUnique(layerIDs) {
            guard graph.layer(id: layerID) != nil else { throw CompositionMutationError.layerNotFound(layerID) }
            try graph.setMatte(layerID: layerID, binding: binding)
        }
        candidate.compositions[index] = graph.composition
        try CompositionValidator.validate(candidate)
        document = candidate
    }

    @discardableResult
    public static func addNull(
        name: String,
        timeRange: CompositionTimeRange,
        compositionID: UUID,
        document: inout CompositionDocument
    ) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CompositionMutationError.emptyName }
        var candidate = document
        let index = try compositionIndex(compositionID, in: candidate)
        let layer = CompositionLayer(name: trimmed, kind: .null, timeRange: timeRange)
        candidate.compositions[index].layers.append(layer)
        try CompositionValidator.validate(candidate)
        document = candidate
        return layer.id
    }

    private static func mutateLayers(
        layerIDs: [UUID],
        compositionID: UUID,
        document: inout CompositionDocument,
        mutation: (inout CompositionLayer) throws -> Void
    ) throws {
        let ids = orderPreservingUnique(layerIDs)
        guard !ids.isEmpty else { throw CompositionMutationError.emptySelection }
        var candidate = document
        let compositionIndex = try compositionIndex(compositionID, in: candidate)
        for id in ids {
            guard let layerIndex = candidate.compositions[compositionIndex].layers.firstIndex(where: { $0.id == id }) else {
                throw CompositionMutationError.layerNotFound(id)
            }
            try mutation(&candidate.compositions[compositionIndex].layers[layerIndex])
        }
        try CompositionValidator.validate(candidate)
        document = candidate
    }

    private static func compositionIndex(_ id: UUID, in document: CompositionDocument) throws -> Int {
        guard let index = document.compositions.firstIndex(where: { $0.id == id }) else {
            throw CompositionMutationError.compositionNotFound(id)
        }
        return index
    }

    private static func orderPreservingUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
