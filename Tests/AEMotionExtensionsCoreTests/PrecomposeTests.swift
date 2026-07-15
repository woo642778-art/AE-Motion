import XCTest
@testable import AEMotionExtensionsCore

final class PrecomposeTests: XCTestCase {
    func testPrecomposeAutoTrimsPreservesOrderRelativeTimingAndProperties() throws {
        let background = CompositionLayer(name: "Background", kind: .image, timeRange: .init(start: 0, duration: 12))
        let first = CompositionLayer(
            name: "A",
            kind: .video,
            timeRange: .init(start: 2, duration: 3),
            transform: .init(positionX: 40, positionY: 50, anchorX: 3, anchorY: 4, scaleX: 1.2, scaleY: 0.8, rotationDegrees: 25, skewDegrees: 8, opacity: 0.7),
            blendModeID: "screen",
            alphaInterpretation: .premultiplied,
            channelMapping: .init(red: .blue, green: .green, blue: .red, alpha: .luminance),
            metadata: ["effect": "glow"]
        )
        var second = CompositionLayer(name: "B", kind: .shape, timeRange: .init(start: 4, duration: 4))
        second.parent = ParentBinding(parentLayerID: first.id)
        second.matte = MatteBinding(sourceLayerID: first.id, mode: .alphaInverted)
        let foreground = CompositionLayer(name: "Foreground", kind: .text, timeRange: .init(start: 1, duration: 9))
        let root = Composition(name: "Root", duration: 12, layers: [background, first, second, foreground])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        let result = try PrecomposeEngine.precompose(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [second.id, first.id], name: "Pre-comp 1")
        )

        XCTAssertEqual(result.childComposition.duration, 6)
        XCTAssertEqual(result.childComposition.layers.map(\.id), [first.id, second.id])
        XCTAssertEqual(result.childComposition.layers.map(\.timeRange.start), [0, 2])
        XCTAssertEqual(result.childComposition.layers[0].transform, first.transform)
        XCTAssertEqual(result.childComposition.layers[0].blendModeID, "screen")
        XCTAssertEqual(result.childComposition.layers[0].alphaInterpretation, .premultiplied)
        XCTAssertEqual(result.childComposition.layers[0].channelMapping, first.channelMapping)
        XCTAssertEqual(result.childComposition.layers[0].metadata, first.metadata)
        XCTAssertEqual(result.childComposition.layers[1].parent?.parentLayerID, first.id)
        XCTAssertEqual(result.childComposition.layers[1].matte?.sourceLayerID, first.id)
        XCTAssertEqual(result.precompLayer.timeRange, .init(start: 2, duration: 6))
        XCTAssertEqual(result.precompLayer.transform, .identity)
        XCTAssertEqual(result.document.compositions.count, 2)
        XCTAssertEqual(result.document.compositions[0].layers.map(\.name), ["Background", "Pre-comp 1", "Foreground"])
        XCTAssertEqual(result.originalDocument, document)
    }

    func testPrecomposeRequiresAtLeastTwoUniqueLayers() {
        let layer = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 0, duration: 1))
        let root = Composition(name: "Root", duration: 2, layers: [layer])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        XCTAssertThrowsError(try PrecomposeEngine.precompose(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [layer.id, layer.id], name: "Bad")
        )) {
            XCTAssertEqual($0 as? PrecomposeError, .requiresAtLeastTwoLayers)
        }
    }

    func testPrecomposeRejectsRelationshipCrossingSelectionBoundary() {
        let parent = CompositionLayer(name: "External Parent", kind: .null, timeRange: .init(start: 0, duration: 5))
        var child = CompositionLayer(name: "Child", kind: .video, timeRange: .init(start: 0, duration: 5))
        child.parent = ParentBinding(parentLayerID: parent.id)
        let peer = CompositionLayer(name: "Peer", kind: .shape, timeRange: .init(start: 0, duration: 5))
        let root = Composition(name: "Root", duration: 5, layers: [parent, child, peer])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        XCTAssertThrowsError(try PrecomposeEngine.precompose(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [child.id, peer.id], name: "Bad")
        )) {
            XCTAssertEqual(
                $0 as? PrecomposeError,
                .relationshipCrossesSelectionBoundary(layerID: child.id, relatedLayerID: parent.id)
            )
        }
    }

    func testPrecomposeRejectsUnselectedConsumerOfSelectedMatte() {
        let matte = CompositionLayer(name: "Matte", kind: .shape, timeRange: .init(start: 0, duration: 5))
        let peer = CompositionLayer(name: "Peer", kind: .shape, timeRange: .init(start: 0, duration: 5))
        let consumer = CompositionLayer(name: "Consumer", kind: .video, timeRange: .init(start: 0, duration: 5), matte: .init(sourceLayerID: matte.id, mode: .luma))
        let root = Composition(name: "Root", duration: 5, layers: [matte, peer, consumer])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])

        XCTAssertThrowsError(try PrecomposeEngine.precompose(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [matte.id, peer.id], name: "Bad")
        )) {
            XCTAssertEqual(
                $0 as? PrecomposeError,
                .relationshipCrossesSelectionBoundary(layerID: consumer.id, relatedLayerID: matte.id)
            )
        }
    }

    func testDocumentValidatorRejectsCompositionDependencyCycle() {
        let rootID = UUID()
        let childID = UUID()
        let rootLayer = CompositionLayer(name: "Child", kind: .precomposition(childID), timeRange: .init(start: 0, duration: 1))
        let childLayer = CompositionLayer(name: "Root", kind: .precomposition(rootID), timeRange: .init(start: 0, duration: 1))
        let root = Composition(id: rootID, name: "Root", duration: 1, layers: [rootLayer])
        let child = Composition(id: childID, name: "Child", duration: 1, layers: [childLayer])
        let document = CompositionDocument(rootCompositionID: rootID, compositions: [root, child])

        XCTAssertThrowsError(try CompositionValidator.validate(document)) {
            XCTAssertEqual($0 as? CompositionValidationError, .compositionDependencyCycle)
        }
    }
}
