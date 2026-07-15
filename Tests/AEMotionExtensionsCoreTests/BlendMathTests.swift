import XCTest
@testable import AEMotionExtensionsCore

final class BlendMathTests: XCTestCase {
    func testCatalogueContainsAllApprovedGroupsAndModes() {
        XCTAssertEqual(Set(BlendModeCatalogue.all.map(\.group)), Set(BlendModeGroup.allCases))
        for id in [
            "normal", "multiply", "color-burn", "linear-burn", "darker-color",
            "add", "screen", "color-dodge", "linear-dodge", "lighter-color",
            "overlay", "soft-light", "hard-light", "linear-light", "vivid-light",
            "pin-light", "hard-mix", "difference", "exclusion", "subtract", "divide",
            "hue", "saturation", "color", "luminosity",
        ] {
            XCTAssertNotNil(BlendModeCatalogue.descriptor(id: id), "Missing \(id)")
        }
    }

    func testMultiplyReferenceVector() throws {
        let result = try BlendMath.blend(
            source: RGBA(r: 0.8, g: 0.5, b: 0.25, a: 1),
            destination: RGBA(r: 0.5, g: 0.4, b: 0.8, a: 1),
            modeID: "multiply"
        )
        XCTAssertEqual(result.r, 0.4, accuracy: 0.000001)
        XCTAssertEqual(result.g, 0.2, accuracy: 0.000001)
        XCTAssertEqual(result.b, 0.2, accuracy: 0.000001)
        XCTAssertEqual(result.a, 1, accuracy: 0.000001)
    }

    func testScreenAndOverlayReferenceVectors() throws {
        let source = RGBA(r: 0.8, g: 0.5, b: 0.25, a: 1)
        let destination = RGBA(r: 0.5, g: 0.4, b: 0.8, a: 1)
        let screen = try BlendMath.blend(source: source, destination: destination, modeID: "screen")
        XCTAssertEqual(screen.r, 0.9, accuracy: 0.000001)
        XCTAssertEqual(screen.g, 0.7, accuracy: 0.000001)
        XCTAssertEqual(screen.b, 0.85, accuracy: 0.000001)
        let overlay = try BlendMath.blend(source: source, destination: destination, modeID: "overlay")
        XCTAssertEqual(overlay.r, 0.8, accuracy: 0.000001)
        XCTAssertEqual(overlay.g, 0.4, accuracy: 0.000001)
        XCTAssertEqual(overlay.b, 0.7, accuracy: 0.000001)
    }

    func testLinearAndInversionModesClampOutput() throws {
        let source = RGBA(r: 0.8, g: 0.2, b: 0.9, a: 1)
        let destination = RGBA(r: 0.5, g: 0.4, b: 0.3, a: 1)

        let add = try BlendMath.blend(source: source, destination: destination, modeID: "add")
        XCTAssertEqual(add.r, 1, accuracy: 0.000001)
        XCTAssertEqual(add.g, 0.6, accuracy: 0.000001)
        XCTAssertEqual(add.b, 1, accuracy: 0.000001)

        let burn = try BlendMath.blend(source: source, destination: destination, modeID: "linear-burn")
        XCTAssertEqual(burn.r, 0.3, accuracy: 0.000001)
        XCTAssertEqual(burn.g, 0, accuracy: 0.000001)
        XCTAssertEqual(burn.b, 0.2, accuracy: 0.000001)

        let difference = try BlendMath.blend(source: source, destination: destination, modeID: "difference")
        XCTAssertEqual(difference.r, 0.3, accuracy: 0.000001)
        XCTAssertEqual(difference.g, 0.2, accuracy: 0.000001)
        XCTAssertEqual(difference.b, 0.6, accuracy: 0.000001)

        let subtract = try BlendMath.blend(source: source, destination: destination, modeID: "subtract")
        XCTAssertEqual(subtract.r, 0, accuracy: 0.000001)
        XCTAssertEqual(subtract.g, 0.2, accuracy: 0.000001)
        XCTAssertEqual(subtract.b, 0, accuracy: 0.000001)
    }

    func testSourceOverAlphaUsesBlendResult() throws {
        let source = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let destination = RGBA(r: 0, g: 0, b: 1, a: 1)
        let result = try BlendMath.blend(source: source, destination: destination, modeID: "normal")
        XCTAssertEqual(result.r, 0.5, accuracy: 0.000001)
        XCTAssertEqual(result.g, 0, accuracy: 0.000001)
        XCTAssertEqual(result.b, 0.5, accuracy: 0.000001)
        XCTAssertEqual(result.a, 1, accuracy: 0.000001)
    }

    func testComponentModesPreserveExpectedLuminosityOrColor() throws {
        let source = RGBA(r: 0.9, g: 0.1, b: 0.2, a: 1)
        let destination = RGBA(r: 0.2, g: 0.5, b: 0.7, a: 1)
        let color = try BlendMath.blend(source: source, destination: destination, modeID: "color")
        let luminosity = try BlendMath.blend(source: source, destination: destination, modeID: "luminosity")
        XCTAssertEqual(BlendMath.luminosity(color), BlendMath.luminosity(destination), accuracy: 0.000001)
        XCTAssertEqual(BlendMath.luminosity(luminosity), BlendMath.luminosity(source), accuracy: 0.000001)
    }

    func testUnverifiedOrUnknownModeFailsClosed() {
        XCTAssertThrowsError(try BlendMath.blend(source: .clear, destination: .clear, modeID: "dissolve"))
        XCTAssertThrowsError(try BlendMath.blend(source: .clear, destination: .clear, modeID: "unknown"))
    }
}
