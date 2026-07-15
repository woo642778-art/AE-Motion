import XCTest
@testable import AEMotionExtensionsCore

final class CompositionMutationTests: XCTestCase {
    func testBlendAndChannelMutationUpdatesOnlySelectedLayers() throws {
        let first = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 0, duration: 5))
        let second = CompositionLayer(name: "B", kind: .video, timeRange: .init(start: 0, duration: 5))
        let root = Composition(name: "Root", duration: 5, layers: [first, second])
        var document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        try CompositionMutationEngine.setBlendMode("screen", layerIDs: [first.id], compositionID: root.id, document: &document)
        try CompositionMutationEngine.setChannelMapping(
            .init(red: .blue, green: .green, blue: .red, alpha: .luminance),
            alphaInterpretation: .premultiplied,
            invertAlpha: true,
            layerIDs: [first.id],
            compositionID: root.id,
            document: &document
        )

        let changed = document.compositions[0].layers[0]
        let untouched = document.compositions[0].layers[1]
        XCTAssertEqual(changed.blendModeID, "screen")
        XCTAssertEqual(changed.channelMapping.alpha, .luminance)
        XCTAssertEqual(changed.alphaInterpretation, .premultiplied)
        XCTAssertTrue(changed.isAlphaInverted)
        XCTAssertEqual(untouched.blendModeID, "normal")
        XCTAssertFalse(untouched.isAlphaInverted)
    }

    func testParentMutationUsesWorldPreservingGraph() throws {
        let parent = CompositionLayer(name: "Null", kind: .null, timeRange: .init(start: 0, duration: 5), transform: .init(positionX: 50, positionY: 20, scaleX: 1.5, scaleY: 0.7, rotationDegrees: 30))
        let child = CompositionLayer(name: "Child", kind: .shape, timeRange: .init(start: 0, duration: 5), transform: .init(positionX: 20, positionY: 10, anchorX: 3, anchorY: 4, rotationDegrees: -8))
        let root = Composition(name: "Root", duration: 5, layers: [parent, child])
        var document = CompositionDocument(rootCompositionID: root.id, compositions: [root])
        let before = try CompositionGraph(composition: root).resolvedWorldTransform(layerID: child.id)

        try CompositionMutationEngine.setParent(parent.id, layerIDs: [child.id], compositionID: root.id, document: &document)

        let graph = try CompositionGraph(composition: document.compositions[0])
        let after = try graph.resolvedWorldTransform(layerID: child.id)
        XCTAssertEqual(after.matrix.a, before.matrix.a, accuracy: 0.000001)
        XCTAssertEqual(after.matrix.b, before.matrix.b, accuracy: 0.000001)
        XCTAssertEqual(after.matrix.c, before.matrix.c, accuracy: 0.000001)
        XCTAssertEqual(after.matrix.d, before.matrix.d, accuracy: 0.000001)
        XCTAssertEqual(after.matrix.tx, before.matrix.tx, accuracy: 0.000001)
        XCTAssertEqual(after.matrix.ty, before.matrix.ty, accuracy: 0.000001)
    }

    func testSharedMatteAndNullCreation() throws {
        let matte = CompositionLayer(name: "Matte", kind: .shape, timeRange: .init(start: 0, duration: 5))
        let first = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 0, duration: 5))
        let second = CompositionLayer(name: "B", kind: .video, timeRange: .init(start: 0, duration: 5))
        let root = Composition(name: "Root", duration: 5, layers: [matte, first, second])
        var document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        try CompositionMutationEngine.setMatte(
            .init(sourceLayerID: matte.id, mode: .lumaInverted),
            layerIDs: [first.id, second.id],
            compositionID: root.id,
            document: &document
        )
        let nullID = try CompositionMutationEngine.addNull(
            name: "Null 1",
            timeRange: .init(start: 1, duration: 3),
            compositionID: root.id,
            document: &document
        )

        XCTAssertEqual(document.compositions[0].layers[1].matte?.sourceLayerID, matte.id)
        XCTAssertEqual(document.compositions[0].layers[2].matte?.mode, .lumaInverted)
        XCTAssertEqual(document.compositions[0].layers.last?.id, nullID)
        XCTAssertEqual(document.compositions[0].layers.last?.kind, .null)
    }

    func testNullCanBeInsertedImmediatelyAboveSelectedLayers() throws {
        let background = CompositionLayer(name: "Background", kind: .image, timeRange: .init(start: 0, duration: 8))
        let first = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 2, duration: 3))
        let second = CompositionLayer(name: "B", kind: .shape, timeRange: .init(start: 3, duration: 4))
        let foreground = CompositionLayer(name: "Foreground", kind: .text, timeRange: .init(start: 0, duration: 8))
        let root = Composition(name: "Root", duration: 8, layers: [background, first, second, foreground])
        var document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        let nullID = try CompositionMutationEngine.addNull(
            name: "Null Group",
            timeRange: .init(start: 2, duration: 5),
            insertionIndex: 1,
            compositionID: root.id,
            document: &document
        )

        XCTAssertEqual(document.compositions[0].layers.map(\.id), [background.id, nullID, first.id, second.id, foreground.id])
    }

    func testUnknownBlendModeFailsWithoutMutation() {
        let layer = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 0, duration: 5))
        let root = Composition(name: "Root", duration: 5, layers: [layer])
        var document = CompositionDocument(rootCompositionID: root.id, compositions: [root])
        let before = document

        XCTAssertThrowsError(try CompositionMutationEngine.setBlendMode("missing", layerIDs: [layer.id], compositionID: root.id, document: &document)) {
            XCTAssertEqual($0 as? CompositionMutationError, .unsupportedBlendMode("missing"))
        }
        XCTAssertEqual(document, before)
    }
}
