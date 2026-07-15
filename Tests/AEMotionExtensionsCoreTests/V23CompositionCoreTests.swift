import Foundation
import XCTest
@testable import AEMotionExtensionsCore

private func v23Range(_ start: Double, _ duration: Double) -> CompositionTimeRange {
    try! CompositionTimeRange(start: start, duration: duration)
}

private func v23Layer(
    id: LayerID = LayerID(),
    name: String,
    start: Double,
    duration: Double,
    transform: LayerTransform = .identity,
    parentID: LayerID? = nil,
    matte: TrackMatteBinding? = nil,
    blend: BlendModeID = "normal"
) -> CompositionLayer {
    CompositionLayer(
        id: id,
        name: name,
        kind: .media,
        timeRange: v23Range(start, duration),
        transform: transform,
        parentID: parentID,
        trackMatte: matte,
        blendMode: blend
    )
}

private func v23Document(layers: [CompositionLayer], duration: Double = 10) -> CompositionDocument {
    CompositionDocument(root: CompositionDefinition(
        name: "Root",
        width: 1920,
        height: 1080,
        frameRate: 30,
        timeRange: v23Range(0, duration),
        layers: layers
    ))
}

final class V23CompositionCoreTests: XCTestCase {
    func testStableIDsAndLayerOrderRoundTrip() throws {
        let compositionID = CompositionID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let layerID = LayerID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        XCTAssertEqual(try JSONDecoder().decode(CompositionID.self, from: JSONEncoder().encode(compositionID)), compositionID)
        XCTAssertEqual(try JSONDecoder().decode(LayerID.self, from: JSONEncoder().encode(layerID)), layerID)

        let first = v23Layer(name: "A", start: 0, duration: 1)
        let second = v23Layer(name: "B", start: 1, duration: 1)
        let document = v23Document(layers: [first, second])
        let decoded = try JSONDecoder().decode(CompositionDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.root?.layers.map(\.id), [first.id, second.id])
    }

    func testInvalidTimeRangesAreRejected() {
        XCTAssertThrowsError(try CompositionTimeRange(start: -1, duration: 1))
        XCTAssertThrowsError(try CompositionTimeRange(start: 0, duration: -1))
        XCTAssertThrowsError(try CompositionTimeRange(start: .infinity, duration: 1))
    }

    func testGraphRejectsParentAndPrecompositionCycles() {
        let aID = LayerID()
        let bID = LayerID()
        let a = v23Layer(id: aID, name: "A", start: 0, duration: 1, parentID: bID)
        let b = v23Layer(id: bID, name: "B", start: 0, duration: 1, parentID: aID)
        XCTAssertTrue(CompositionGraphValidator.validate(v23Document(layers: [a, b])).contains {
            if case .parentCycle = $0 { return true }
            return false
        })

        let firstID = CompositionID()
        let secondID = CompositionID()
        let first = CompositionDefinition(
            id: firstID,
            name: "First",
            width: 100,
            height: 100,
            frameRate: 30,
            timeRange: v23Range(0, 1),
            layers: [CompositionLayer(name: "Second", kind: .precomposition, sourceCompositionID: secondID, timeRange: v23Range(0, 1))]
        )
        let second = CompositionDefinition(
            id: secondID,
            name: "Second",
            width: 100,
            height: 100,
            frameRate: 30,
            timeRange: v23Range(0, 1),
            layers: [CompositionLayer(name: "First", kind: .precomposition, sourceCompositionID: firstID, timeRange: v23Range(0, 1))]
        )
        let cyclic = CompositionDocument(rootCompositionID: firstID, compositions: [firstID: first, secondID: second])
        XCTAssertTrue(CompositionGraphValidator.validate(cyclic).contains {
            if case .precompositionCycle = $0 { return true }
            return false
        })
    }

    func testReparentAndDisconnectPreserveWorldSpace() throws {
        let firstParentID = LayerID()
        let secondParentID = LayerID()
        let childID = LayerID()
        let first = v23Layer(id: firstParentID, name: "P1", start: 0, duration: 5, transform: LayerTransform(positionX: 50, positionY: 10, scaleX: 2, scaleY: 2))
        let second = v23Layer(id: secondParentID, name: "P2", start: 0, duration: 5, transform: LayerTransform(positionX: -20, positionY: 80, rotationRadians: 0.25))
        let child = v23Layer(id: childID, name: "Child", start: 0, duration: 5, transform: LayerTransform(positionX: 12, positionY: 7), parentID: firstParentID)
        let original = v23Document(layers: [first, second, child])
        let before = try ParentingResolver.worldMatrix(for: childID, in: original)
        let reparented = try ParentingResolver.reparentPreservingWorldSpace(child: childID, newParent: secondParentID, document: original)
        let after = try ParentingResolver.worldMatrix(for: childID, in: reparented)
        XCTAssertEqual(after.a, before.a, accuracy: 1e-9)
        XCTAssertEqual(after.b, before.b, accuracy: 1e-9)
        XCTAssertEqual(after.c, before.c, accuracy: 1e-9)
        XCTAssertEqual(after.d, before.d, accuracy: 1e-9)
        XCTAssertEqual(after.tx, before.tx, accuracy: 1e-9)
        XCTAssertEqual(after.ty, before.ty, accuracy: 1e-9)

        let disconnected = try ParentingResolver.reparentPreservingWorldSpace(child: childID, newParent: nil, document: original)
        let disconnectedWorld = try ParentingResolver.worldMatrix(for: childID, in: disconnected)
        XCTAssertEqual(disconnectedWorld.tx, before.tx, accuracy: 1e-9)
        XCTAssertEqual(disconnectedWorld.ty, before.ty, accuracy: 1e-9)
    }

    func testBlendCatalogAndReferenceVectors() {
        XCTAssertEqual(Set(BlendModeCatalog.all.map(\.group)), Set(BlendModeGroup.allCases))
        XCTAssertGreaterThanOrEqual(BlendModeCatalog.all.count, 38)
        XCTAssertEqual(BlendModeCatalog.descriptor(for: "dissolve")?.policy, .stochasticRequiresSeed)

        let backdrop = PixelRGBA(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let source = PixelRGBA(red: 0.7, green: 0.5, blue: 0.25, alpha: 1)
        let multiply = BlendReferenceMath.composite(source: source, backdrop: backdrop, mode: "multiply")
        XCTAssertEqual(multiply.red, 0.14, accuracy: 1e-9)
        XCTAssertEqual(multiply.green, 0.2, accuracy: 1e-9)
        XCTAssertEqual(multiply.blue, 0.2, accuracy: 1e-9)
        let screen = BlendReferenceMath.composite(source: source, backdrop: backdrop, mode: "screen")
        XCTAssertEqual(screen.red, 0.76, accuracy: 1e-9)
        XCTAssertEqual(screen.green, 0.7, accuracy: 1e-9)
        XCTAssertEqual(screen.blue, 0.85, accuracy: 1e-9)
        let difference = BlendReferenceMath.composite(source: source, backdrop: backdrop, mode: "difference")
        XCTAssertEqual(difference.red, 0.5, accuracy: 1e-9)
        XCTAssertEqual(difference.green, 0.1, accuracy: 1e-9)
        XCTAssertEqual(difference.blue, 0.55, accuracy: 1e-9)
    }

    func testChannelAndAlphaOperations() {
        let original = PixelRGBA(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.25)
        let roundTrip = ChannelProcessor.process(original, operations: [.premultiply, .unpremultiply])
        XCTAssertEqual(roundTrip.red, original.red, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.green, original.green, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.blue, original.blue, accuracy: 1e-9)
        XCTAssertEqual(ChannelProcessor.process(PixelRGBA(red: 1, green: 1, blue: 1, alpha: 0), operations: [.unpremultiply]), .clear)

        let mapped = ChannelProcessor.process(
            PixelRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            operations: [
                .map(output: .red, source: .blue),
                .map(output: .green, source: .alpha),
                .map(output: .blue, source: .one),
            ]
        )
        XCTAssertEqual(mapped.red, 0.3, accuracy: 1e-9)
        XCTAssertEqual(mapped.green, 0.4, accuracy: 1e-9)
        XCTAssertEqual(mapped.blue, 1, accuracy: 1e-9)
    }

    func testModernTrackMatteUsesStableIDsAndRec709Luma() {
        let matteID = LayerID()
        let matte = v23Layer(id: matteID, name: "Matte", start: 0, duration: 3)
        let first = v23Layer(name: "One", start: 0, duration: 3, matte: TrackMatteBinding(sourceLayerID: matteID, mode: .alpha))
        let second = v23Layer(name: "Two", start: 0, duration: 3, matte: TrackMatteBinding(sourceLayerID: matteID, mode: .luma))
        let reordered = v23Document(layers: [second, matte, first])
        XCTAssertTrue(CompositionGraphValidator.validate(reordered).isEmpty)
        XCTAssertEqual(reordered.root?.layer(id: first.id)?.trackMatte?.sourceLayerID, matteID)
        XCTAssertEqual(TrackMatteEvaluator.coverage(
            for: PixelRGBA(red: 1, green: 0, blue: 0, alpha: 0.5),
            mode: .luma
        ), 0.2126 * 0.5, accuracy: 1e-9)
    }

    func testEditablePrecomposeAutoTrimsAndPreservesProperties() throws {
        let firstID = LayerID()
        let secondID = LayerID()
        var first = v23Layer(id: firstID, name: "First", start: 2, duration: 3, transform: LayerTransform(positionX: 20, positionY: 30), blend: "screen")
        first.effectIDs = ["glow"]
        first.keyframes = ["opacity": [ScalarKeyframe(time: 2, value: 0.5)]]
        let middle = v23Layer(name: "Middle", start: 0, duration: 10)
        let second = v23Layer(id: secondID, name: "Second", start: 4, duration: 4, parentID: firstID)
        let original = v23Document(layers: [first, middle, second])

        let mutation = try PrecomposeCommand.apply(selection: [firstID, secondID], name: "Selected", to: original)
        let child = mutation.updated.compositions[mutation.createdCompositionID!]!
        XCTAssertEqual(child.timeRange.duration, 6)
        XCTAssertEqual(child.layers.map(\.id), [firstID, secondID])
        XCTAssertEqual(child.layer(id: firstID)?.timeRange.start, 0)
        XCTAssertEqual(child.layer(id: secondID)?.timeRange.start, 2)
        XCTAssertEqual(child.layer(id: firstID)?.blendMode, "screen")
        XCTAssertEqual(child.layer(id: firstID)?.effectIDs, ["glow"])
        XCTAssertEqual(child.layer(id: secondID)?.parentID, firstID)
        XCTAssertEqual(mutation.updated.root?.layers.map(\.name), ["Selected", "Middle"])
        XCTAssertEqual(mutation.inverseDocument(), original)
    }

    func testPrecomposeRejectsSplitMatteDependency() {
        let matteID = LayerID()
        let targetID = LayerID()
        let otherID = LayerID()
        let matte = v23Layer(id: matteID, name: "Matte", start: 0, duration: 3)
        let target = v23Layer(id: targetID, name: "Target", start: 0, duration: 3, matte: TrackMatteBinding(sourceLayerID: matteID, mode: .alpha))
        let other = v23Layer(id: otherID, name: "Other", start: 0, duration: 3)
        XCTAssertThrowsError(try PrecomposeCommand.apply(selection: [targetID, otherID], name: "P", to: v23Document(layers: [matte, target, other]))) { error in
            XCTAssertEqual(error as? PrecomposeCommandError, .splitMatteDependency(layer: targetID, matte: matteID))
        }
    }

    func testStructuralTransactionCommitsAndRollsBackExactly() throws {
        let original = v23Document(layers: [])
        let updated = v23Document(layers: [v23Layer(name: "A", start: 0, duration: 1)])
        var applied: [CompositionDocument] = []
        let transaction = CompositionTransaction(original: original) { applied.append($0) }
        try transaction.begin()
        try transaction.update(updated)
        XCTAssertEqual(try transaction.commit(), updated)

        applied.removeAll()
        let cancelling = CompositionTransaction(original: original) { applied.append($0) }
        try cancelling.begin()
        try cancelling.update(updated)
        try cancelling.selectionDidChange()
        XCTAssertEqual(cancelling.state, .cancelled)
        XCTAssertEqual(applied.last, original)
    }

    func testPreviewCoalescerKeepsLatestGraph() async {
        let first = v23Document(layers: [v23Layer(name: "A", start: 0, duration: 1)])
        let second = v23Document(layers: [v23Layer(name: "B", start: 0, duration: 1)])
        let coalescer = CompositionPreviewCoalescer()
        await coalescer.enqueue(first)
        await coalescer.enqueue(second)
        XCTAssertEqual(await coalescer.takePending(), second)
        let empty = await coalescer.takePending()
        XCTAssertNil(empty)
    }
}
