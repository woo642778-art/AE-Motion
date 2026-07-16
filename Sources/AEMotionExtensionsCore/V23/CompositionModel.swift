import Foundation

public enum CompositionLayerKind: String, Codable, CaseIterable, Sendable {
    case media
    case text
    case shape
    case null
    case precomposition
}

public struct ScalarKeyframe: Codable, Equatable, Sendable {
    public var time: Double
    public var value: Double
    public var interpolation: String

    public init(time: Double, value: Double, interpolation: String = "linear") {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }
}

public struct CompositionLayer: Codable, Equatable, Sendable, Identifiable {
    public var id: LayerID
    public var name: String
    public var kind: CompositionLayerKind
    public var sourceCompositionID: CompositionID?
    public var timeRange: CompositionTimeRange
    public var sourceTimeOffset: Double
    public var transform: LayerTransform
    public var parentID: LayerID?
    public var trackMatte: TrackMatteBinding?
    public var blendMode: BlendModeID
    public var isVisible: Bool
    public var effectIDs: [String]
    public var keyframes: [String: [ScalarKeyframe]]
    public var metadata: [String: String]

    public init(
        id: LayerID = LayerID(),
        name: String,
        kind: CompositionLayerKind,
        sourceCompositionID: CompositionID? = nil,
        timeRange: CompositionTimeRange,
        sourceTimeOffset: Double = 0,
        transform: LayerTransform = .identity,
        parentID: LayerID? = nil,
        trackMatte: TrackMatteBinding? = nil,
        blendMode: BlendModeID = "normal",
        isVisible: Bool = true,
        effectIDs: [String] = [],
        keyframes: [String: [ScalarKeyframe]] = [:],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sourceCompositionID = sourceCompositionID
        self.timeRange = timeRange
        self.sourceTimeOffset = sourceTimeOffset
        self.transform = transform
        self.parentID = parentID
        self.trackMatte = trackMatte
        self.blendMode = blendMode
        self.isVisible = isVisible
        self.effectIDs = effectIDs
        self.keyframes = keyframes
        self.metadata = metadata
    }

    public static func null(
        name: String = "Null",
        timeRange: CompositionTimeRange,
        transform: LayerTransform = .identity
    ) -> CompositionLayer {
        CompositionLayer(name: name, kind: .null, timeRange: timeRange, transform: transform)
    }
}

public struct CompositionDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: CompositionID
    public var name: String
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var timeRange: CompositionTimeRange
    public var layers: [CompositionLayer]

    public init(
        id: CompositionID = CompositionID(),
        name: String,
        width: Int,
        height: Int,
        frameRate: Double,
        timeRange: CompositionTimeRange,
        layers: [CompositionLayer] = []
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.timeRange = timeRange
        self.layers = layers
    }

    public func layer(id: LayerID) -> CompositionLayer? {
        layers.first { $0.id == id }
    }
}

public struct CompositionDocument: Codable, Equatable, Sendable {
    public var rootCompositionID: CompositionID
    public var compositions: [CompositionID: CompositionDefinition]

    public init(root: CompositionDefinition, additionalCompositions: [CompositionDefinition] = []) {
        self.rootCompositionID = root.id
        self.compositions = Dictionary(uniqueKeysWithValues: ([root] + additionalCompositions).map { ($0.id, $0) })
    }

    public init(rootCompositionID: CompositionID, compositions: [CompositionID: CompositionDefinition]) {
        self.rootCompositionID = rootCompositionID
        self.compositions = compositions
    }

    public var root: CompositionDefinition? { compositions[rootCompositionID] }

    public func composition(id: CompositionID) -> CompositionDefinition? {
        compositions[id]
    }

    public func replacing(_ composition: CompositionDefinition) -> CompositionDocument {
        var copy = self
        copy.compositions[composition.id] = composition
        return copy
    }
}

public enum CompositionGraphValidationError: Error, Equatable, Sendable {
    case missingRoot(CompositionID)
    case invalidCanvas(CompositionID)
    case invalidFrameRate(CompositionID)
    case duplicateLayerID(composition: CompositionID, layer: LayerID)
    case missingParent(composition: CompositionID, layer: LayerID, parent: LayerID)
    case missingMatte(composition: CompositionID, layer: LayerID, matte: LayerID)
    case selfReference(composition: CompositionID, layer: LayerID)
    case parentCycle(composition: CompositionID, layer: LayerID)
    case matteCycle(composition: CompositionID, layer: LayerID)
    case missingPrecomposition(composition: CompositionID, layer: LayerID, target: CompositionID)
    case invalidPrecompositionLayer(composition: CompositionID, layer: LayerID)
    case precompositionCycle(CompositionID)
}

public enum CompositionGraphValidator {
    public static func validate(_ document: CompositionDocument) -> [CompositionGraphValidationError] {
        guard document.compositions[document.rootCompositionID] != nil else {
            return [.missingRoot(document.rootCompositionID)]
        }

        var errors: [CompositionGraphValidationError] = []
        for definition in document.compositions.values {
            if definition.width <= 0 || definition.height <= 0 {
                errors.append(.invalidCanvas(definition.id))
            }
            if !definition.frameRate.isFinite || definition.frameRate <= 0 {
                errors.append(.invalidFrameRate(definition.id))
            }
            validateLayers(in: definition, document: document, errors: &errors)
        }
        errors.append(contentsOf: validatePrecompositionCycles(document))
        return errors
    }

    public static func validateOrThrow(_ document: CompositionDocument) throws {
        if let first = validate(document).first { throw first }
    }

    private static func validateLayers(
        in definition: CompositionDefinition,
        document: CompositionDocument,
        errors: inout [CompositionGraphValidationError]
    ) {
        var seen = Set<LayerID>()
        for layer in definition.layers {
            if !seen.insert(layer.id).inserted {
                errors.append(.duplicateLayerID(composition: definition.id, layer: layer.id))
            }
        }
        let ids = Set(definition.layers.map(\.id))
        for layer in definition.layers {
            if layer.parentID == layer.id || layer.trackMatte?.sourceLayerID == layer.id {
                errors.append(.selfReference(composition: definition.id, layer: layer.id))
            }
            if let parent = layer.parentID, !ids.contains(parent) {
                errors.append(.missingParent(composition: definition.id, layer: layer.id, parent: parent))
            }
            if let matte = layer.trackMatte?.sourceLayerID, !ids.contains(matte) {
                errors.append(.missingMatte(composition: definition.id, layer: layer.id, matte: matte))
            }
            if layer.kind == .precomposition {
                guard let target = layer.sourceCompositionID else {
                    errors.append(.invalidPrecompositionLayer(composition: definition.id, layer: layer.id))
                    continue
                }
                if document.compositions[target] == nil {
                    errors.append(.missingPrecomposition(composition: definition.id, layer: layer.id, target: target))
                }
            } else if layer.sourceCompositionID != nil {
                errors.append(.invalidPrecompositionLayer(composition: definition.id, layer: layer.id))
            }
        }

        errors.append(contentsOf: detectLayerCycles(
            definition: definition,
            edge: { $0.parentID },
            makeError: { .parentCycle(composition: definition.id, layer: $0) }
        ))
        errors.append(contentsOf: detectLayerCycles(
            definition: definition,
            edge: { $0.trackMatte?.sourceLayerID },
            makeError: { .matteCycle(composition: definition.id, layer: $0) }
        ))
    }

    private static func detectLayerCycles(
        definition: CompositionDefinition,
        edge: (CompositionLayer) -> LayerID?,
        makeError: (LayerID) -> CompositionGraphValidationError
    ) -> [CompositionGraphValidationError] {
        let lookup = Dictionary(uniqueKeysWithValues: definition.layers.map { ($0.id, $0) })
        var complete = Set<LayerID>()
        var active = Set<LayerID>()
        var errors: [CompositionGraphValidationError] = []

        func visit(_ id: LayerID) {
            if active.contains(id) {
                errors.append(makeError(id))
                return
            }
            guard !complete.contains(id), let layer = lookup[id] else { return }
            active.insert(id)
            if let next = edge(layer) { visit(next) }
            active.remove(id)
            complete.insert(id)
        }

        for id in lookup.keys { visit(id) }
        return errors
    }

    private static func validatePrecompositionCycles(_ document: CompositionDocument) -> [CompositionGraphValidationError] {
        let edges: [CompositionID: [CompositionID]] = document.compositions.mapValues { definition in
            definition.layers.compactMap { layer in
                layer.kind == .precomposition ? layer.sourceCompositionID : nil
            }
        }
        var complete = Set<CompositionID>()
        var active = Set<CompositionID>()
        var errors: [CompositionGraphValidationError] = []

        func visit(_ id: CompositionID) {
            if active.contains(id) {
                errors.append(.precompositionCycle(id))
                return
            }
            guard !complete.contains(id) else { return }
            active.insert(id)
            for next in edges[id, default: []] where document.compositions[next] != nil {
                visit(next)
            }
            active.remove(id)
            complete.insert(id)
        }

        for id in document.compositions.keys { visit(id) }
        return errors
    }
}
