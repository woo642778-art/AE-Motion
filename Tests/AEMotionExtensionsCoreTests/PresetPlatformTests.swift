import XCTest
@testable import AEMotionExtensionsCore

final class PresetPlatformTests: XCTestCase {
    func testPresetXMLRoundTripPreservesCurveMacroAndDependencies() throws {
        let document = PresetDocument(
            id: "velocity.impact.custom",
            name: "Impact Custom",
            summary: "A user velocity preset",
            author: "Jin Woo",
            kind: .velocity,
            targets: ["speed.remap"],
            tags: ["amv", "impact"],
            parameters: [
                PresetParameter(
                    id: "velocity.curve",
                    name: "Velocity Curve",
                    value: .curve(KeyframeCurve(points: [
                        .init(time: 0, value: 1, outgoingSlope: -4),
                        .init(time: 0.3, value: 4, incomingSlope: 0, outgoingSlope: -2),
                        .init(time: 1, value: 1, incomingSlope: 0),
                    ])),
                    keyframeable: true
                ),
            ],
            macros: [
                PresetMacro(
                    id: "strength",
                    name: "Strength",
                    minimum: 0,
                    maximum: 2,
                    defaultValue: 1,
                    bindings: [
                        .init(parameterID: "velocity.curve", component: "valueScale", outputMinimum: 0, outputMaximum: 2)
                    ]
                ),
            ],
            dependencies: DependencyManifest(
                fonts: [.init(name: "Pretendard", minimumVersion: nil, optional: true)],
                effects: [.init(name: "BCC Film Glow", minimumVersion: "1", optional: false)]
            ),
            extensions: ["future.vendor": "preserved"]
        )

        let data = try PresetXMLCodec.encode(document)
        let decoded = try PresetXMLCodec.decode(data)
        XCTAssertEqual(decoded, document)
    }

    func testValidatorRejectsDuplicateParameterIDsAndMissingTargets() {
        let document = PresetDocument(
            id: "broken",
            name: "Broken",
            kind: .effect,
            targets: [],
            parameters: [
                .init(id: "amount", name: "Amount", value: .number(1)),
                .init(id: "amount", name: "Duplicate", value: .number(2)),
            ]
        )
        let result = PresetValidator.validate(document)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.code == "target.missing" })
        XCTAssertTrue(result.issues.contains { $0.code == "parameter.duplicate" })
    }

    func testMacroMapsNormalizedInputToNumericParameter() throws {
        let document = PresetDocument(
            id: "shake",
            name: "Shake",
            kind: .motion,
            targets: ["camera.shake"],
            parameters: [.init(id: "amplitude", name: "Amplitude", value: .number(10))],
            macros: [
                .init(
                    id: "strength",
                    name: "Strength",
                    minimum: 0,
                    maximum: 1,
                    defaultValue: 0.5,
                    bindings: [.init(parameterID: "amplitude", outputMinimum: 0, outputMaximum: 40)]
                ),
            ]
        )
        let applied = try PresetMacroEngine.applying(macroID: "strength", value: 0.75, to: document)
        XCTAssertEqual(applied.parameter(id: "amplitude")?.value.numberValue ?? .nan, 30, accuracy: 0.0001)
    }

    func testSpeedAdapterScalesNormalizedCurveToDuration() throws {
        let document = PresetBuiltins.impactVelocity
        let keyframes = try SpeedPresetAdapter.keyframes(from: document, duration: 4)
        XCTAssertEqual(keyframes.first?.outputTime ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(keyframes.last?.outputTime ?? .nan, 4, accuracy: 0.0001)
        XCTAssertGreaterThan(keyframes.map(\.velocity).max() ?? 0, 2)
    }

    func testPresetQueryMatchesTagsTargetsAndFavorites() {
        let documents = [PresetBuiltins.impactVelocity, PresetBuiltins.easeInOut, PresetBuiltins.handheldShake]
        let result = PresetQuery.filter(
            documents,
            text: "amv",
            kind: nil,
            target: nil,
            favoriteIDs: [PresetBuiltins.impactVelocity.id],
            favoritesOnly: true
        )
        XCTAssertEqual(result.map(\.id), [PresetBuiltins.impactVelocity.id])
    }

    func testNativeEffectCategoriesRestoreMoveAndDistortionGroups() {
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("move"), "transform")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("transform"), "transform")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("move/transform"), "transform")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("warp"), "distort")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("distortion/warp"), "distort")
        XCTAssertEqual(EffectSearchMetadata.normalizedCategory("distortion"), "distort")
    }

    func testBootstrapRefreshesChangedBuiltInPreset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PresetFileStore(rootDirectory: root)
        let old = PresetDocument(id: "builtin.refresh", name: "Old", kind: .motion, targets: ["camera.shake"])
        let updated = PresetDocument(id: "builtin.refresh", name: "Updated", kind: .motion, targets: ["camera.shake"])

        try store.bootstrap(builtins: [old])
        try store.bootstrap(builtins: [updated])

        XCTAssertEqual(store.loadAll().documents.first(where: { $0.id == "builtin.refresh" })?.name, "Updated")
    }


    func testFileStoreQuarantinesInvalidXMLAndDuplicatesPreset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PresetFileStore(rootDirectory: root)
        try store.bootstrap(builtins: [PresetBuiltins.impactVelocity])
        try Data("<not-a-preset/>".utf8).write(to: store.userDirectory.appendingPathComponent("broken.xml"))

        let load = store.loadAll()
        XCTAssertTrue(load.documents.contains { $0.id == PresetBuiltins.impactVelocity.id })
        XCTAssertEqual(load.issues.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.quarantineDirectory.path))

        let duplicate = try store.duplicate(PresetBuiltins.impactVelocity, newName: "Impact Copy")
        XCTAssertNotEqual(duplicate.id, PresetBuiltins.impactVelocity.id)
        XCTAssertEqual(duplicate.name, "Impact Copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: duplicate).path))
    }

    func testExtendedPresetValuesAndTemplateRoundTrip() throws {
        let template = EditableTemplateDefinition(
            exposedParameterIDs: ["title", "accent", "media.hero"],
            lockedParameterIDs: ["internal.seed"],
            mediaSlots: [
                .init(id: "media.hero", name: "Hero Clip", required: true, acceptedTypes: ["public.movie", "public.image"]),
            ],
            responsiveTime: .init(introDuration: 0.5, outroDuration: 0.4, minimumMiddleDuration: 1.0, loopMiddle: true)
        )
        let document = PresetDocument(
            id: "template.extended",
            name: "Extended Template",
            kind: .editableTemplate,
            targets: ["template.editable"],
            parameters: [
                .init(id: "mode", name: "Mode", value: .choice("Impact"), options: ["Impact", "Smooth"]),
                .init(id: "rotation", name: "Rotation", value: .angle(45)),
                .init(id: "canvas", name: "Canvas", value: .size(.init(width: 1920, height: 1080))),
                .init(id: "crop", name: "Crop", value: .rectangle(.init(x: 0.1, y: 0.2, width: 0.7, height: 0.6))),
                .init(id: "gradient", name: "Gradient", value: .gradient(.init(stops: [
                    .init(location: 0, color: .init(red: 1, green: 0, blue: 0)),
                    .init(location: 1, color: .init(red: 0, green: 0, blue: 1)),
                ]))),
                .init(id: "layer", name: "Layer", value: .layerReference("layer.hero")),
                .init(id: "mask", name: "Mask", value: .maskReference("mask.subject")),
                .init(id: "map", name: "Map", value: .mapReference("layer.noise")),
                .init(id: "band", name: "Band", value: .audioBandReference("bass:40-180")),
                .init(id: "seed", name: "Seed", value: .seed(42)),
                .init(id: "quality", name: "Quality", value: .qualityLevel(.final)),
            ],
            template: template
        )

        let decoded = try PresetXMLCodec.decode(PresetXMLCodec.encode(document))
        XCTAssertEqual(decoded, document)
    }

    func testMacroReverseValueAndRepeatedCurveApplicationAreStable() throws {
        let curve = KeyframeCurve(points: [
            .init(time: 0, value: 1),
            .init(time: 1, value: 2),
        ])
        let document = PresetDocument(
            id: "macro.stable",
            name: "Stable Macro",
            kind: .graph,
            targets: ["easing.curve"],
            parameters: [
                .init(id: "amount", name: "Amount", value: .number(20)),
                .init(id: "curve", name: "Curve", value: .curve(curve), defaultValue: .curve(curve)),
            ],
            macros: [
                .init(id: "strength", name: "Strength", minimum: 0, maximum: 1, defaultValue: 0.5, bindings: [
                    .init(parameterID: "amount", outputMinimum: 0, outputMaximum: 40),
                    .init(parameterID: "curve", component: "valueScale", outputMinimum: 0, outputMaximum: 2),
                ]),
            ]
        )

        XCTAssertEqual(try PresetMacroEngine.value(macroID: "strength", in: document), 0.5, accuracy: 0.0001)
        let first = try PresetMacroEngine.applying(macroID: "strength", value: 0.75, to: document)
        let second = try PresetMacroEngine.applying(macroID: "strength", value: 0.75, to: first)
        XCTAssertEqual(first.parameter(id: "curve"), second.parameter(id: "curve"))
        XCTAssertEqual(try PresetMacroEngine.value(macroID: "strength", in: first), 0.75, accuracy: 0.0001)
    }

    func testCompatibilityEvaluatorReportsOnlyAvailableDependencyDomains() {
        let document = PresetDocument(
            id: "dependencies",
            name: "Dependencies",
            kind: .effect,
            targets: ["effect.generic"],
            dependencies: .init(
                fonts: [.init(name: "Missing Font")],
                effects: [.init(name: "BCC Film Glow")],
                models: [.init(name: "DepthModel", optional: true)]
            ),
            compatibility: [
                .init(kind: .minimumIOSVersion, value: "17.0"),
                .init(kind: .target, value: "effect.generic"),
            ]
        )
        let context = PresetRuntimeContext(
            appVersion: "2.0.0",
            iOSVersion: "16.6",
            availableTargets: ["effect.generic"],
            availableFonts: ["Pretendard"],
            availableEffects: nil,
            availableModels: []
        )
        let result = PresetCompatibilityEvaluator.evaluate(document, context: context)
        XCTAssertTrue(result.issues.contains { $0.code == "compatibility.ios" && $0.severity == .error })
        XCTAssertTrue(result.issues.contains { $0.code == "dependency.font" && $0.severity == .error })
        XCTAssertFalse(result.issues.contains { $0.code == "dependency.effect" })
        XCTAssertTrue(result.issues.contains { $0.code == "dependency.model" && $0.severity == .warning })
    }


    func testValidatorRejectsInvalidChoiceGradientAndTemplateReferences() {
        let document = PresetDocument(
            id: "invalid.extended",
            name: "Invalid Extended",
            kind: .editableTemplate,
            targets: ["template.editable"],
            parameters: [
                .init(id: "mode", name: "Mode", value: .choice("Unknown"), options: ["A", "B"]),
                .init(id: "gradient", name: "Gradient", value: .gradient(.init(stops: [
                    .init(location: 1.2, color: .init(red: 1.2, green: 0, blue: 0)),
                ]))),
            ],
            template: .init(
                exposedParameterIDs: ["missing"],
                lockedParameterIDs: ["mode"],
                mediaSlots: [.init(id: "slot", name: "One"), .init(id: "slot", name: "Duplicate")]
            )
        )
        let result = PresetValidator.validate(document)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.code == "choice.invalid" })
        XCTAssertTrue(result.issues.contains { $0.code == "gradient.invalid" })
        XCTAssertTrue(result.issues.contains { $0.code == "template.parameter" })
        XCTAssertTrue(result.issues.contains { $0.code == "template.slot.duplicate" })
    }


    func testPresetDiffReportsChangedAddedAndRemovedParameters() {
        let before = PresetDocument(
            id: "diff", name: "Before", kind: .effect, targets: ["effect.generic"],
            parameters: [
                .init(id: "amount", name: "Amount", value: .number(1)),
                .init(id: "old", name: "Old", value: .boolean(true)),
            ]
        )
        let after = PresetDocument(
            id: "diff", name: "After", kind: .effect, targets: ["effect.generic"],
            parameters: [
                .init(id: "amount", name: "Amount", value: .number(2)),
                .init(id: "new", name: "New", value: .text("x")),
            ]
        )
        let diff = PresetDiff.compare(before, after)
        XCTAssertTrue(diff.entries.contains { $0.path == "name" && $0.kind == .changed })
        XCTAssertTrue(diff.entries.contains { $0.path == "parameters.amount" && $0.kind == .changed })
        XCTAssertTrue(diff.entries.contains { $0.path == "parameters.old" && $0.kind == .removed })
        XCTAssertTrue(diff.entries.contains { $0.path == "parameters.new" && $0.kind == .added })
    }


    func testMigratorUpgradesLegacyTargetsAndPreservesExtensionFields() throws {
        let legacy = PresetDocument(
            schemaVersion: "0.9",
            id: "legacy",
            name: "Legacy",
            kind: .velocity,
            targets: ["speedRemap"],
            extensions: ["vendor.custom": "keep"]
        )
        let migrated = try PresetMigrator.migrate(legacy)
        XCTAssertEqual(migrated.schemaVersion, "1.0")
        XCTAssertEqual(migrated.targets, ["speed.remap"])
        XCTAssertEqual(migrated.extensions["vendor.custom"], "keep")
        XCTAssertEqual(migrated.extensions["migration.sourceSchema"], "0.9")
    }


    func testColorPaletteFactoryBuildsRoundTrippablePreset() throws {
        let colors = [
            PresetColor(red: 1, green: 0.25, blue: 0.1),
            PresetColor(red: 0.1, green: 0.3, blue: 0.9),
            PresetColor(red: 0.02, green: 0.02, blue: 0.04),
        ]
        let document = ColorPalettePresetFactory.document(
            colors: colors,
            name: "User Palette",
            id: "user.palette",
            timestamp: "2026-07-12T00:00:00Z"
        )

        XCTAssertEqual(document.kind, .color)
        XCTAssertEqual(document.targets, ["color.palette"])
        XCTAssertEqual(document.createdAt, "2026-07-12T00:00:00Z")
        XCTAssertEqual(document.modifiedAt, "2026-07-12T00:00:00Z")
        XCTAssertEqual(try ColorPresetAdapter.colors(from: document), colors)

        let decoded = try PresetXMLCodec.decode(PresetXMLCodec.encode(document))
        XCTAssertEqual(try ColorPresetAdapter.colors(from: decoded), colors)
    }


    func testColorAdapterReadsGradientPalette() throws {
        let document = PresetDocument(
            id: "color.palette",
            name: "Palette",
            kind: .color,
            targets: ["color.palette"],
            parameters: [
                .init(id: "palette.colors", name: "Colors", value: .gradient(.init(stops: [
                    .init(location: 0, color: .init(red: 1, green: 0, blue: 0)),
                    .init(location: 1, color: .init(red: 0, green: 0, blue: 1)),
                ]))),
            ]
        )
        let colors = try ColorPresetAdapter.colors(from: document)
        XCTAssertEqual(colors, [PresetColor(red: 1, green: 0, blue: 0), PresetColor(red: 0, green: 0, blue: 1)])
    }

}

