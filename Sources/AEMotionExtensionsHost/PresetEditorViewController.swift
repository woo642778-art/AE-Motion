#if canImport(UIKit) && canImport(PhotosUI)
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AEMotionExtensionsCore

@MainActor
final class PresetEditorViewController: UIViewController, PHPickerViewControllerDelegate {
    enum Mode { case create, edit }

    private let environment = PresetLibraryEnvironment.shared
    private var document: PresetDocument
    private let mode: Mode

    private let nameField = ExtensionUI.field("Preset name")
    private let authorField = ExtensionUI.field("Author")
    private let summaryView = UITextView()
    private let tagsField = ExtensionUI.field("Tags separated by commas")
    private let targetField = ExtensionUI.field("Target, e.g. speed.remap")
    private let kindButton = UIButton(type: .system)
    private let previewView = UIImageView()
    private let parameterStack = UIStackView()
    private let macroStack = UIStackView()
    private let dependencyStack = UIStackView()
    private let validationLabel = ExtensionUI.label("")
    private let compatibilityView = UITextView()
    private let templateStack = UIStackView()
    private let exposedField = ExtensionUI.field("Exposed parameter IDs, comma separated")
    private let lockedField = ExtensionUI.field("Locked parameter IDs, comma separated")
    private let mediaSlotsView = UITextView()
    private let introField = ExtensionUI.field("Responsive intro seconds", value: "0")
    private let outroField = ExtensionUI.field("Responsive outro seconds", value: "0")
    private let middleField = ExtensionUI.field("Minimum middle seconds", value: "0")
    private let loopMiddleSwitch = UISwitch()
    private var editorErrors: [String] = []

    init(document: PresetDocument, mode: Mode) {
        self.document = document
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode == .create ? "New Preset" : "Edit Preset"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))

        summaryView.font = .preferredFont(forTextStyle: .body)
        summaryView.layer.borderWidth = 1 / UIScreen.main.scale
        summaryView.layer.borderColor = UIColor.separator.cgColor
        summaryView.layer.cornerRadius = 8
        summaryView.heightAnchor.constraint(equalToConstant: 100).isActive = true

        previewView.contentMode = .scaleAspectFit
        previewView.backgroundColor = .secondarySystemBackground
        previewView.layer.cornerRadius = 12
        previewView.clipsToBounds = true
        previewView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        for textView in [compatibilityView, mediaSlotsView] {
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.layer.borderWidth = 1 / UIScreen.main.scale
            textView.layer.borderColor = UIColor.separator.cgColor
            textView.layer.cornerRadius = 8
            textView.heightAnchor.constraint(equalToConstant: 130).isActive = true
        }
        templateStack.axis = .vertical
        templateStack.spacing = 8
        templateStack.addArrangedSubview(exposedField)
        templateStack.addArrangedSubview(lockedField)
        templateStack.addArrangedSubview(ExtensionUI.label("Media slots: id|name|required|UTType1,UTType2|defaultResource — one slot per line.", style: .footnote))
        templateStack.addArrangedSubview(mediaSlotsView)
        templateStack.addArrangedSubview(introField)
        templateStack.addArrangedSubview(outroField)
        templateStack.addArrangedSubview(middleField)
        templateStack.addArrangedSubview(ExtensionUI.labeledSwitch("Loop responsive middle section", control: loopMiddleSwitch))

        for stack in [parameterStack, macroStack, dependencyStack] {
            stack.axis = .vertical
            stack.spacing = 8
        }

        kindButton.configuration = .tinted()
        updateKindMenu()

        let previewButton = ExtensionUI.secondaryButton("Choose Preview Image", action: UIAction { [weak self] _ in self?.choosePreview() })
        let addParameter = ExtensionUI.secondaryButton("Add Parameter", action: UIAction { [weak self] _ in self?.editParameter(nil, index: nil) })
        let addMacro = ExtensionUI.secondaryButton("Add Macro", action: UIAction { [weak self] _ in self?.editMacro(nil, index: nil) })
        let addDependency = ExtensionUI.secondaryButton("Add Dependency", action: UIAction { [weak self] _ in self?.editDependency() })

        let stack = ExtensionUI.stack([
            ExtensionUI.label("Metadata", style: .headline),
            nameField,
            authorField,
            summaryView,
            tagsField,
            targetField,
            kindButton,
            previewView,
            previewButton,
            ExtensionUI.label("Parameters", style: .headline),
            parameterStack,
            addParameter,
            ExtensionUI.label("Macro Controls", style: .headline),
            macroStack,
            addMacro,
            ExtensionUI.label("Dependencies", style: .headline),
            dependencyStack,
            addDependency,
            ExtensionUI.label("Compatibility Rules", style: .headline),
            ExtensionUI.label("Format: ruleKind|value|required — one rule per line. Example: minimumIOSVersion|17.0|true", style: .footnote),
            compatibilityView,
            ExtensionUI.label("Editable Template", style: .headline),
            templateStack,
            validationLabel,
            ExtensionUI.label("XML schema 1.0 preserves typed values, curves, macros and dependency metadata. Unsupported or broken files are quarantined instead of loaded into the active library.", style: .footnote),
        ])
        ExtensionUI.installScrollStack(stack, in: self)
        populate()
    }

    private func populate() {
        nameField.text = document.name
        authorField.text = document.author
        summaryView.text = document.summary
        tagsField.text = document.tags.joined(separator: ", ")
        targetField.text = document.targets.joined(separator: ", ")
        compatibilityView.text = document.compatibility.map { "\($0.kind.rawValue)|\($0.value)|\($0.required)" }.joined(separator: "\n")
        if let template = document.template {
            exposedField.text = template.exposedParameterIDs.joined(separator: ", ")
            lockedField.text = template.lockedParameterIDs.joined(separator: ", ")
            mediaSlotsView.text = template.mediaSlots.map { slot in
                [slot.id, slot.name, String(slot.required), slot.acceptedTypes.joined(separator: ","), slot.defaultResource ?? ""].joined(separator: "|")
            }.joined(separator: "\n")
            introField.text = String(template.responsiveTime?.introDuration ?? 0)
            outroField.text = String(template.responsiveTime?.outroDuration ?? 0)
            middleField.text = String(template.responsiveTime?.minimumMiddleDuration ?? 0)
            loopMiddleSwitch.isOn = template.responsiveTime?.loopMiddle ?? false
        }
        if let data = document.previewImagePNG { previewView.image = UIImage(data: data) }
        updateTemplateVisibility()
        rebuildLists()
        validateDraft()
    }

    private func updateKindMenu() {
        kindButton.setTitle("Type: \(document.kind.rawValue)", for: .normal)
        kindButton.menu = UIMenu(children: PresetKind.allCases.map { kind in
            UIAction(title: kind.rawValue.capitalized, state: kind == document.kind ? .on : .off) { [weak self] _ in
                self?.document.kind = kind
                self?.updateKindMenu()
                self?.updateTemplateVisibility()
                self?.validateDraft()
            }
        })
        kindButton.showsMenuAsPrimaryAction = true
    }

    private func updateTemplateVisibility() {
        templateStack.isHidden = document.kind != .editableTemplate
    }

    private func rebuildLists() {
        parameterStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, parameter) in document.parameters.enumerated() {
            parameterStack.addArrangedSubview(itemButton(
                title: parameter.name,
                subtitle: "\(parameter.id) · \(parameter.value.type.rawValue) · \(parameter.value.displayString)",
                edit: { [weak self] in self?.editParameter(parameter, index: index) },
                delete: { [weak self] in self?.document.parameters.remove(at: index); self?.rebuildLists(); self?.validateDraft() }
            ))
        }
        if document.parameters.isEmpty { parameterStack.addArrangedSubview(emptyItem("No parameters.")) }

        macroStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, macro) in document.macros.enumerated() {
            macroStack.addArrangedSubview(itemButton(
                title: macro.name,
                subtitle: "\(macro.bindings.count) binding(s) · \(macro.minimum)...\(macro.maximum)",
                edit: { [weak self] in self?.editMacro(macro, index: index) },
                delete: { [weak self] in self?.document.macros.remove(at: index); self?.rebuildLists(); self?.validateDraft() }
            ))
        }
        if document.macros.isEmpty { macroStack.addArrangedSubview(emptyItem("No macro controls.")) }

        dependencyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var dependencyCount = 0
        func addDependencies(_ kind: String, _ values: [PresetDependency]) {
            for (index, dependency) in values.enumerated() {
                dependencyCount += 1
                dependencyStack.addArrangedSubview(itemButton(
                    title: "\(kind): \(dependency.name)",
                    subtitle: "\(dependency.minimumVersion.map { "Minimum \($0)" } ?? "Any version")\(dependency.optional ? " · Optional" : " · Required")",
                    edit: { [weak self] in self?.editDependency(kind: kind, index: index, existing: dependency) },
                    delete: { [weak self] in self?.removeDependency(kind: kind, index: index) }
                ))
            }
        }
        addDependencies("Font", document.dependencies.fonts)
        addDependencies("Effect", document.dependencies.effects)
        addDependencies("Media", document.dependencies.media)
        addDependencies("Model", document.dependencies.models)
        if dependencyCount == 0 { dependencyStack.addArrangedSubview(emptyItem("No dependencies.")) }
    }

    private func itemButton(title: String, subtitle: String, edit: @escaping () -> Void, delete: @escaping () -> Void) -> UIView {
        let titleLabel = ExtensionUI.label(title, style: .headline)
        let subtitleLabel = ExtensionUI.label(subtitle, style: .footnote)
        subtitleLabel.textColor = .secondaryLabel
        let labels = ExtensionUI.stack([titleLabel, subtitleLabel], spacing: 2)
        let editButton = UIButton(type: .system, primaryAction: UIAction(title: "Edit") { _ in edit() })
        let deleteButton = UIButton(type: .system, primaryAction: UIAction(title: "Delete", attributes: .destructive) { _ in delete() })
        let actions = ExtensionUI.horizontalStack([editButton, deleteButton])
        actions.distribution = .fillEqually
        let result = ExtensionUI.stack([labels, actions], spacing: 6)
        result.isLayoutMarginsRelativeArrangement = true
        result.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        result.backgroundColor = .secondarySystemBackground
        result.layer.cornerRadius = 10
        return result
    }

    private func emptyItem(_ text: String) -> UIView {
        let label = ExtensionUI.label(text, style: .footnote)
        label.textColor = .secondaryLabel
        return label
    }

    private func editParameter(_ parameter: PresetParameter?, index: Int?) {
        let editor = PresetParameterEditorViewController(parameter: parameter) { [weak self] result in
            guard let self else { return }
            if let index { self.document.parameters[index] = result } else { self.document.parameters.append(result) }
            self.rebuildLists()
            self.validateDraft()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func editMacro(_ macro: PresetMacro?, index: Int?) {
        let editor = PresetMacroEditorViewController(macro: macro, parameters: document.parameters) { [weak self] result in
            guard let self else { return }
            if let index { self.document.macros[index] = result } else { self.document.macros.append(result) }
            self.rebuildLists()
            self.validateDraft()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func editDependency(kind: String? = nil, index: Int? = nil, existing: PresetDependency? = nil) {
        let alert = UIAlertController(title: existing == nil ? "Add Dependency" : "Edit Dependency", message: "Use Font, Effect, Media or Model as the first field.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "Kind: Font / Effect / Media / Model"; field.text = kind }
        alert.addTextField { field in field.placeholder = "Name"; field.text = existing?.name }
        alert.addTextField { field in field.placeholder = "Minimum version (optional)"; field.text = existing?.minimumVersion }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save Required", style: .default) { [weak self, weak alert] _ in
            self?.storeDependency(from: alert, optional: false, originalKind: kind, originalIndex: index)
        })
        alert.addAction(UIAlertAction(title: "Save Optional", style: .default) { [weak self, weak alert] _ in
            self?.storeDependency(from: alert, optional: true, originalKind: kind, originalIndex: index)
        })
        present(alert, animated: true)
    }

    private func storeDependency(from alert: UIAlertController?, optional: Bool, originalKind: String?, originalIndex: Int?) {
        guard let fields = alert?.textFields, fields.count == 3 else { return }
        let kind = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let name = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = fields[2].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ExtensionUI.alert(title: "Dependency name required", message: "Enter a font, effect, media or model name.", from: self)
            return
        }
        if let originalKind, let originalIndex { removeDependency(kind: originalKind, index: originalIndex, rebuild: false) }
        let dependency = PresetDependency(name: name, minimumVersion: version?.isEmpty == false ? version : nil, optional: optional)
        switch kind {
        case "font": document.dependencies.fonts.append(dependency)
        case "effect": document.dependencies.effects.append(dependency)
        case "media": document.dependencies.media.append(dependency)
        case "model": document.dependencies.models.append(dependency)
        default:
            ExtensionUI.alert(title: "Unknown dependency type", message: "Use Font, Effect, Media or Model.", from: self)
            return
        }
        rebuildLists()
        validateDraft()
    }

    private func removeDependency(kind: String, index: Int, rebuild: Bool = true) {
        switch kind.lowercased() {
        case "font" where document.dependencies.fonts.indices.contains(index): document.dependencies.fonts.remove(at: index)
        case "effect" where document.dependencies.effects.indices.contains(index): document.dependencies.effects.remove(at: index)
        case "media" where document.dependencies.media.indices.contains(index): document.dependencies.media.remove(at: index)
        case "model" where document.dependencies.models.indices.contains(index): document.dependencies.models.remove(at: index)
        default: return
        }
        if rebuild { rebuildLists(); validateDraft() }
    }

    private func choosePreview() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                if let data, let image = UIImage(data: data),
                   let png = image.preparingThumbnail(of: CGSize(width: 720, height: 720))?.pngData() ?? image.pngData() {
                    self.document.previewImagePNG = png
                    self.previewView.image = UIImage(data: png)
                } else if let errorMessage {
                    ExtensionUI.alert(title: "Preview import failed", message: errorMessage, from: self)
                } else {
                    ExtensionUI.alert(title: "Preview import failed", message: "The selected image could not be decoded.", from: self)
                }
            }
        }
    }

    private func updateDocumentFromFields() {
        editorErrors.removeAll()
        document.name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        document.author = authorField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        document.summary = summaryView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        document.tags = split(tagsField.text)
        document.targets = split(targetField.text)
        document.compatibility = parseCompatibility()
        if document.kind == .editableTemplate {
            document.template = parseTemplate()
        } else {
            document.template = nil
        }
        document.modifiedAt = ISO8601DateFormatter().string(from: Date())
    }

    private func parseCompatibility() -> [CompatibilityRule] {
        var rules: [CompatibilityRule] = []
        for (index, line) in compatibilityView.text.split(whereSeparator: { $0.isNewline }).enumerated() {
            let columns = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard columns.count >= 2,
                  let kind = CompatibilityRuleKind(rawValue: columns[0]),
                  !columns[1].isEmpty else {
                editorErrors.append("Compatibility line \(index + 1) is invalid.")
                continue
            }
            let required = columns.count < 3 || ["1", "true", "yes", "required"].contains(columns[2].lowercased())
            rules.append(.init(kind: kind, value: columns[1], required: required))
        }
        return rules
    }

    private func parseTemplate() -> EditableTemplateDefinition {
        var slots: [PresetMediaSlot] = []
        for (index, line) in mediaSlotsView.text.split(whereSeparator: { $0.isNewline }).enumerated() {
            let columns = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard columns.count >= 2, !columns[0].isEmpty, !columns[1].isEmpty else {
                editorErrors.append("Media slot line \(index + 1) is invalid.")
                continue
            }
            let required = columns.count < 3 || !["0", "false", "no", "optional"].contains(columns[2].lowercased())
            let types = columns.count > 3 ? columns[3].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } : []
            let defaultResource = columns.count > 4 && !columns[4].isEmpty ? columns[4] : nil
            slots.append(.init(id: columns[0], name: columns[1], required: required, acceptedTypes: types, defaultResource: defaultResource))
        }
        let intro = parseNonnegative(introField, name: "Responsive intro")
        let outro = parseNonnegative(outroField, name: "Responsive outro")
        let middle = parseNonnegative(middleField, name: "Minimum middle")
        return EditableTemplateDefinition(
            exposedParameterIDs: split(exposedField.text),
            lockedParameterIDs: split(lockedField.text),
            mediaSlots: slots,
            responsiveTime: PresetResponsiveTime(
                introDuration: intro,
                outroDuration: outro,
                minimumMiddleDuration: middle,
                loopMiddle: loopMiddleSwitch.isOn
            )
        )
    }

    private func parseNonnegative(_ field: UITextField, name: String) -> Double {
        guard let value = Double(field.text ?? ""), value >= 0 else {
            editorErrors.append("\(name) must be a non-negative number.")
            return 0
        }
        return value
    }

    private func split(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func validateDraft() {
        updateDocumentFromFields()
        let result = PresetValidator.validate(document)
        let messages = editorErrors + result.issues.map(\.message)
        validationLabel.text = messages.isEmpty ? "Preset is valid." : messages.map { "• \($0)" }.joined(separator: "\n")
        validationLabel.textColor = result.isValid && editorErrors.isEmpty ? .systemGreen : .systemRed
    }

    @objc private func save() {
        updateDocumentFromFields()
        let validation = PresetValidator.validate(document)
        guard validation.isValid, editorErrors.isEmpty else {
            let messages = editorErrors + validation.issues.map(\.message)
            ExtensionUI.alert(title: "Preset is not valid", message: messages.joined(separator: "\n"), from: self)
            return
        }
        do {
            try environment.save(document)
            navigationController?.popViewController(animated: true)
        } catch { ExtensionUI.alert(title: "Save failed", message: error.localizedDescription, from: self) }
    }
}

@MainActor
final class PresetParameterEditorViewController: UIViewController {
    private var parameter: PresetParameter
    private let completion: (PresetParameter) -> Void
    private let idField = ExtensionUI.field("Parameter ID")
    private let nameField = ExtensionUI.field("Display name")
    private let valueField = ExtensionUI.field("Value")
    private let secondValueField = ExtensionUI.field("Second value / Y")
    private let minField = ExtensionUI.field("Minimum (optional)")
    private let maxField = ExtensionUI.field("Maximum (optional)")
    private let optionsField = ExtensionUI.field("Options separated by commas")
    private let keyframeSwitch = UISwitch()
    private let typeButton = UIButton(type: .system)
    private let curveView = UITextView()

    init(parameter: PresetParameter?, completion: @escaping (PresetParameter) -> Void) {
        self.parameter = parameter ?? PresetParameter(id: "parameter.\(UUID().uuidString.prefix(8).lowercased())", name: "Parameter", value: .number(0))
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Parameter"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        curveView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        curveView.layer.borderColor = UIColor.separator.cgColor
        curveView.layer.borderWidth = 1 / UIScreen.main.scale
        curveView.layer.cornerRadius = 8
        curveView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        typeButton.configuration = .tinted()
        configureTypeMenu()
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            idField, nameField, typeButton, valueField, secondValueField,
            minField, maxField, optionsField,
            ExtensionUI.labeledSwitch("Keyframeable", control: keyframeSwitch),
            ExtensionUI.label("Curve format: time,value,inSlope,outSlope — one keyframe per line. Leave a slope blank to use automatic interpolation.", style: .footnote),
            curveView,
        ]), in: self)
        populate()
    }

    private func populate() {
        idField.text = parameter.id
        nameField.text = parameter.name
        minField.text = parameter.minimum.map { String($0) }
        maxField.text = parameter.maximum.map { String($0) }
        optionsField.text = parameter.options.joined(separator: ", ")
        keyframeSwitch.isOn = parameter.keyframeable
        switch parameter.value {
        case .number(let value): valueField.text = String(value)
        case .integer(let value): valueField.text = String(value)
        case .boolean(let value): valueField.text = value ? "true" : "false"
        case .text(let value), .choice(let value), .layerReference(let value),
             .maskReference(let value), .mapReference(let value), .audioBandReference(let value):
            valueField.text = value
        case .color(let value): valueField.text = "\(value.red),\(value.green),\(value.blue),\(value.alpha)"
        case .point(let value): valueField.text = String(value.x); secondValueField.text = String(value.y)
        case .angle(let value): valueField.text = String(value)
        case .size(let value): valueField.text = String(value.width); secondValueField.text = String(value.height)
        case .rectangle(let value): valueField.text = "\(value.x),\(value.y),\(value.width),\(value.height)"
        case .gradient(let gradient):
            curveView.text = gradient.stops.map { stop in
                "\(stop.location),\(stop.color.red),\(stop.color.green),\(stop.color.blue),\(stop.color.alpha)"
            }.joined(separator: "\n")
        case .curve(let curve):
            curveView.text = curve.points.map { point in
                [String(point.time), String(point.value), point.incomingSlope.map { String($0) } ?? "", point.outgoingSlope.map { String($0) } ?? ""].joined(separator: ",")
            }.joined(separator: "\n")
        case .seed(let value): valueField.text = String(value)
        case .qualityLevel(let value): valueField.text = value.rawValue
        }
        updateVisibility()
    }

    private func configureTypeMenu() {
        typeButton.setTitle("Type: \(parameter.value.type.rawValue)", for: .normal)
        typeButton.menu = UIMenu(children: PresetValueType.allCases.map { type in
            UIAction(title: type.rawValue.capitalized, state: type == self.parameter.value.type ? .on : .off) { [weak self] _ in
                self?.parameter.value = Self.defaultValue(for: type)
                self?.configureTypeMenu()
                self?.populate()
            }
        })
        typeButton.showsMenuAsPrimaryAction = true
    }

    private func updateVisibility() {
        let type = parameter.value.type
        curveView.isHidden = ![.curve, .gradient].contains(type)
        secondValueField.isHidden = ![.point, .size].contains(type)
        valueField.isHidden = [.curve, .gradient].contains(type)
        optionsField.isHidden = type != .choice
        switch type {
        case .point: secondValueField.placeholder = "Y"
        case .size: secondValueField.placeholder = "Height"
        default: secondValueField.placeholder = "Second value / Y"
        }
    }

    @objc private func done() {
        parameter.id = idField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        parameter.name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        parameter.minimum = Double(minField.text ?? "")
        parameter.maximum = Double(maxField.text ?? "")
        parameter.options = (optionsField.text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        parameter.keyframeable = keyframeSwitch.isOn
        do { parameter.value = try parsedValue(type: parameter.value.type) }
        catch { ExtensionUI.alert(title: "Invalid value", message: error.localizedDescription, from: self); return }
        completion(parameter)
        navigationController?.popViewController(animated: true)
    }

    private func parsedValue(type: PresetValueType) throws -> PresetValue {
        let raw = valueField.text ?? ""
        switch type {
        case .number:
            guard let value = Double(raw) else { throw PresetXMLCodecError.invalidValue(raw) }
            return .number(value)
        case .integer:
            guard let value = Int(raw) else { throw PresetXMLCodecError.invalidValue(raw) }
            return .integer(value)
        case .boolean:
            return .boolean(["1", "true", "yes", "on"].contains(raw.lowercased()))
        case .text: return .text(raw)
        case .choice:
            guard parameter.options.contains(raw) else { throw PresetXMLCodecError.invalidValue("Choice must match one declared option") }
            return .choice(raw)
        case .color:
            let values = numericColumns(raw)
            guard values.count == 3 || values.count == 4 else { throw PresetXMLCodecError.invalidValue("Color requires r,g,b[,a]") }
            return .color(PresetColor(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1))
        case .point:
            guard let x = Double(raw), let y = Double(secondValueField.text ?? "") else { throw PresetXMLCodecError.invalidValue("Point requires X and Y") }
            return .point(PresetPoint(x: x, y: y))
        case .angle:
            guard let value = Double(raw) else { throw PresetXMLCodecError.invalidValue("Angle requires degrees") }
            return .angle(value)
        case .size:
            guard let width = Double(raw), let height = Double(secondValueField.text ?? "") else { throw PresetXMLCodecError.invalidValue("Size requires width and height") }
            return .size(PresetSize(width: width, height: height))
        case .rectangle:
            let values = numericColumns(raw)
            guard values.count == 4 else { throw PresetXMLCodecError.invalidValue("Rectangle requires x,y,width,height") }
            return .rectangle(PresetRectangle(x: values[0], y: values[1], width: values[2], height: values[3]))
        case .gradient:
            let stops = try curveView.text.split(whereSeparator: { $0.isNewline }).map { line -> PresetGradientStop in
                let values = numericColumns(String(line))
                guard values.count == 4 || values.count == 5 else { throw PresetXMLCodecError.invalidValue("Gradient line requires location,r,g,b[,a]") }
                return PresetGradientStop(location: values[0], color: PresetColor(red: values[1], green: values[2], blue: values[3], alpha: values.count == 5 ? values[4] : 1))
            }
            return .gradient(PresetGradient(stops: stops))
        case .curve:
            let points = try curveView.text.split(whereSeparator: { $0.isNewline }).map { line -> PresetKeyframe in
                let columns = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 2, let time = Double(columns[0]), let value = Double(columns[1]) else { throw PresetXMLCodecError.invalidValue(String(line)) }
                return PresetKeyframe(time: time, value: value, incomingSlope: columns.count > 2 ? Double(columns[2]) : nil, outgoingSlope: columns.count > 3 ? Double(columns[3]) : nil)
            }
            return .curve(KeyframeCurve(points: points, normalizedTime: true))
        case .layerReference: return .layerReference(raw)
        case .maskReference: return .maskReference(raw)
        case .mapReference: return .mapReference(raw)
        case .audioBandReference: return .audioBandReference(raw)
        case .seed:
            guard let value = Int(raw) else { throw PresetXMLCodecError.invalidValue("Seed requires an integer") }
            return .seed(value)
        case .qualityLevel:
            guard let value = PresetQualityLevel(rawValue: raw.lowercased()) else { throw PresetXMLCodecError.invalidValue("Quality must be draft, preview, high or final") }
            return .qualityLevel(value)
        }
    }

    private func numericColumns(_ value: String) -> [Double] {
        value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func defaultValue(for type: PresetValueType) -> PresetValue {
        switch type {
        case .number: return .number(0)
        case .integer: return .integer(0)
        case .boolean: return .boolean(false)
        case .text: return .text("")
        case .choice: return .choice("")
        case .color: return .color(.init(red: 1, green: 1, blue: 1))
        case .point: return .point(.init(x: 0, y: 0))
        case .angle: return .angle(0)
        case .size: return .size(.init(width: 1920, height: 1080))
        case .rectangle: return .rectangle(.init(x: 0, y: 0, width: 1, height: 1))
        case .gradient: return .gradient(.init(stops: [
            .init(location: 0, color: .init(red: 0, green: 0, blue: 0)),
            .init(location: 1, color: .init(red: 1, green: 1, blue: 1)),
        ]))
        case .curve: return .curve(.init(points: [.init(time: 0, value: 0), .init(time: 1, value: 1)]))
        case .layerReference: return .layerReference("")
        case .maskReference: return .maskReference("")
        case .mapReference: return .mapReference("")
        case .audioBandReference: return .audioBandReference("bass:40-180")
        case .seed: return .seed(0)
        case .qualityLevel: return .qualityLevel(.preview)
        }
    }
}

@MainActor
final class PresetMacroEditorViewController: UIViewController {
    private var macro: PresetMacro
    private let parameters: [PresetParameter]
    private let completion: (PresetMacro) -> Void
    private let idField = ExtensionUI.field("Macro ID")
    private let nameField = ExtensionUI.field("Macro name")
    private let minimumField = ExtensionUI.field("Minimum", value: "0")
    private let maximumField = ExtensionUI.field("Maximum", value: "1")
    private let defaultField = ExtensionUI.field("Default", value: "0.5")
    private let bindingsView = UITextView()

    init(macro: PresetMacro?, parameters: [PresetParameter], completion: @escaping (PresetMacro) -> Void) {
        self.macro = macro ?? PresetMacro(id: "macro.\(UUID().uuidString.prefix(8).lowercased())", name: "Strength", minimum: 0, maximum: 1, defaultValue: 0.5, bindings: [])
        self.parameters = parameters
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Macro Control"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        bindingsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        bindingsView.layer.borderWidth = 1 / UIScreen.main.scale
        bindingsView.layer.borderColor = UIColor.separator.cgColor
        bindingsView.layer.cornerRadius = 8
        bindingsView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        ExtensionUI.installScrollStack(ExtensionUI.stack([
            idField, nameField, minimumField, maximumField, defaultField,
            ExtensionUI.label("Bindings: parameterID,outputMin,outputMax[,component]. Numeric parameters use direct mapping. Curves support component valueScale.", style: .footnote),
            bindingsView,
            ExtensionUI.label("Available parameters:\n" + parameters.map { "• \($0.id) (\($0.value.type.rawValue))" }.joined(separator: "\n"), style: .footnote),
        ]), in: self)
        idField.text = macro.id
        nameField.text = macro.name
        minimumField.text = String(macro.minimum)
        maximumField.text = String(macro.maximum)
        defaultField.text = String(macro.defaultValue)
        bindingsView.text = macro.bindings.map { "\($0.parameterID),\($0.outputMinimum),\($0.outputMaximum),\($0.component ?? "")" }.joined(separator: "\n")
    }

    @objc private func done() {
        guard let minimum = Double(minimumField.text ?? ""), let maximum = Double(maximumField.text ?? ""), let defaultValue = Double(defaultField.text ?? "") else {
            ExtensionUI.alert(title: "Invalid macro", message: "Minimum, maximum and default must be numbers.", from: self); return
        }
        do {
            let bindings = try bindingsView.text.split(whereSeparator: { $0.isNewline }).map { line -> PresetMacroBinding in
                let columns = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 3, let low = Double(columns[1]), let high = Double(columns[2]) else { throw PresetXMLCodecError.invalidValue(String(line)) }
                return PresetMacroBinding(parameterID: columns[0], component: columns.count > 3 && !columns[3].isEmpty ? columns[3] : nil, outputMinimum: low, outputMaximum: high)
            }
            macro = PresetMacro(id: idField.text ?? "", name: nameField.text ?? "", minimum: minimum, maximum: maximum, defaultValue: defaultValue, bindings: bindings)
            completion(macro)
            navigationController?.popViewController(animated: true)
        } catch { ExtensionUI.alert(title: "Invalid binding", message: error.localizedDescription, from: self) }
    }
}
#endif
