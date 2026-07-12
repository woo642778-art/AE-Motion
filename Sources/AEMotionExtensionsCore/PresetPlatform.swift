import Foundation

public struct PresetValidationIssue: Equatable, Sendable, Codable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public var severity: Severity
    public var code: String
    public var message: String

    public init(severity: Severity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

public struct PresetValidationResult: Equatable, Sendable, Codable {
    public var issues: [PresetValidationIssue]
    public var isValid: Bool { !issues.contains { $0.severity == .error } }
    public init(issues: [PresetValidationIssue]) { self.issues = issues }
}

public enum PresetValidator {
    public static func validate(_ document: PresetDocument) -> PresetValidationResult {
        var issues: [PresetValidationIssue] = []
        if document.schemaVersion != "1.0" {
            issues.append(.init(severity: .warning, code: "schema.future", message: "Preset schema \(document.schemaVersion) may require migration."))
        }
        if document.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, code: "id.missing", message: "Preset ID is required."))
        }
        if document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, code: "name.missing", message: "Preset name is required."))
        }
        if document.targets.isEmpty {
            issues.append(.init(severity: .error, code: "target.missing", message: "At least one application target is required."))
        }
        duplicateIssues(document.parameters.map(\.id), code: "parameter.duplicate", noun: "parameter", issues: &issues)
        duplicateIssues(document.macros.map(\.id), code: "macro.duplicate", noun: "macro", issues: &issues)

        let parameterIDs = Set(document.parameters.map(\.id))
        for parameter in document.parameters {
            if parameter.id.isEmpty || parameter.name.isEmpty {
                issues.append(.init(severity: .error, code: "parameter.invalid", message: "Every parameter requires an ID and name."))
            }
            if let minimum = parameter.minimum, let maximum = parameter.maximum, minimum > maximum {
                issues.append(.init(severity: .error, code: "parameter.range", message: "\(parameter.name) has an inverted range."))
            }
            if let defaultValue = parameter.defaultValue, defaultValue.type != parameter.value.type {
                issues.append(.init(severity: .error, code: "parameter.defaultType", message: "\(parameter.name) default value has a different type."))
            }
            switch parameter.value {
            case .choice(let value):
                if parameter.options.isEmpty || !parameter.options.contains(value) {
                    issues.append(.init(severity: .error, code: "choice.invalid", message: "\(parameter.name) must use one of its declared options."))
                }
            case .color(let color):
                if [color.red, color.green, color.blue, color.alpha].contains(where: { !$0.isFinite || !(0...1).contains($0) }) {
                    issues.append(.init(severity: .error, code: "color.invalid", message: "\(parameter.name) color components must be between 0 and 1."))
                }
            case .size(let size):
                if !size.width.isFinite || !size.height.isFinite || size.width <= 0 || size.height <= 0 {
                    issues.append(.init(severity: .error, code: "size.invalid", message: "\(parameter.name) width and height must be positive."))
                }
            case .rectangle(let rectangle):
                if !rectangle.x.isFinite || !rectangle.y.isFinite || !rectangle.width.isFinite || !rectangle.height.isFinite || rectangle.width < 0 || rectangle.height < 0 {
                    issues.append(.init(severity: .error, code: "rectangle.invalid", message: "\(parameter.name) rectangle is invalid."))
                }
            case .gradient(let gradient):
                let sorted = gradient.stops.sorted { $0.location < $1.location }
                let invalidColor = gradient.stops.contains { stop in
                    [stop.color.red, stop.color.green, stop.color.blue, stop.color.alpha].contains(where: { !$0.isFinite || !(0...1).contains($0) })
                }
                let invalidLocation = gradient.stops.contains { !$0.location.isFinite || !(0...1).contains($0.location) }
                let duplicateLocation = zip(sorted, sorted.dropFirst()).contains { abs($0.location - $1.location) < 0.000_001 }
                if gradient.stops.count < 2 || invalidColor || invalidLocation || duplicateLocation {
                    issues.append(.init(severity: .error, code: "gradient.invalid", message: "\(parameter.name) requires at least two valid, uniquely positioned gradient stops."))
                }
            case .curve(let curve):
                if curve.points.count < 2 {
                    issues.append(.init(severity: .error, code: "curve.tooShort", message: "\(parameter.name) requires at least two keyframes."))
                }
                let sorted = curve.points.sorted { $0.time < $1.time }
                if curve.points.contains(where: { !$0.time.isFinite || !$0.value.isFinite }) ||
                    zip(sorted, sorted.dropFirst()).contains(where: { $0.time >= $1.time }) {
                    issues.append(.init(severity: .error, code: "curve.timeOrder", message: "\(parameter.name) has invalid, duplicate or decreasing keyframe times."))
                }
            case .qualityLevel:
                break
            default:
                if let value = parameter.value.numberValue, !value.isFinite {
                    issues.append(.init(severity: .error, code: "parameter.number", message: "\(parameter.name) is not a finite number."))
                }
            }
        }
        for macro in document.macros {
            if macro.minimum >= macro.maximum {
                issues.append(.init(severity: .error, code: "macro.range", message: "\(macro.name) requires minimum < maximum."))
            }
            if !(macro.minimum...macro.maximum).contains(macro.defaultValue) {
                issues.append(.init(severity: .error, code: "macro.default", message: "\(macro.name) default is outside its range."))
            }
            for binding in macro.bindings where !parameterIDs.contains(binding.parameterID) {
                issues.append(.init(severity: .error, code: "macro.binding", message: "\(macro.name) references missing parameter \(binding.parameterID)."))
            }
        }
        for (domain, values) in [
            ("font", document.dependencies.fonts),
            ("effect", document.dependencies.effects),
            ("media", document.dependencies.media),
            ("model", document.dependencies.models),
        ] {
            if values.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                issues.append(.init(severity: .error, code: "dependency.invalid", message: "A \(domain) dependency has no name."))
            }
        }
        if let template = document.template {
            let exposed = Set(template.exposedParameterIDs)
            let locked = Set(template.lockedParameterIDs)
            let missing = exposed.union(locked).subtracting(parameterIDs)
            for parameterID in missing.sorted() {
                issues.append(.init(severity: .error, code: "template.parameter", message: "Template references missing parameter \(parameterID)."))
            }
            for parameterID in exposed.intersection(locked).sorted() {
                issues.append(.init(severity: .error, code: "template.parameterConflict", message: "Template parameter \(parameterID) cannot be both exposed and locked."))
            }
            duplicateIssues(template.mediaSlots.map(\.id), code: "template.slot.duplicate", noun: "media slot", issues: &issues)
            if template.mediaSlots.contains(where: { $0.id.isEmpty || $0.name.isEmpty }) {
                issues.append(.init(severity: .error, code: "template.slot.invalid", message: "Every media slot requires an ID and name."))
            }
            if let time = template.responsiveTime,
               [time.introDuration, time.outroDuration, time.minimumMiddleDuration].contains(where: { !$0.isFinite || $0 < 0 }) {
                issues.append(.init(severity: .error, code: "template.time", message: "Responsive Time durations must be non-negative."))
            }
        } else if document.kind == .editableTemplate {
            issues.append(.init(severity: .warning, code: "template.missing", message: "Editable Template has no template exposure definition."))
        }
        return PresetValidationResult(issues: issues)
    }

    private static func duplicateIssues(_ values: [String], code: String, noun: String, issues: inout [PresetValidationIssue]) {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted {
            issues.append(.init(severity: .error, code: code, message: "Duplicate \(noun) ID: \(value)"))
        }
    }
}

public enum PresetMacroError: Error, LocalizedError, Sendable {
    case missingMacro(String)
    case missingParameter(String)
    case unsupportedValue(String)

    public var errorDescription: String? {
        switch self {
        case .missingMacro(let id): return "Macro not found: \(id)"
        case .missingParameter(let id): return "Macro parameter not found: \(id)"
        case .unsupportedValue(let id): return "Macro cannot modify parameter: \(id)"
        }
    }
}

public enum PresetMacroEngine {
    public static func applying(macroID: String, value: Double, to document: PresetDocument) throws -> PresetDocument {
        guard let macro = document.macros.first(where: { $0.id == macroID }) else { throw PresetMacroError.missingMacro(macroID) }
        var result = document
        let input = min(max(value, macro.minimum), macro.maximum)
        let normalized = (input - macro.minimum) / (macro.maximum - macro.minimum)

        for binding in macro.bindings {
            guard var parameter = result.parameter(id: binding.parameterID) else { throw PresetMacroError.missingParameter(binding.parameterID) }
            let progress = binding.inverted ? 1 - normalized : normalized
            var mapped = binding.outputMinimum + progress * (binding.outputMaximum - binding.outputMinimum)
            if binding.clamp {
                let lower = min(binding.outputMinimum, binding.outputMaximum)
                let upper = max(binding.outputMinimum, binding.outputMaximum)
                mapped = min(max(mapped, lower), upper)
            }
            switch parameter.value {
            case .number:
                parameter.value = .number(mapped)
            case .integer:
                parameter.value = .integer(Int(mapped.rounded()))
            case .angle:
                parameter.value = .angle(mapped)
            case .seed:
                parameter.value = .seed(Int(mapped.rounded()))
            case .curve where binding.component == "valueScale":
                let baseCurve: KeyframeCurve
                if case .curve(let value)? = parameter.defaultValue { baseCurve = value }
                else if case .curve(let value) = parameter.value { baseCurve = value }
                else { throw PresetMacroError.unsupportedValue(binding.parameterID) }
                parameter.value = .curve(KeyframeCurve(points: baseCurve.points.map { point in
                    var updated = point
                    updated.value *= mapped
                    updated.incomingSlope = updated.incomingSlope.map { $0 * mapped }
                    updated.outgoingSlope = updated.outgoingSlope.map { $0 * mapped }
                    return updated
                }, normalizedTime: baseCurve.normalizedTime))
            default:
                throw PresetMacroError.unsupportedValue(binding.parameterID)
            }
            result.setParameter(parameter)
        }
        result.extensions["macro.\(macroID).value"] = String(input)
        return result
    }

    public static func value(macroID: String, in document: PresetDocument) throws -> Double {
        guard let macro = document.macros.first(where: { $0.id == macroID }) else { throw PresetMacroError.missingMacro(macroID) }
        if let stored = document.extensions["macro.\(macroID).value"].flatMap(Double.init) {
            return min(max(stored, macro.minimum), macro.maximum)
        }
        guard let binding = macro.bindings.first,
              let parameter = document.parameter(id: binding.parameterID) else {
            return macro.defaultValue
        }
        let output: Double
        if binding.component == "valueScale",
           case .curve(let current) = parameter.value,
           case .curve(let baseline)? = parameter.defaultValue {
            let pairs = zip(current.points, baseline.points).filter { abs($0.1.value) > 0.000_001 }
            guard let ratio = pairs.map({ $0.0.value / $0.1.value }).first else { return macro.defaultValue }
            output = ratio
        } else if let numeric = parameter.value.numberValue {
            output = numeric
        } else {
            return macro.defaultValue
        }
        let denominator = binding.outputMaximum - binding.outputMinimum
        guard abs(denominator) > 0.000_001 else { return macro.defaultValue }
        var normalized = (output - binding.outputMinimum) / denominator
        if binding.inverted { normalized = 1 - normalized }
        normalized = min(max(normalized, 0), 1)
        return macro.minimum + normalized * (macro.maximum - macro.minimum)
    }
}

public struct PresetRuntimeContext: Equatable, Sendable {
    public var appVersion: String
    public var iOSVersion: String
    public var availableTargets: Set<String>?
    public var availableFonts: Set<String>?
    public var availableEffects: Set<String>?
    public var availableMedia: Set<String>?
    public var availableModels: Set<String>?
    public var availableFeatures: Set<String>?

    public init(
        appVersion: String,
        iOSVersion: String,
        availableTargets: Set<String>? = nil,
        availableFonts: Set<String>? = nil,
        availableEffects: Set<String>? = nil,
        availableMedia: Set<String>? = nil,
        availableModels: Set<String>? = nil,
        availableFeatures: Set<String>? = nil
    ) {
        self.appVersion = appVersion
        self.iOSVersion = iOSVersion
        self.availableTargets = availableTargets
        self.availableFonts = availableFonts
        self.availableEffects = availableEffects
        self.availableMedia = availableMedia
        self.availableModels = availableModels
        self.availableFeatures = availableFeatures
    }
}

public enum PresetCompatibilityEvaluator {
    public static func evaluate(_ document: PresetDocument, context: PresetRuntimeContext) -> PresetValidationResult {
        var issues: [PresetValidationIssue] = []
        for rule in document.compatibility {
            let matches: Bool
            switch rule.kind {
            case .minimumAppVersion: matches = compareVersions(context.appVersion, rule.value) != .orderedAscending
            case .maximumAppVersion: matches = compareVersions(context.appVersion, rule.value) != .orderedDescending
            case .minimumIOSVersion: matches = compareVersions(context.iOSVersion, rule.value) != .orderedAscending
            case .target: matches = context.availableTargets?.contains(rule.value) ?? true
            case .feature: matches = context.availableFeatures?.contains(rule.value) ?? true
            case .aspectRatio, .frameRate, .colorDepth: matches = true
            }
            if !matches {
                issues.append(.init(
                    severity: rule.required ? .error : .warning,
                    code: compatibilityCode(rule.kind),
                    message: "Compatibility requirement is not met: \(rule.kind.rawValue) \(rule.value)"
                ))
            }
        }
        checkDependencies(document.dependencies.fonts, domain: "font", available: context.availableFonts, issues: &issues)
        checkDependencies(document.dependencies.effects, domain: "effect", available: context.availableEffects, issues: &issues)
        checkDependencies(document.dependencies.media, domain: "media", available: context.availableMedia, issues: &issues)
        checkDependencies(document.dependencies.models, domain: "model", available: context.availableModels, issues: &issues)
        return PresetValidationResult(issues: issues)
    }

    private static func checkDependencies(
        _ values: [PresetDependency],
        domain: String,
        available: Set<String>?,
        issues: inout [PresetValidationIssue]
    ) {
        guard let available else { return }
        let normalized = Set(available.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        for dependency in values {
            let key = dependency.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !normalized.contains(key) else { continue }
            issues.append(.init(
                severity: dependency.optional ? .warning : .error,
                code: "dependency.\(domain)",
                message: "Missing \(domain): \(dependency.name)"
            ))
        }
    }

    private static func compatibilityCode(_ kind: CompatibilityRuleKind) -> String {
        switch kind {
        case .minimumIOSVersion: return "compatibility.ios"
        case .minimumAppVersion, .maximumAppVersion: return "compatibility.app"
        case .target: return "compatibility.target"
        case .feature: return "compatibility.feature"
        case .aspectRatio: return "compatibility.aspectRatio"
        case .frameRate: return "compatibility.frameRate"
        case .colorDepth: return "compatibility.colorDepth"
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}

public enum PresetQuery {
    public static func filter(
        _ documents: [PresetDocument],
        text: String,
        kind: PresetKind?,
        target: String?,
        favoriteIDs: Set<String>,
        favoritesOnly: Bool
    ) -> [PresetDocument] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return documents.filter { document in
            if let kind, document.kind != kind { return false }
            if let target, !document.targets.contains(target) { return false }
            if favoritesOnly, !favoriteIDs.contains(document.id) { return false }
            if query.isEmpty { return true }
            let searchable = ([document.name, document.summary, document.author, document.kind.rawValue] + document.tags + document.targets).joined(separator: " ").lowercased()
            return searchable.contains(query)
        }.sorted { lhs, rhs in
            let lhsFavorite = favoriteIDs.contains(lhs.id)
            let rhsFavorite = favoriteIDs.contains(rhs.id)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public struct ShakePresetConfiguration: Equatable, Sendable {
    public var count: Int
    public var amplitude: Double
    public var decay: Double
    public var seed: UInt64
}

public enum PresetAdapterError: Error, LocalizedError, Sendable {
    case wrongTarget(String)
    case missingParameter(String)
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .wrongTarget(let target): return "Preset does not support target: \(target)"
        case .missingParameter(let id): return "Preset is missing parameter: \(id)"
        case .invalidParameter(let id): return "Preset parameter is invalid: \(id)"
        }
    }
}

public enum SpeedPresetAdapter {
    public static func keyframes(from document: PresetDocument, duration: Double) throws -> [SpeedKeyframe] {
        guard document.targets.contains("speed.remap") else { throw PresetAdapterError.wrongTarget("speed.remap") }
        guard case .curve(let curve)? = document.parameter(id: "velocity.curve")?.value else { throw PresetAdapterError.missingParameter("velocity.curve") }
        guard duration.isFinite, duration > 0, curve.points.count >= 2 else { throw PresetAdapterError.invalidParameter("velocity.curve") }
        return curve.points.sorted { $0.time < $1.time }.map { point in
            SpeedKeyframe(
                id: point.id,
                outputTime: curve.normalizedTime ? point.time * duration : point.time,
                velocity: point.value,
                incomingSlope: point.incomingSlope.map { curve.normalizedTime ? $0 / duration : $0 },
                outgoingSlope: point.outgoingSlope.map { curve.normalizedTime ? $0 / duration : $0 }
            )
        }
    }
}

public enum EasingPresetAdapter {
    public static func curve(from document: PresetDocument) throws -> KeyframeCurve {
        guard document.targets.contains("easing.curve") else { throw PresetAdapterError.wrongTarget("easing.curve") }
        guard case .curve(let curve)? = document.parameter(id: "easing.curve")?.value else { throw PresetAdapterError.missingParameter("easing.curve") }
        return curve
    }
}

public enum ShakePresetAdapter {
    public static func configuration(from document: PresetDocument) throws -> ShakePresetConfiguration {
        guard document.targets.contains("camera.shake") else { throw PresetAdapterError.wrongTarget("camera.shake") }
        func number(_ id: String) throws -> Double {
            guard let value = document.parameter(id: id)?.value.numberValue else { throw PresetAdapterError.missingParameter(id) }
            return value
        }
        return ShakePresetConfiguration(
            count: max(1, Int(try number("count").rounded())),
            amplitude: max(0, try number("amplitude")),
            decay: min(max(try number("decay"), 0), 1),
            seed: UInt64(max(0, try number("seed").rounded()))
        )
    }
}

public enum ColorPresetAdapter {
    public static func colors(from document: PresetDocument) throws -> [PresetColor] {
        guard document.targets.contains("color.palette") else { throw PresetAdapterError.wrongTarget("color.palette") }
        guard case .gradient(let gradient)? = document.parameter(id: "palette.colors")?.value else {
            throw PresetAdapterError.missingParameter("palette.colors")
        }
        let stops = gradient.stops.sorted { $0.location < $1.location }
        guard stops.count >= 2 else { throw PresetAdapterError.invalidParameter("palette.colors") }
        return stops.map(\.color)
    }
}

public enum PresetBuiltins {
    public static let impactVelocity = PresetDocument(
        id: "builtin.velocity.impact",
        name: "Impact Velocity",
        summary: "Fast AMV velocity punch with overshoot and recovery.",
        author: "AE Motion",
        kind: .velocity,
        targets: ["speed.remap"],
        tags: ["amv", "impact", "velocity", "speed"],
        parameters: [
            .init(
                id: "velocity.curve",
                name: "Velocity Curve",
                value: .curve(KeyframeCurve(points: [
                    .init(time: 0, value: 1, outgoingSlope: -5),
                    .init(time: 0.22, value: 0.15, incomingSlope: 0, outgoingSlope: 12),
                    .init(time: 0.38, value: 4.5, incomingSlope: 0, outgoingSlope: -7),
                    .init(time: 0.62, value: 0.65, incomingSlope: 0, outgoingSlope: 1.2),
                    .init(time: 1, value: 1, incomingSlope: 0),
                ])),
                defaultValue: .curve(KeyframeCurve(points: [
                    .init(time: 0, value: 1, outgoingSlope: -5),
                    .init(time: 0.22, value: 0.15, incomingSlope: 0, outgoingSlope: 12),
                    .init(time: 0.38, value: 4.5, incomingSlope: 0, outgoingSlope: -7),
                    .init(time: 0.62, value: 0.65, incomingSlope: 0, outgoingSlope: 1.2),
                    .init(time: 1, value: 1, incomingSlope: 0),
                ])),
                keyframeable: true
            ),
        ],
        macros: [
            .init(id: "strength", name: "Strength", minimum: 0.25, maximum: 1.75, defaultValue: 1, bindings: [
                .init(parameterID: "velocity.curve", component: "valueScale", outputMinimum: 0.25, outputMaximum: 1.75),
            ]),
        ]
    )

    public static let easeInOut = PresetDocument(
        id: "builtin.graph.easeInOut",
        name: "Ease In-Out",
        summary: "Balanced smooth cubic movement.",
        author: "AE Motion",
        kind: .graph,
        targets: ["easing.curve"],
        tags: ["graph", "smooth", "easing"],
        parameters: [
            .init(id: "easing.curve", name: "Easing Curve", value: .curve(KeyframeCurve(points: [
                .init(time: 0, value: 0, incomingSlope: 0, outgoingSlope: 0),
                .init(time: 1, value: 1, incomingSlope: 0, outgoingSlope: 0),
            ])), keyframeable: true),
        ]
    )

    public static let handheldShake = PresetDocument(
        id: "builtin.motion.handheld",
        name: "Handheld Drift",
        summary: "Deterministic low-amplitude handheld motion.",
        author: "AE Motion",
        kind: .motion,
        targets: ["camera.shake"],
        tags: ["shake", "camera", "handheld", "amv"],
        parameters: [
            .init(id: "count", name: "Samples", value: .integer(24), minimum: 1, maximum: 500),
            .init(id: "amplitude", name: "Amplitude", value: .number(20), minimum: 0, maximum: 500),
            .init(id: "decay", name: "Decay", value: .number(0.93), minimum: 0, maximum: 1),
            .init(id: "seed", name: "Seed", value: .integer(7), minimum: 0),
        ],
        macros: [
            .init(id: "strength", name: "Strength", minimum: 0, maximum: 1, defaultValue: 0.5, bindings: [
                .init(parameterID: "amplitude", outputMinimum: 0, outputMaximum: 40),
            ]),
        ]
    )

    public static let cinematicPalette = PresetDocument(
        id: "builtin.color.cinematic",
        name: "Cinematic Teal & Amber",
        summary: "A five-color palette for contrast-driven AMV and title design.",
        author: "AE Motion",
        kind: .color,
        targets: ["color.palette"],
        tags: ["color", "cinematic", "teal", "amber"],
        parameters: [
            .init(id: "palette.colors", name: "Palette", value: .gradient(.init(stops: [
                .init(location: 0.00, color: .init(red: 0.02, green: 0.10, blue: 0.13)),
                .init(location: 0.25, color: .init(red: 0.04, green: 0.34, blue: 0.38)),
                .init(location: 0.50, color: .init(red: 0.88, green: 0.76, blue: 0.54)),
                .init(location: 0.75, color: .init(red: 0.92, green: 0.42, blue: 0.16)),
                .init(location: 1.00, color: .init(red: 0.24, green: 0.05, blue: 0.03)),
            ])))
        ]
    )

    public static let all: [PresetDocument] = [impactVelocity, easeInOut, handheldShake, cinematicPalette]
}

public struct PresetDiffEntry: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable { case added, removed, changed }
    public var path: String
    public var kind: Kind
    public var before: String?
    public var after: String?

    public init(path: String, kind: Kind, before: String? = nil, after: String? = nil) {
        self.path = path
        self.kind = kind
        self.before = before
        self.after = after
    }
}

public struct PresetDiffResult: Equatable, Sendable, Codable {
    public var entries: [PresetDiffEntry]
    public var isEmpty: Bool { entries.isEmpty }

    public init(entries: [PresetDiffEntry]) { self.entries = entries }
}

public enum PresetDiff {
    public static func compare(_ before: PresetDocument, _ after: PresetDocument) -> PresetDiffResult {
        var entries: [PresetDiffEntry] = []
        compare("name", before.name, after.name, entries: &entries)
        compare("summary", before.summary, after.summary, entries: &entries)
        compare("author", before.author, after.author, entries: &entries)
        compare("kind", before.kind.rawValue, after.kind.rawValue, entries: &entries)
        compare("targets", before.targets.joined(separator: ","), after.targets.joined(separator: ","), entries: &entries)
        compare("tags", before.tags.joined(separator: ","), after.tags.joined(separator: ","), entries: &entries)

        let oldParameters = Dictionary(uniqueKeysWithValues: before.parameters.map { ($0.id, $0) })
        let newParameters = Dictionary(uniqueKeysWithValues: after.parameters.map { ($0.id, $0) })
        for id in Set(oldParameters.keys).subtracting(Set(newParameters.keys)).sorted() {
            entries.append(.init(path: "parameters.\(id)", kind: .removed, before: oldParameters[id]?.value.displayString))
        }
        for id in Set(newParameters.keys).subtracting(Set(oldParameters.keys)).sorted() {
            entries.append(.init(path: "parameters.\(id)", kind: .added, after: newParameters[id]?.value.displayString))
        }
        for id in Set(oldParameters.keys).intersection(Set(newParameters.keys)).sorted() {
            guard let lhs = oldParameters[id], let rhs = newParameters[id], lhs != rhs else { continue }
            entries.append(.init(path: "parameters.\(id)", kind: .changed, before: lhs.value.displayString, after: rhs.value.displayString))
        }

        let oldMacros = Dictionary(uniqueKeysWithValues: before.macros.map { ($0.id, $0) })
        let newMacros = Dictionary(uniqueKeysWithValues: after.macros.map { ($0.id, $0) })
        for id in Set(oldMacros.keys).subtracting(Set(newMacros.keys)).sorted() {
            entries.append(.init(path: "macros.\(id)", kind: .removed, before: oldMacros[id]?.name))
        }
        for id in Set(newMacros.keys).subtracting(Set(oldMacros.keys)).sorted() {
            entries.append(.init(path: "macros.\(id)", kind: .added, after: newMacros[id]?.name))
        }
        for id in Set(oldMacros.keys).intersection(Set(newMacros.keys)).sorted() where oldMacros[id] != newMacros[id] {
            entries.append(.init(path: "macros.\(id)", kind: .changed, before: oldMacros[id]?.name, after: newMacros[id]?.name))
        }
        return PresetDiffResult(entries: entries)
    }

    private static func compare(_ path: String, _ before: String, _ after: String, entries: inout [PresetDiffEntry]) {
        guard before != after else { return }
        entries.append(.init(path: path, kind: .changed, before: before, after: after))
    }
}

public enum ColorPalettePresetFactory {
    public static func document(
        colors: [PresetColor],
        name: String,
        id: String = "user.\(UUID().uuidString.lowercased())",
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> PresetDocument {
        let normalizedColors: [PresetColor]
        switch colors.count {
        case 0:
            normalizedColors = [
                PresetColor(red: 0, green: 0, blue: 0),
                PresetColor(red: 1, green: 1, blue: 1),
            ]
        case 1:
            normalizedColors = [colors[0], colors[0]]
        default:
            normalizedColors = colors
        }
        let denominator = Double(max(1, normalizedColors.count - 1))
        let stops = normalizedColors.enumerated().map { index, color in
            PresetGradientStop(location: Double(index) / denominator, color: color)
        }
        return PresetDocument(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Color Palette" : name,
            summary: "Created from Color Palette Generator.",
            author: "",
            kind: .color,
            targets: ["color.palette"],
            tags: ["color", "palette", "user"],
            parameters: [
                PresetParameter(
                    id: "palette.colors",
                    name: "Palette",
                    value: .gradient(PresetGradient(stops: stops))
                ),
            ],
            createdAt: timestamp,
            modifiedAt: timestamp
        )
    }
}
