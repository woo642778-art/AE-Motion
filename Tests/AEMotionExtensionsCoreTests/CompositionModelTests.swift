import XCTest
@testable import AEMotionExtensionsCore

final class CompositionModelTests: XCTestCase {
    func testCompositionDocumentRoundTripsWithStableIdentifiers() throws {
        let child = Composition(name: "Child", duration: 2)
        let layer = CompositionLayer(name: "Title", kind: .shape, timeRange: .init(start: 1, duration: 2))
        let root = Composition(name: "Root", duration: 8, layers: [layer])
        let document = CompositionDocument(rootCompositionID: root.id, compositions: [root, child])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(CompositionDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.rootCompositionID, root.id)
        XCTAssertEqual(decoded.compositions[0].layers[0].id, layer.id)
    }

    func testValidatorRejectsDuplicateLayerIdentifier() {
        let id = UUID()
        let first = CompositionLayer(id: id, name: "A", kind: .video, timeRange: .init(start: 0, duration: 1))
        let second = CompositionLayer(id: id, name: "B", kind: .video, timeRange: .init(start: 1, duration: 1))
        let composition = Composition(name: "Root", duration: 3, layers: [first, second])
        let document = CompositionDocument(rootCompositionID: composition.id, compositions: [composition])

        XCTAssertThrowsError(try CompositionValidator.validate(document)) {
            XCTAssertEqual($0 as? CompositionValidationError, .duplicateIdentifier(id))
        }
    }

    func testValidatorRejectsInvalidTimeRange() {
        let layer = CompositionLayer(name: "Bad", kind: .video, timeRange: .init(start: 0, duration: -1))
        let composition = Composition(name: "Root", duration: 3, layers: [layer])
        let document = CompositionDocument(rootCompositionID: composition.id, compositions: [composition])

        XCTAssertThrowsError(try CompositionValidator.validate(document)) {
            XCTAssertEqual($0 as? CompositionValidationError, .invalidLayerTimeRange(layer.id))
        }
    }

    func testValidatorRejectsMissingRelationshipSources() {
        let missingMatte = UUID()
        let missingParent = UUID()
        let layer = CompositionLayer(
            name: "Target",
            kind: .video,
            timeRange: .init(start: 0, duration: 1),
            matte: .init(sourceLayerID: missingMatte, mode: .alpha),
            parent: .init(parentLayerID: missingParent)
        )
        let composition = Composition(name: "Root", duration: 3, layers: [layer])
        let document = CompositionDocument(rootCompositionID: composition.id, compositions: [composition])

        XCTAssertThrowsError(try CompositionValidator.validate(document)) {
            XCTAssertEqual(
                $0 as? CompositionValidationError,
                .missingMatteSource(layerID: layer.id, sourceID: missingMatte)
            )
        }
    }
}
