import Foundation

public struct AffineTransform2D: Codable, Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func rotation(radians: Double) -> AffineTransform2D {
        let cosine = cos(radians)
        let sine = sin(radians)
        return AffineTransform2D(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    public static func scale(x: Double, y: Double) -> AffineTransform2D {
        AffineTransform2D(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public static func skewX(radians: Double) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: tan(radians), d: 1, tx: 0, ty: 0)
    }

    public var determinant: Double { a * d - b * c }

    public func concatenating(_ rhs: AffineTransform2D) -> AffineTransform2D {
        AffineTransform2D(
            a: a * rhs.a + c * rhs.b,
            b: b * rhs.a + d * rhs.b,
            c: a * rhs.c + c * rhs.d,
            d: b * rhs.c + d * rhs.d,
            tx: a * rhs.tx + c * rhs.ty + tx,
            ty: b * rhs.tx + d * rhs.ty + ty
        )
    }

    public func inverted(epsilon: Double = 1e-12) -> AffineTransform2D? {
        let determinant = determinant
        guard determinant.isFinite, abs(determinant) > epsilon else { return nil }
        return AffineTransform2D(
            a: d / determinant,
            b: -b / determinant,
            c: -c / determinant,
            d: a / determinant,
            tx: (c * ty - d * tx) / determinant,
            ty: (b * tx - a * ty) / determinant
        )
    }

    public var isFinite: Bool {
        [a, b, c, d, tx, ty].allSatisfy(\.isFinite)
    }
}

public struct ResolvedCompositionTransform: Equatable, Sendable {
    public var matrix: AffineTransform2D
    public var opacity: Double

    public init(matrix: AffineTransform2D, opacity: Double) {
        self.matrix = matrix
        self.opacity = opacity
    }
}

public enum CompositionGraphError: Error, Equatable {
    case missingLayer(UUID)
    case invalidSelfReference
    case dependencyCycle
    case singularTransform(UUID)
    case singularOpacity(UUID)
    case nonFiniteTransform(UUID)
}

public struct CompositionGraph: Equatable, Sendable {
    public private(set) var composition: Composition

    public init(composition: Composition) throws {
        self.composition = composition
        try validateRelationships()
    }

    public func layer(id: UUID) -> CompositionLayer? {
        composition.layers.first { $0.id == id }
    }

    public func matteConsumers(sourceLayerID: UUID) -> [UUID] {
        composition.layers.compactMap { layer in
            layer.matte?.sourceLayerID == sourceLayerID ? layer.id : nil
        }
    }

    public func resolvedWorldTransform(layerID: UUID) throws -> ResolvedCompositionTransform {
        try resolvedWorldTransform(layerID: layerID, visiting: [])
    }

    public mutating func setParent(
        layerID: UUID,
        parentID: UUID?,
        preserveWorldTransform: Bool
    ) throws {
        guard layerID != parentID else { throw CompositionGraphError.invalidSelfReference }
        guard let childIndex = composition.layers.firstIndex(where: { $0.id == layerID }) else {
            throw CompositionGraphError.missingLayer(layerID)
        }
        if let parentID, layer(id: parentID) == nil {
            throw CompositionGraphError.missingLayer(parentID)
        }

        let original = composition
        let worldBefore = preserveWorldTransform ? try resolvedWorldTransform(layerID: layerID) : nil
        composition.layers[childIndex].parent = parentID.map(ParentBinding.init(parentLayerID:))

        do {
            try validateRelationships()
            if let worldBefore {
                let parentWorld: ResolvedCompositionTransform
                if let parentID {
                    parentWorld = try resolvedWorldTransform(layerID: parentID)
                } else {
                    parentWorld = ResolvedCompositionTransform(matrix: .identity, opacity: 1)
                }
                guard let parentInverse = parentWorld.matrix.inverted() else {
                    throw CompositionGraphError.singularTransform(parentID ?? layerID)
                }
                guard abs(parentWorld.opacity) > 1e-12 else {
                    throw CompositionGraphError.singularOpacity(parentID ?? layerID)
                }

                let localMatrix = parentInverse.concatenating(worldBefore.matrix)
                let anchorX = composition.layers[childIndex].transform.anchorX
                let anchorY = composition.layers[childIndex].transform.anchorY
                var local = try Self.decompose(
                    localMatrix,
                    anchorX: anchorX,
                    anchorY: anchorY,
                    layerID: layerID
                )
                local.opacity = worldBefore.opacity / parentWorld.opacity
                guard local.opacity.isFinite else {
                    throw CompositionGraphError.nonFiniteTransform(layerID)
                }
                composition.layers[childIndex].transform = local
            }
            try validateRelationships()
        } catch {
            composition = original
            throw error
        }
    }

    public mutating func setMatte(layerID: UUID, binding: MatteBinding?) throws {
        guard let index = composition.layers.firstIndex(where: { $0.id == layerID }) else {
            throw CompositionGraphError.missingLayer(layerID)
        }
        if let sourceID = binding?.sourceLayerID {
            guard sourceID != layerID else { throw CompositionGraphError.invalidSelfReference }
            guard layer(id: sourceID) != nil else { throw CompositionGraphError.missingLayer(sourceID) }
        }

        let original = composition
        composition.layers[index].matte = binding
        do {
            try validateRelationships()
        } catch {
            composition = original
            throw error
        }
    }

    private func resolvedWorldTransform(
        layerID: UUID,
        visiting: Set<UUID>
    ) throws -> ResolvedCompositionTransform {
        guard let layer = layer(id: layerID) else { throw CompositionGraphError.missingLayer(layerID) }
        guard !visiting.contains(layerID) else { throw CompositionGraphError.dependencyCycle }
        let localMatrix = Self.matrix(for: layer.transform)
        guard localMatrix.isFinite, layer.transform.opacity.isFinite else {
            throw CompositionGraphError.nonFiniteTransform(layerID)
        }

        guard let parentID = layer.parent?.parentLayerID else {
            return ResolvedCompositionTransform(matrix: localMatrix, opacity: layer.transform.opacity)
        }
        let parent = try resolvedWorldTransform(layerID: parentID, visiting: visiting.union([layerID]))
        return ResolvedCompositionTransform(
            matrix: parent.matrix.concatenating(localMatrix),
            opacity: parent.opacity * layer.transform.opacity
        )
    }

    private func validateRelationships() throws {
        let layerIDs = Set(composition.layers.map(\.id))
        for layer in composition.layers {
            if let parentID = layer.parent?.parentLayerID {
                guard parentID != layer.id else { throw CompositionGraphError.invalidSelfReference }
                guard layerIDs.contains(parentID) else { throw CompositionGraphError.missingLayer(parentID) }
            }
            if let matteID = layer.matte?.sourceLayerID {
                guard matteID != layer.id else { throw CompositionGraphError.invalidSelfReference }
                guard layerIDs.contains(matteID) else { throw CompositionGraphError.missingLayer(matteID) }
            }
            _ = try resolvedWorldTransform(layerID: layer.id)
        }

        var permanent = Set<UUID>()
        var temporary = Set<UUID>()
        func visit(_ id: UUID) throws {
            if permanent.contains(id) { return }
            guard temporary.insert(id).inserted else { throw CompositionGraphError.dependencyCycle }
            guard let current = layer(id: id) else { throw CompositionGraphError.missingLayer(id) }
            if let parentID = current.parent?.parentLayerID { try visit(parentID) }
            if let matteID = current.matte?.sourceLayerID { try visit(matteID) }
            temporary.remove(id)
            permanent.insert(id)
        }
        for layer in composition.layers { try visit(layer.id) }
    }

    private static func matrix(for transform: CompositionTransform) -> AffineTransform2D {
        let radians = transform.rotationDegrees * .pi / 180
        let skewRadians = transform.skewDegrees * .pi / 180
        return AffineTransform2D.translation(x: transform.positionX, y: transform.positionY)
            .concatenating(.rotation(radians: radians))
            .concatenating(.skewX(radians: skewRadians))
            .concatenating(.scale(x: transform.scaleX, y: transform.scaleY))
            .concatenating(.translation(x: -transform.anchorX, y: -transform.anchorY))
    }

    private static func decompose(
        _ matrix: AffineTransform2D,
        anchorX: Double,
        anchorY: Double,
        layerID: UUID
    ) throws -> CompositionTransform {
        guard matrix.isFinite else { throw CompositionGraphError.nonFiniteTransform(layerID) }
        let scaleX = hypot(matrix.a, matrix.b)
        guard scaleX > 1e-12 else { throw CompositionGraphError.singularTransform(layerID) }

        let cosine = matrix.a / scaleX
        let sine = matrix.b / scaleX
        let shearTimesScaleY = cosine * matrix.c + sine * matrix.d
        let scaleY = -sine * matrix.c + cosine * matrix.d
        guard abs(scaleY) > 1e-12 else { throw CompositionGraphError.singularTransform(layerID) }

        let rotation = atan2(sine, cosine)
        let skew = atan(shearTimesScaleY / scaleY)
        let positionX = matrix.tx + matrix.a * anchorX + matrix.c * anchorY
        let positionY = matrix.ty + matrix.b * anchorX + matrix.d * anchorY

        return CompositionTransform(
            positionX: positionX,
            positionY: positionY,
            anchorX: anchorX,
            anchorY: anchorY,
            scaleX: scaleX,
            scaleY: scaleY,
            rotationDegrees: rotation * 180 / .pi,
            skewDegrees: skew * 180 / .pi,
            opacity: 1
        )
    }
}
