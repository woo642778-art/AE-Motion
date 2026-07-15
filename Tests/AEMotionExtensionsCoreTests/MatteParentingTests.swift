import XCTest
@testable import AEMotionExtensionsCore

final class MatteParentingTests: XCTestCase {
    func testParentCycleIsRejectedWithoutMutation() throws {
        let a = CompositionLayer(name: "A", kind: .null, timeRange: .init(start: 0, duration: 5))
        var b = CompositionLayer(name: "B", kind: .shape, timeRange: .init(start: 0, duration: 5))
        b.parent = ParentBinding(parentLayerID: a.id)
        var graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [a, b]))
        let before = graph.composition

        XCTAssertThrowsError(try graph.setParent(layerID: a.id, parentID: b.id, preserveWorldTransform: true)) {
            XCTAssertEqual($0 as? CompositionGraphError, .dependencyCycle)
        }
        XCTAssertEqual(graph.composition, before)
    }

    func testReparentPreservesFullWorldMatrixWithRotationScaleAndAnchor() throws {
        let parent = CompositionLayer(
            name: "Null 1",
            kind: .null,
            timeRange: .init(start: 0, duration: 5),
            transform: .init(
                positionX: 120,
                positionY: 80,
                anchorX: 10,
                anchorY: 20,
                scaleX: 1.7,
                scaleY: 0.65,
                rotationDegrees: 37,
                skewDegrees: 12,
                opacity: 0.8
            )
        )
        let child = CompositionLayer(
            name: "Child",
            kind: .shape,
            timeRange: .init(start: 0, duration: 5),
            transform: .init(
                positionX: 40,
                positionY: 75,
                anchorX: 13,
                anchorY: 9,
                scaleX: 0.8,
                scaleY: 1.2,
                rotationDegrees: -24,
                skewDegrees: -7,
                opacity: 0.7
            )
        )
        var graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [parent, child]))
        let before = try graph.resolvedWorldTransform(layerID: child.id)

        try graph.setParent(layerID: child.id, parentID: parent.id, preserveWorldTransform: true)
        let after = try graph.resolvedWorldTransform(layerID: child.id)

        assertEqual(before.matrix, after.matrix)
        XCTAssertEqual(after.opacity, before.opacity, accuracy: 0.000001)
        XCTAssertEqual(graph.layer(id: child.id)?.parent?.parentLayerID, parent.id)
    }

    func testUnparentPreservesFullWorldMatrix() throws {
        let parent = CompositionLayer(
            name: "Parent",
            kind: .null,
            timeRange: .init(start: 0, duration: 5),
            transform: .init(positionX: 50, positionY: 20, scaleX: 1.3, scaleY: 0.75, rotationDegrees: 28, skewDegrees: 9, opacity: 0.6)
        )
        var child = CompositionLayer(
            name: "Child",
            kind: .video,
            timeRange: .init(start: 0, duration: 5),
            transform: .init(positionX: 14, positionY: 22, anchorX: 5, anchorY: 7, scaleX: 0.9, scaleY: 1.4, rotationDegrees: 11, opacity: 0.5)
        )
        child.parent = ParentBinding(parentLayerID: parent.id)
        var graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [parent, child]))
        let before = try graph.resolvedWorldTransform(layerID: child.id)

        try graph.setParent(layerID: child.id, parentID: nil, preserveWorldTransform: true)
        let after = try graph.resolvedWorldTransform(layerID: child.id)

        assertEqual(before.matrix, after.matrix)
        XCTAssertEqual(after.opacity, before.opacity, accuracy: 0.000001)
        XCTAssertNil(graph.layer(id: child.id)?.parent)
    }

    func testOneMatteCanFeedMultipleTargets() throws {
        let matte = CompositionLayer(name: "Matte", kind: .shape, timeRange: .init(start: 0, duration: 5))
        let first = CompositionLayer(name: "A", kind: .video, timeRange: .init(start: 0, duration: 5), matte: .init(sourceLayerID: matte.id, mode: .alpha))
        let second = CompositionLayer(name: "B", kind: .video, timeRange: .init(start: 0, duration: 5), matte: .init(sourceLayerID: matte.id, mode: .lumaInverted))
        let graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [matte, first, second]))

        XCTAssertEqual(graph.matteConsumers(sourceLayerID: matte.id), [first.id, second.id])
    }

    func testMatteCycleIsRejectedWithoutMutation() throws {
        let a = CompositionLayer(name: "A", kind: .shape, timeRange: .init(start: 0, duration: 5))
        var b = CompositionLayer(name: "B", kind: .video, timeRange: .init(start: 0, duration: 5))
        b.matte = MatteBinding(sourceLayerID: a.id, mode: .alpha)
        var graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [a, b]))
        let before = graph.composition

        XCTAssertThrowsError(try graph.setMatte(layerID: a.id, binding: .init(sourceLayerID: b.id, mode: .luma))) {
            XCTAssertEqual($0 as? CompositionGraphError, .dependencyCycle)
        }
        XCTAssertEqual(graph.composition, before)
    }

    func testSingularParentCannotPreserveWorldTransform() throws {
        let parent = CompositionLayer(
            name: "Singular",
            kind: .null,
            timeRange: .init(start: 0, duration: 5),
            transform: .init(scaleX: 0, scaleY: 1)
        )
        let child = CompositionLayer(name: "Child", kind: .shape, timeRange: .init(start: 0, duration: 5))
        var graph = try CompositionGraph(composition: .init(name: "Root", duration: 5, layers: [parent, child]))
        let before = graph.composition

        XCTAssertThrowsError(try graph.setParent(layerID: child.id, parentID: parent.id, preserveWorldTransform: true)) {
            XCTAssertEqual($0 as? CompositionGraphError, .singularTransform(parent.id))
        }
        XCTAssertEqual(graph.composition, before)
    }

    private func assertEqual(
        _ lhs: AffineTransform2D,
        _ rhs: AffineTransform2D,
        accuracy: Double = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.a, rhs.a, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.b, rhs.b, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.c, rhs.c, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.d, rhs.d, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.tx, rhs.tx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.ty, rhs.ty, accuracy: accuracy, file: file, line: line)
    }
}
