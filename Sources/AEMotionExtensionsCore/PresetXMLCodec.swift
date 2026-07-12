import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum PresetXMLCodecError: Error, LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case invalidRoot
    case parseFailed(String)
    case missingAttribute(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "Preset XML could not be encoded as UTF-8."
        case .invalidRoot: return "The document is not an AE Motion preset."
        case .parseFailed(let message): return "Preset XML parsing failed: \(message)"
        case .missingAttribute(let name): return "Preset XML is missing attribute: \(name)"
        case .invalidValue(let value): return "Preset XML contains an invalid value: \(value)"
        }
    }
}

public enum PresetXMLCodec {
    public static func encode(_ document: PresetDocument) throws -> Data {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        let rootAttributes: [(String, String)] = [
            ("schemaVersion", document.schemaVersion),
            ("id", document.id),
            ("name", document.name),
            ("author", document.author),
            ("kind", document.kind.rawValue),
            ("createdAt", document.createdAt),
            ("modifiedAt", document.modifiedAt),
        ]
        lines.append("<preset\(attributes(rootAttributes))>")
        lines.append("  <summary>\(escape(document.summary))</summary>")

        lines.append("  <targets>")
        for target in document.targets { lines.append("    <target id=\"\(escape(target))\"/>") }
        lines.append("  </targets>")

        lines.append("  <tags>")
        for tag in document.tags { lines.append("    <tag>\(escape(tag))</tag>") }
        lines.append("  </tags>")

        if let preview = document.previewImagePNG {
            lines.append("  <preview encoding=\"base64\">\(preview.base64EncodedString())</preview>")
        }

        lines.append("  <parameters>")
        for parameter in document.parameters {
            let attributes: [(String, String)] = [
                ("id", parameter.id),
                ("name", parameter.name),
                ("type", parameter.value.type.rawValue),
                ("keyframeable", parameter.keyframeable ? "true" : "false"),
                ("minimum", optionalNumber(parameter.minimum)),
                ("maximum", optionalNumber(parameter.maximum)),
                ("group", parameter.group ?? ""),
                ("help", parameter.help ?? ""),
            ]
            lines.append("    <parameter\(self.attributes(attributes))>")
            lines.append(contentsOf: encodeValue(parameter.value, element: "value", indentation: "      "))
            if let defaultValue = parameter.defaultValue {
                lines.append(contentsOf: encodeValue(defaultValue, element: "default", indentation: "      "))
            }
            if !parameter.options.isEmpty {
                lines.append("      <options>")
                for option in parameter.options { lines.append("        <option>\(escape(option))</option>") }
                lines.append("      </options>")
            }
            lines.append("    </parameter>")
        }
        lines.append("  </parameters>")

        lines.append("  <macros>")
        for macro in document.macros {
            let macroAttributes: [(String, String)] = [
                ("id", macro.id), ("name", macro.name),
                ("minimum", number(macro.minimum)), ("maximum", number(macro.maximum)),
                ("default", number(macro.defaultValue)),
            ]
            lines.append("    <macro\(attributes(macroAttributes))>")
            for binding in macro.bindings {
                let bindingAttributes: [(String, String)] = [
                    ("parameterID", binding.parameterID),
                    ("component", binding.component ?? ""),
                    ("outputMinimum", number(binding.outputMinimum)),
                    ("outputMaximum", number(binding.outputMaximum)),
                    ("inverted", binding.inverted ? "true" : "false"),
                    ("clamp", binding.clamp ? "true" : "false"),
                ]
                lines.append("      <binding\(attributes(bindingAttributes))/>")
            }
            lines.append("    </macro>")
        }
        lines.append("  </macros>")

        lines.append("  <dependencies>")
        encodeDependencies(document.dependencies.fonts, kind: "font", lines: &lines)
        encodeDependencies(document.dependencies.effects, kind: "effect", lines: &lines)
        encodeDependencies(document.dependencies.media, kind: "media", lines: &lines)
        encodeDependencies(document.dependencies.models, kind: "model", lines: &lines)
        lines.append("  </dependencies>")

        lines.append("  <compatibility>")
        for rule in document.compatibility {
            let ruleAttributes: [(String, String)] = [
                ("kind", rule.kind.rawValue),
                ("value", rule.value),
                ("required", rule.required ? "true" : "false"),
            ]
            lines.append("    <rule\(attributes(ruleAttributes))/>")
        }
        lines.append("  </compatibility>")

        if let template = document.template {
            lines.append("  <template>")
            lines.append("    <exposedParameters>")
            for parameterID in template.exposedParameterIDs {
                lines.append("      <parameter id=\"\(escape(parameterID))\"/>")
            }
            lines.append("    </exposedParameters>")
            lines.append("    <lockedParameters>")
            for parameterID in template.lockedParameterIDs {
                lines.append("      <parameter id=\"\(escape(parameterID))\"/>")
            }
            lines.append("    </lockedParameters>")
            lines.append("    <mediaSlots>")
            for slot in template.mediaSlots {
                let slotAttributes: [(String, String)] = [
                    ("id", slot.id),
                    ("name", slot.name),
                    ("required", slot.required ? "true" : "false"),
                    ("acceptedTypes", slot.acceptedTypes.joined(separator: ",")),
                    ("defaultResource", slot.defaultResource ?? ""),
                ]
                lines.append("      <slot\(attributes(slotAttributes))/>")
            }
            lines.append("    </mediaSlots>")
            if let responsive = template.responsiveTime {
                let responsiveAttributes: [(String, String)] = [
                    ("introDuration", number(responsive.introDuration)),
                    ("outroDuration", number(responsive.outroDuration)),
                    ("minimumMiddleDuration", number(responsive.minimumMiddleDuration)),
                    ("loopMiddle", responsive.loopMiddle ? "true" : "false"),
                ]
                lines.append("    <responsiveTime\(attributes(responsiveAttributes))/>")
            }
            lines.append("  </template>")
        }

        lines.append("  <extensions>")
        for key in document.extensions.keys.sorted() {
            lines.append("    <entry\(attributes([("key", key), ("value", document.extensions[key] ?? "")]))/>")
        }
        lines.append("  </extensions>")
        lines.append("</preset>")

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw PresetXMLCodecError.invalidUTF8
        }
        return data
    }

    public static func decode(_ data: Data) throws -> PresetDocument {
        let parser = XMLParser(data: data)
        let builder = XMLTreeBuilder()
        parser.delegate = builder
        guard parser.parse() else {
            throw PresetXMLCodecError.parseFailed(parser.parserError?.localizedDescription ?? "Unknown error")
        }
        guard let root = builder.root, root.name == "preset" else {
            throw PresetXMLCodecError.invalidRoot
        }

        let id = try required(root.attributes["id"], name: "id")
        let name = try required(root.attributes["name"], name: "name")
        guard let kind = PresetKind(rawValue: root.attributes["kind"] ?? "") else {
            throw PresetXMLCodecError.invalidValue("kind")
        }

        let targets = root.child("targets")?.children(named: "target").compactMap { $0.attributes["id"] } ?? []
        let tags = root.child("tags")?.children(named: "tag").map(\.text) ?? []
        let parameters = try (root.child("parameters")?.children(named: "parameter") ?? []).map(decodeParameter)
        let macros = try (root.child("macros")?.children(named: "macro") ?? []).map(decodeMacro)
        let dependencies = decodeDependencies(root.child("dependencies"))
        let compatibility = (root.child("compatibility")?.children(named: "rule") ?? []).compactMap { node -> CompatibilityRule? in
            guard let raw = node.attributes["kind"], let kind = CompatibilityRuleKind(rawValue: raw) else { return nil }
            return CompatibilityRule(kind: kind, value: node.attributes["value"] ?? "", required: bool(node.attributes["required"], default: true))
        }
        let extensionPairs: [(String, String)] = (root.child("extensions")?.children(named: "entry") ?? []).compactMap { node in
            guard let key = node.attributes["key"] else { return nil }
            return (key, node.attributes["value"] ?? "")
        }
        let extensions = Dictionary(uniqueKeysWithValues: extensionPairs)
        let preview = root.child("preview").flatMap { Data(base64Encoded: $0.text) }
        let template = decodeTemplate(root.child("template"))

        return PresetDocument(
            schemaVersion: root.attributes["schemaVersion"] ?? "1.0",
            id: id,
            name: name,
            summary: root.child("summary")?.text ?? "",
            author: root.attributes["author"] ?? "",
            kind: kind,
            targets: targets,
            tags: tags,
            parameters: parameters,
            macros: macros,
            dependencies: dependencies,
            compatibility: compatibility,
            template: template,
            previewImagePNG: preview,
            createdAt: root.attributes["createdAt"] ?? "",
            modifiedAt: root.attributes["modifiedAt"] ?? "",
            extensions: extensions
        )
    }

    private static func decodeParameter(_ node: XMLNode) throws -> PresetParameter {
        let id = try required(node.attributes["id"], name: "parameter.id")
        let name = try required(node.attributes["name"], name: "parameter.name")
        let typeRaw = try required(node.attributes["type"], name: "parameter.type")
        guard let type = PresetValueType(rawValue: typeRaw) else { throw PresetXMLCodecError.invalidValue(typeRaw) }
        guard let valueNode = node.child("value") else { throw PresetXMLCodecError.invalidValue("parameter.value") }
        let value = try decodeValue(valueNode, type: type)
        let defaultValue = try node.child("default").map { try decodeValue($0, type: PresetValueType(rawValue: $0.attributes["type"] ?? type.rawValue) ?? type) }
        return PresetParameter(
            id: id,
            name: name,
            value: value,
            defaultValue: defaultValue,
            minimum: double(node.attributes["minimum"]),
            maximum: double(node.attributes["maximum"]),
            options: node.child("options")?.children(named: "option").map(\.text) ?? [],
            keyframeable: bool(node.attributes["keyframeable"]),
            group: nonempty(node.attributes["group"]),
            help: nonempty(node.attributes["help"])
        )
    }

    private static func decodeMacro(_ node: XMLNode) throws -> PresetMacro {
        PresetMacro(
            id: try required(node.attributes["id"], name: "macro.id"),
            name: try required(node.attributes["name"], name: "macro.name"),
            minimum: double(node.attributes["minimum"]) ?? 0,
            maximum: double(node.attributes["maximum"]) ?? 1,
            defaultValue: double(node.attributes["default"]) ?? 0,
            bindings: node.children(named: "binding").compactMap { binding in
                guard let parameterID = binding.attributes["parameterID"] else { return nil }
                return PresetMacroBinding(
                    parameterID: parameterID,
                    component: nonempty(binding.attributes["component"]),
                    outputMinimum: double(binding.attributes["outputMinimum"]) ?? 0,
                    outputMaximum: double(binding.attributes["outputMaximum"]) ?? 1,
                    inverted: bool(binding.attributes["inverted"]),
                    clamp: bool(binding.attributes["clamp"], default: true)
                )
            }
        )
    }

    private static func decodeTemplate(_ node: XMLNode?) -> EditableTemplateDefinition? {
        guard let node else { return nil }
        let exposed = node.child("exposedParameters")?.children(named: "parameter").compactMap { $0.attributes["id"] } ?? []
        let locked = node.child("lockedParameters")?.children(named: "parameter").compactMap { $0.attributes["id"] } ?? []
        let slots = node.child("mediaSlots")?.children(named: "slot").compactMap { slot -> PresetMediaSlot? in
            guard let id = slot.attributes["id"], let name = slot.attributes["name"] else { return nil }
            let types = (slot.attributes["acceptedTypes"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return PresetMediaSlot(
                id: id,
                name: name,
                required: bool(slot.attributes["required"], default: true),
                acceptedTypes: types,
                defaultResource: nonempty(slot.attributes["defaultResource"])
            )
        } ?? []
        let responsive = node.child("responsiveTime").map { value in
            PresetResponsiveTime(
                introDuration: double(value.attributes["introDuration"]) ?? 0,
                outroDuration: double(value.attributes["outroDuration"]) ?? 0,
                minimumMiddleDuration: double(value.attributes["minimumMiddleDuration"]) ?? 0,
                loopMiddle: bool(value.attributes["loopMiddle"])
            )
        }
        return EditableTemplateDefinition(
            exposedParameterIDs: exposed,
            lockedParameterIDs: locked,
            mediaSlots: slots,
            responsiveTime: responsive
        )
    }

    private static func decodeDependencies(_ node: XMLNode?) -> DependencyManifest {
        func list(_ kind: String) -> [PresetDependency] {
            node?.children(named: kind).compactMap { child in
                guard let name = child.attributes["name"] else { return nil }
                return PresetDependency(
                    name: name,
                    minimumVersion: nonempty(child.attributes["minimumVersion"]),
                    optional: bool(child.attributes["optional"])
                )
            } ?? []
        }
        return DependencyManifest(fonts: list("font"), effects: list("effect"), media: list("media"), models: list("model"))
    }

    private static func encodeDependencies(_ values: [PresetDependency], kind: String, lines: inout [String]) {
        for value in values {
            let dependencyAttributes: [(String, String)] = [
                ("name", value.name),
                ("minimumVersion", value.minimumVersion ?? ""),
                ("optional", value.optional ? "true" : "false"),
            ]
            lines.append("    <\(kind)\(attributes(dependencyAttributes))/>")
        }
    }

    private static func encodeValue(_ value: PresetValue, element: String, indentation: String) -> [String] {
        switch value {
        case .number(let value): return ["\(indentation)<\(element) type=\"number\">\(number(value))</\(element)>"]
        case .integer(let value): return ["\(indentation)<\(element) type=\"integer\">\(value)</\(element)>"]
        case .boolean(let value): return ["\(indentation)<\(element) type=\"boolean\">\(value ? "true" : "false")</\(element)>"]
        case .text(let value): return ["\(indentation)<\(element) type=\"text\">\(escape(value))</\(element)>"]
        case .choice(let value): return ["\(indentation)<\(element) type=\"choice\">\(escape(value))</\(element)>"]
        case .color(let value):
            return ["\(indentation)<\(element)\(attributes([("type", "color"), ("red", number(value.red)), ("green", number(value.green)), ("blue", number(value.blue)), ("alpha", number(value.alpha))]))/>"]
        case .point(let value):
            return ["\(indentation)<\(element)\(attributes([("type", "point"), ("x", number(value.x)), ("y", number(value.y))]))/>"]
        case .angle(let value):
            return ["\(indentation)<\(element) type=\"angle\">\(number(value))</\(element)>"]
        case .size(let value):
            return ["\(indentation)<\(element)\(attributes([("type", "size"), ("width", number(value.width)), ("height", number(value.height))]))/>"]
        case .rectangle(let value):
            return ["\(indentation)<\(element)\(attributes([("type", "rectangle"), ("x", number(value.x)), ("y", number(value.y)), ("width", number(value.width)), ("height", number(value.height))]))/>"]
        case .gradient(let gradient):
            var lines = ["\(indentation)<\(element) type=\"gradient\">"]
            for stop in gradient.stops {
                let stopAttributes: [(String, String)] = [
                    ("id", stop.id.uuidString),
                    ("location", number(stop.location)),
                    ("red", number(stop.color.red)),
                    ("green", number(stop.color.green)),
                    ("blue", number(stop.color.blue)),
                    ("alpha", number(stop.color.alpha)),
                ]
                lines.append("\(indentation)  <stop\(attributes(stopAttributes))/>")
            }
            lines.append("\(indentation)</\(element)>")
            return lines
        case .curve(let curve):
            var lines = ["\(indentation)<\(element) type=\"curve\" normalizedTime=\"\(curve.normalizedTime ? "true" : "false")\">"]
            for point in curve.points {
                let keyframeAttributes: [(String, String)] = [
                    ("id", point.id.uuidString),
                    ("time", number(point.time)),
                    ("value", number(point.value)),
                    ("incomingSlope", optionalNumber(point.incomingSlope)),
                    ("outgoingSlope", optionalNumber(point.outgoingSlope)),
                    ("interpolation", point.interpolation.rawValue),
                ]
                lines.append("\(indentation)  <keyframe\(attributes(keyframeAttributes))/>")
            }
            lines.append("\(indentation)</\(element)>")
            return lines
        case .layerReference(let value):
            return ["\(indentation)<\(element) type=\"layerReference\">\(escape(value))</\(element)>"]
        case .maskReference(let value):
            return ["\(indentation)<\(element) type=\"maskReference\">\(escape(value))</\(element)>"]
        case .mapReference(let value):
            return ["\(indentation)<\(element) type=\"mapReference\">\(escape(value))</\(element)>"]
        case .audioBandReference(let value):
            return ["\(indentation)<\(element) type=\"audioBandReference\">\(escape(value))</\(element)>"]
        case .seed(let value):
            return ["\(indentation)<\(element) type=\"seed\">\(value)</\(element)>"]
        case .qualityLevel(let value):
            return ["\(indentation)<\(element) type=\"qualityLevel\">\(value.rawValue)</\(element)>"]
        }
    }

    private static func decodeValue(_ node: XMLNode, type: PresetValueType) throws -> PresetValue {
        switch type {
        case .number:
            guard let value = Double(node.text) else { throw PresetXMLCodecError.invalidValue(node.text) }
            return .number(value)
        case .integer:
            guard let value = Int(node.text) else { throw PresetXMLCodecError.invalidValue(node.text) }
            return .integer(value)
        case .boolean: return .boolean(bool(node.text))
        case .text: return .text(node.text)
        case .choice: return .choice(node.text)
        case .color:
            return .color(PresetColor(
                red: double(node.attributes["red"]) ?? 0,
                green: double(node.attributes["green"]) ?? 0,
                blue: double(node.attributes["blue"]) ?? 0,
                alpha: double(node.attributes["alpha"]) ?? 1
            ))
        case .point:
            return .point(PresetPoint(x: double(node.attributes["x"]) ?? 0, y: double(node.attributes["y"]) ?? 0))
        case .angle:
            guard let value = Double(node.text) else { throw PresetXMLCodecError.invalidValue(node.text) }
            return .angle(value)
        case .size:
            return .size(PresetSize(width: double(node.attributes["width"]) ?? 0, height: double(node.attributes["height"]) ?? 0))
        case .rectangle:
            return .rectangle(PresetRectangle(
                x: double(node.attributes["x"]) ?? 0,
                y: double(node.attributes["y"]) ?? 0,
                width: double(node.attributes["width"]) ?? 0,
                height: double(node.attributes["height"]) ?? 0
            ))
        case .gradient:
            return .gradient(PresetGradient(stops: node.children(named: "stop").compactMap { stop in
                guard let location = double(stop.attributes["location"]) else { return nil }
                return PresetGradientStop(
                    id: UUID(uuidString: stop.attributes["id"] ?? "") ?? UUID(),
                    location: location,
                    color: PresetColor(
                        red: double(stop.attributes["red"]) ?? 0,
                        green: double(stop.attributes["green"]) ?? 0,
                        blue: double(stop.attributes["blue"]) ?? 0,
                        alpha: double(stop.attributes["alpha"]) ?? 1
                    )
                )
            }))
        case .curve:
            return .curve(KeyframeCurve(
                points: node.children(named: "keyframe").compactMap { keyframe in
                    guard let time = double(keyframe.attributes["time"]), let value = double(keyframe.attributes["value"]) else { return nil }
                    return PresetKeyframe(
                        id: UUID(uuidString: keyframe.attributes["id"] ?? "") ?? UUID(),
                        time: time,
                        value: value,
                        incomingSlope: double(keyframe.attributes["incomingSlope"]),
                        outgoingSlope: double(keyframe.attributes["outgoingSlope"]),
                        interpolation: PresetInterpolation(rawValue: keyframe.attributes["interpolation"] ?? "") ?? .bezier
                    )
                },
                normalizedTime: bool(node.attributes["normalizedTime"], default: true)
            ))
        case .layerReference: return .layerReference(node.text)
        case .maskReference: return .maskReference(node.text)
        case .mapReference: return .mapReference(node.text)
        case .audioBandReference: return .audioBandReference(node.text)
        case .seed:
            guard let value = Int(node.text) else { throw PresetXMLCodecError.invalidValue(node.text) }
            return .seed(value)
        case .qualityLevel:
            guard let value = PresetQualityLevel(rawValue: node.text) else { throw PresetXMLCodecError.invalidValue(node.text) }
            return .qualityLevel(value)
        }
    }

    private static func required(_ value: String?, name: String) throws -> String {
        guard let value, !value.isEmpty else { throw PresetXMLCodecError.missingAttribute(name) }
        return value
    }

    private static func attributes(_ values: [(String, String)]) -> String {
        values.filter { !$0.1.isEmpty }.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func optionalNumber(_ value: Double?) -> String { value.map(number) ?? "" }
    private static func double(_ value: String?) -> Double? { value.flatMap(Double.init) }
    private static func bool(_ value: String?, default defaultValue: Bool = false) -> Bool {
        guard let value else { return defaultValue }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private final class XMLNode {
    let name: String
    var attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
    func children(named name: String) -> [XMLNode] { children.filter { $0.name == name } }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let node = XMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let node = stack.last { node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        _ = stack.popLast()
    }
}
