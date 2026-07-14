import XCTest
@testable import AEMotionExtensionsCore

final class CoreTests: XCTestCase {
    func testCategoryInsertedAfterMoveTransform() {
        let input = [HostCategory(id: "color", title: "Color"), HostCategory(id: "move_transform", title: "Move & Transform"), HostCategory(id: "blur", title: "Blur")]
        XCTAssertEqual(CategoryInjector.insertExtensionsCategory(in: input).map(\.id), ["color", "move_transform", "com.aemotion.extensions", "blur"])
    }
    func testCategoryInsertedOnlyOnce() {
        let once = CategoryInjector.insertExtensionsCategory(in: [HostCategory(id: "moveTransform", title: "Move & Transform")])
        XCTAssertEqual(CategoryInjector.insertExtensionsCategory(in: once), once)
    }
    func testFramesPerBeat() { XCTAssertEqual(BPMFrameCalculator.framesPerBeat(bpm: 120, fps: 60), 30, accuracy: 0.0001) }
    func testEasingEndpoints() {
        let values = EasingCurveGenerator.easeInOutCubic(samples: 5, durationFrames: 60)
        XCTAssertEqual(values.first?.value, 0); XCTAssertEqual(values.last?.value, 1); XCTAssertEqual(values.last?.frame, 60)
    }
    func testRandomIsDeterministic() {
        XCTAssertEqual(RandomValueGenerator.values(count: 4, range: -1...1, seed: 7), RandomValueGenerator.values(count: 4, range: -1...1, seed: 7))
    }
    func testOffsetPlanner() { XCTAssertEqual(LayerOffsetPlanner.startFrames(layerCount: 4, firstFrame: 10, offsetFrames: 3), [10,13,16,19]) }
    func testCameraShakeDeterministic() {
        let a = CameraShakeGenerator.samples(count: 3, amplitude: 10, decay: 0.8, seed: 9)
        let b = CameraShakeGenerator.samples(count: 3, amplitude: 10, decay: 0.8, seed: 9)
        XCTAssertEqual(a.map(\.x), b.map(\.x)); XCTAssertEqual(a.map(\.y), b.map(\.y))
    }
    func testToolRegistryContainsFunctionalTools() {
        XCTAssertEqual(ToolRegistry.all.count, 16)
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "speed.remap" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "host.diagnostics" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "effects.integrity" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "project.reliability" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "cutout.person" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "dead.frames" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "depth.map" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "preset.library" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "resource.hub" })
    }
    func testToolRegistryExcludesStandaloneAnimationCore() {
        XCTAssertFalse(ToolRegistry.all.contains { $0.id == "animation.core" })
        XCTAssertEqual(ToolRegistry.all.count, 16)
    }
    func testConstantSpeedCurve() throws {
        let curve = try SpeedCurve.constant(duration: 3, velocity: 2)
        XCTAssertEqual(curve.velocity(at: 1.5), 2, accuracy: 1e-9)
        XCTAssertEqual(curve.sourceTime(at: 1.5), 3, accuracy: 1e-6)
    }
    func testReverseSpeedCurve() throws {
        let curve = try SpeedCurve.reverse(sourceDuration: 5)
        XCTAssertEqual(curve.sourceTime(at: 0), 5, accuracy: 1e-9)
        XCTAssertEqual(curve.sourceTime(at: 2), 3, accuracy: 1e-6)
        XCTAssertEqual(curve.sourceTime(at: 5), 0, accuracy: 1e-6)
    }
    func testFreezeSpeedCurve() throws {
        let curve = try SpeedCurve.constant(duration: 2, velocity: 0, sourceOrigin: 1.25)
        XCTAssertEqual(curve.sourceTime(at: 1.8), 1.25, accuracy: 1e-9)
    }
    func testRenderSizePolicyPreservesUnderLimitLandscape() {
        XCTAssertEqual(RenderSizePolicy.constrained(width: 1920, height: 1080), RenderDimensions(width: 1920, height: 1080))
    }
    func testRenderSizePolicyCapsOversizedPortrait() {
        let result = RenderSizePolicy.constrained(width: 4320, height: 7680)
        XCTAssertLessThanOrEqual(max(result.width, result.height), 3840)
        XCTAssertLessThanOrEqual(result.width * result.height, 8_294_400)
        XCTAssertEqual(result.width % 2, 0); XCTAssertEqual(result.height % 2, 0)
    }
    func testEffectSearchMetadataAddsBCCAliases() {
        let tags = EffectSearchMetadata.normalizedTags(name: "BCC Film Glow", id: "com.alightcreative.effects.bccfilmglow", existing: "film,glow").split(separator: ",").map(String.init)
        XCTAssertTrue(tags.contains("bcc")); XCTAssertTrue(tags.contains("bbc")); XCTAssertTrue(tags.contains("boris")); XCTAssertTrue(tags.contains("borisfx")); XCTAssertTrue(tags.contains("film")); XCTAssertTrue(tags.contains("glow"))
    }
    func testEffectSearchMetadataNormalizesUnsupportedCategories() {
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("lighting"), "drawing")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("stylize"), "procedural")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("distort"), "distort")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("blur"), "blur")
    }
}

extension CoreTests {
    func testToolPlacementRegistryDistributesEditingToolsOutsideExtensionsHub() {
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "speed.remap"), .timeline)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "easing.curve"), .graph)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "cutout.person"), .layer)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "depth.map"), .viewer)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "dead.frames"), .clip)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "camera.shake"), .layer)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "color.palette"), .color)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "project.reliability"), .project)
    }
    func testToolPlacementRegistryKeepsGlobalUtilitiesInHub() {
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "resource.hub"), .extensionsHub)
        XCTAssertEqual(ToolPlacementRegistry.placement(for: "host.diagnostics"), .extensionsHub)
        XCTAssertTrue(ToolPlacementRegistry.contextualToolIDs.contains("speed.remap"))
        XCTAssertFalse(ToolPlacementRegistry.contextualToolIDs.contains("host.diagnostics"))
    }
}

extension CoreTests {
    func testCategoryProxyDoesNotForwardUnknownIndexPathSelectors() {
        XCTAssertFalse(CollectionProxyForwardingPolicy.mayForward(selectorName: "collectionView:willDisplayCell:forItemAtIndexPath:"))
        XCTAssertFalse(CollectionProxyForwardingPolicy.mayForward(selectorName: "collectionView:didEndDisplayingCell:forItemAtIndexPath:"))
        XCTAssertFalse(CollectionProxyForwardingPolicy.mayForward(selectorName: "collectionView:contextMenuConfigurationForItemAtIndexPath:point:"))
    }
    func testCategoryProxyMayForwardSelectorsWithoutIndexPaths() {
        XCTAssertTrue(CollectionProxyForwardingPolicy.mayForward(selectorName: "scrollViewDidScroll:"))
        XCTAssertTrue(CollectionProxyForwardingPolicy.mayForward(selectorName: "collectionView:layout:minimumLineSpacingForSectionAtIndex:"))
    }
}

extension CoreTests {
    func testBrokenEffectsAreNotVisible() {
        XCTAssertFalse(EffectVisibilityPolicy.isVisible(.existingBroken))
        XCTAssertFalse(EffectVisibilityPolicy.isVisible(.placeholder))
        XCTAssertFalse(EffectVisibilityPolicy.isVisible(.unsupportedDependency))
        XCTAssertTrue(EffectVisibilityPolicy.isVisible(.existingWorking))
        XCTAssertTrue(EffectVisibilityPolicy.isVisible(.implementedVerified))
    }
    func testIntegrityReportRoundTrip() throws {
        let report = EffectIntegrityReport(schemaVersion: 1, generatedAt: "2026-07-14T00:00:00Z", sourceAppVersion: "6.2.42", sourceBuild: "838", records: [fixture(.existingWorking)])
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(EffectIntegrityReport.self, from: data), report)
    }
    func testIntegritySummaryCountsStatuses() {
        let summary = EffectIntegritySummary(records: [fixture(.existingWorking), fixture(.existingBroken), fixture(.existingBroken), fixture(.implementedVerified)])
        XCTAssertEqual(summary.visibleCount, 2); XCTAssertEqual(summary.quarantinedCount, 2); XCTAssertEqual(summary.totalCount, 4)
    }
    private func fixture(_ status: EffectIntegrityStatus) -> EffectIntegrityRecord {
        EffectIntegrityRecord(effectID: "com.aemotion.test.\(status.rawValue)", name: "Test", fileName: "test.xml", category: "procedural", status: status, descriptorSHA256: String(repeating: "a", count: 64), shaderSHA256: String(repeating: "b", count: 64), parameterSignature: "amount:slider", dependencies: [], resources: [], findings: [], quarantineReason: nil)
    }
}
