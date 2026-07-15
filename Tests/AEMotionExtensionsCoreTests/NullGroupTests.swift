import XCTest
@testable import AEMotionExtensionsCore

final class NullGroupTests: XCTestCase {
    func testGroupCreatesCenteredNullAboveSelectionAndPreservesWorldTransforms() throws {
        let background = CompositionLayer(name: "Background", kind: .image, timeRange: .init(start: 0, duration: 10))
        let first = CompositionLayer(
            name: "A",
            kind: .video,
            timeRange: .init(start: 2, duration: 3),
            transform: .init(positionX: 20, positionY: 30, anchorX: 2, anchorY: 4, scaleX: 1.2, scaleY: 0.8, rotationDegrees: 15)
        )
        let second = CompositionLayer(
            name: "B",
            kind: .shape,
            timeRange: .init(start: 4, duration: 4),
            transform: .init(positionX: 100, positionY: 70, anchorX: 6, anchorY: 8, scaleX: 0.7, scaleY: 1.4, rotationDegrees: -20)
        )
        let foreground = CompositionLayer(name: "Foreground", kind: .text, timeRange: .init(start: 0, duration: 10))
        let root = Composition(name: "Root", duration: 10, layers: [background, first, second, foreground])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])
        let beforeGraph = try CompositionGraph(composition: root)
        let firstBefore = try beforeGraph.resolvedWorldTransform(layerID: first.id)
        let secondBefore = try beforeGraph.resolvedWorldTransform(layerID: second.id)

        let result = try NullGroupEngine.group(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [second.id, first.id], name: "Null Group 1")
        )

        let grouped = result.document.compositions[0]
        XCTAssertEqual(grouped.layers.map(\.id), [background.id, result.nullLayer.id, first.id, second.id, foreground.id])
        XCTAssertEqual(result.nullLayer.timeRange, .init(start: 2, duration: 6))
        XCTAssertEqual(result.nullLayer.kind, .null)
        let expectedX = (firstBefore.matrix.tx + secondBefore.matrix.tx) / 2
        let expectedY = (firstBefore.matrix.ty + secondBefore.matrix.ty) / 2
        XCTAssertEqual(result.nullLayer.transform.positionX, expectedX, accuracy: 0.000001)
        XCTAssertEqual(result.nullLayer.transform.positionY, expectedY, accuracy: 0.000001)

        let afterGraph = try CompositionGraph(composition: grouped)
        let firstAfter = try afterGraph.resolvedWorldTransform(layerID: first.id)
        let secondAfter = try afterGraph.resolvedWorldTransform(layerID: second.id)
        assertEqual(firstBefore.matrix, firstAfter.matrix)
        assertEqual(secondBefore.matrix, secondAfter.matrix)
        XCTAssertEqual(afterGraph.layer(id: first.id)?.parent?.parentLayerID, result.nullLayer.id)
        XCTAssertEqual(afterGraph.layer(id: second.id)?.parent?.parentLayerID, result.nullLayer.id)
        XCTAssertEqual(result.originalDocument, document)
    }

    func testGroupRejectsEmptySelectionWithoutMutation() {
        let root = Composition(name: "Root", duration: 2)
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root])
        XCTAssertThrowsError(try NullGroupEngine.group(
            document: document,
            request: .init(compositionID: root.id, selectedLayerIDs: [], name: "Bad")
        )) {
            XCTAssertEqual($0 as? NullGroupError, .emptySelection)
        }
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
