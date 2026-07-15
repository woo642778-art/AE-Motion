import XCTest
@testable import AEMotionExtensionsCore

final class ChannelAlphaTests: XCTestCase {
    func testPremultiplyAndUnpremultiplyRoundTrip() {
        let input = RGBA(r: 0.8, g: 0.4, b: 0.2, a: 0.5)
        let premultiplied = ChannelAlphaProcessor.premultiply(input)
        XCTAssertEqual(premultiplied, RGBA(r: 0.4, g: 0.2, b: 0.1, a: 0.5))
        let restored = ChannelAlphaProcessor.unpremultiply(premultiplied)
        XCTAssertEqual(restored.r, input.r, accuracy: 0.000001)
        XCTAssertEqual(restored.g, input.g, accuracy: 0.000001)
        XCTAssertEqual(restored.b, input.b, accuracy: 0.000001)
        XCTAssertEqual(restored.a, input.a, accuracy: 0.000001)
    }

    func testUnpremultiplyZeroAlphaProducesFiniteClearPixel() {
        let output = ChannelAlphaProcessor.unpremultiply(RGBA(r: 0.8, g: 0.4, b: 0.2, a: 0))
        XCTAssertEqual(output, .clear)
    }

    func testLuminanceCanDriveAlphaWhilePreservingRGB() {
        let input = RGBA(r: 1, g: 0, b: 0, a: 0.25)
        let mapping = ChannelMapping(red: .red, green: .green, blue: .blue, alpha: .luminance)
        let output = ChannelAlphaProcessor.map(input, using: mapping)
        XCTAssertEqual(output.r, 1)
        XCTAssertEqual(output.g, 0)
        XCTAssertEqual(output.b, 0)
        XCTAssertEqual(output.a, 0.2126, accuracy: 0.000001)
    }

    func testAlphaInversionCanPreserveOrReplaceRGB() {
        let input = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.25)
        XCTAssertEqual(
            ChannelAlphaProcessor.invertedAlpha(input, preserveRGB: true),
            RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.75)
        )
        XCTAssertEqual(
            ChannelAlphaProcessor.invertedAlpha(input, preserveRGB: false),
            RGBA(r: 0.75, g: 0.75, b: 0.75, a: 0.75)
        )
    }

    func testSingleChannelPreviewReplicatesSelectedComponent() {
        let input = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        XCTAssertEqual(
            ChannelAlphaProcessor.preview(input, channel: .green),
            RGBA(r: 0.4, g: 0.4, b: 0.4, a: 1)
        )
        XCTAssertEqual(
            ChannelAlphaProcessor.preview(input, channel: .alpha),
            RGBA(r: 0.8, g: 0.8, b: 0.8, a: 1)
        )
    }

    func testCompositionLayerDefaultsToStraightIdentityMapping() {
        let layer = CompositionLayer(name: "Layer", kind: .video, timeRange: .init(start: 0, duration: 1))
        XCTAssertEqual(layer.alphaInterpretation, .straight)
        XCTAssertEqual(layer.channelMapping, .identity)
    }
}
