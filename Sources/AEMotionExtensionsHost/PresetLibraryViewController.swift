#if canImport(UIKit) && canImport(UniformTypeIdentifiers)
import UIKit
import UniformTypeIdentifiers
import AEMotionExtensionsCore

@MainActor
final class PresetLibraryViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate, UIDocumentPickerDelegate {
    private let environment = PresetLibraryEnvironment.shared
    private var documents: [PresetDocument] = []
    private var query = ""
    private var selectedKind: PresetKind?
    private var favoritesOnly = false
    private var selectedCollection: String?
    private enum SortMode { case name, recent, mostUsed }
    private var sortMode: SortMode = .name
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Preset Studio"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "preset")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.searchBar.delegate = self
        search.searchBar.placeholder = "Search name, tag, target or author"
        search.searchBar.scopeButtonTitles = ["All", "Velocity", "Graph", "Motion", "Color", "Text"]
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        rebuildNavigationActions()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "star"),
            style: .plain,
            target: self,
            action: #selector(toggleFavoritesOnly)
        )

        changeObserver = NotificationCenter.default.addObserver(
            forName: PresetLibraryEnvironment.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }


    private func rebuildNavigationActions() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createPreset)),
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: actionsMenu()),
        ]
    }

    private func actionsMenu() -> UIMenu {
        let collectionActions: [UIAction] = [
            UIAction(title: "All Presets", state: selectedCollection == nil ? .on : .off) { [weak self] _ in
                self?.selectedCollection = nil
                self?.reload()
            },
        ] + environment.collectionNames.map { name in
            UIAction(title: name, state: selectedCollection == name ? .on : .off) { [weak self] _ in
                self?.selectedCollection = name
                self?.reload()
            }
        }
        let sort = UIMenu(title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), children: [
            UIAction(title: "Name", state: sortMode == .name ? .on : .off) { [weak self] _ in self?.sortMode = .name; self?.reload() },
            UIAction(title: "Recently Used", state: sortMode == .recent ? .on : .off) { [weak self] _ in self?.sortMode = .recent; self?.reload() },
            UIAction(title: "Most Used", state: sortMode == .mostUsed ? .on : .off) { [weak self] _ in self?.sortMode = .mostUsed; self?.reload() },
        ])
        let collections = UIMenu(title: "Collection", image: UIImage(systemName: "folder"), children: collectionActions)
        return UIMenu(children: [
            UIAction(title: "Import XML Preset", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                self?.importPreset()
            },
            UIAction(title: "Resource Hub", image: UIImage(systemName: "link")) { [weak self] _ in
                self?.navigationController?.pushViewController(ResourceHubViewController(), animated: true)
            },
            collections,
            sort,
            UIAction(title: "Reload Library", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.environment.reload()
            },
        ])
    }

    @objc private func createPreset() {
        let editor = PresetEditorViewController(document: environment.userTemplate(), mode: .create)
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func toggleFavoritesOnly() {
        favoritesOnly.toggle()
        navigationItem.leftBarButtonItem?.image = UIImage(systemName: favoritesOnly ? "star.fill" : "star")
        reload()
    }

    private func importPreset() {
        let types: [UTType] = [UTType.xml, UTType(filenameExtension: "aemotionpreset") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var imported: [String] = []
        var failures: [String] = []
        for url in urls {
            do { imported.append(try environment.importFile(url).name) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        let message = [
            imported.isEmpty ? nil : "Imported: \(imported.joined(separator: ", "))",
            failures.isEmpty ? nil : "Failed:\n\(failures.joined(separator: "\n"))",
        ].compactMap { $0 }.joined(separator: "\n\n")
        ExtensionUI.alert(title: failures.isEmpty ? "Import complete" : "Import finished with issues", message: message, from: self)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        selectedKind = [nil, .velocity, .graph, .motion, .color, .text][safe: selectedScope] ?? nil
        reload()
    }

    private func reload() {
        documents = PresetQuery.filter(
            environment.documents(inCollection: selectedCollection),
            text: query,
            kind: selectedKind,
            target: nil,
            favoriteIDs: environment.favoriteIDs,
            favoritesOnly: favoritesOnly
        )
        switch sortMode {
        case .name: break
        case .recent:
            documents.sort {
                (environment.recentRank($0) ?? Int.max, $0.name) < (environment.recentRank($1) ?? Int.max, $1.name)
            }
        case .mostUsed:
            documents.sort {
                let left = environment.usageCount($0)
                let right = environment.usageCount($1)
                return left == right ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : left > right
            }
        }
        tableView.reloadData()
        tableView.backgroundView = documents.isEmpty ? emptyLabel("No presets match the current filter.") : nil
        tableView.tableHeaderView = environment.loadIssues.isEmpty ? nil : issueHeader(environment.loadIssues)
        rebuildNavigationActions()
    }

    private func emptyLabel(_ text: String) -> UILabel {
        let label = ExtensionUI.label(text)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }

    private func issueHeader(_ issues: [PresetLoadIssue]) -> UIView {
        let label = ExtensionUI.label("\(issues.count) invalid preset file(s) were moved to Quarantine. The library remained available.", style: .footnote)
        label.textColor = .systemOrange
        label.frame = CGRect(x: 20, y: 8, width: max(0, tableView.bounds.width - 40), height: 52)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 68))
        container.addSubview(label)
        return container
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { documents.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let document = documents[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "preset", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = document.name
        let source = environment.isBuiltin(document) ? "Built-in" : "User"
        let tags = document.tags.prefix(4).joined(separator: " · ")
        let useCount = environment.usageCount(document)
        configuration.secondaryText = "\(document.kind.rawValue.capitalized) · \(source) · Used \(useCount)\n\(tags.isEmpty ? document.summary : tags)"
        configuration.secondaryTextProperties.numberOfLines = 2
        if let data = document.previewImagePNG, let image = UIImage(data: data) {
            configuration.image = image.preparingThumbnail(of: CGSize(width: 56, height: 56)) ?? image
        } else {
            configuration.image = UIImage(systemName: icon(for: document.kind))
        }
        cell.contentConfiguration = configuration
        cell.accessoryView = UIImageView(image: UIImage(systemName: environment.isFavorite(document) ? "star.fill" : "chevron.right"))
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(PresetDetailViewController(document: documents[indexPath.row]), animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let document = documents[indexPath.row]
        let favorite = UIContextualAction(style: .normal, title: environment.isFavorite(document) ? "Unfavorite" : "Favorite") { [weak self] _, _, completion in
            self?.environment.toggleFavorite(document)
            completion(true)
        }
        favorite.backgroundColor = .systemYellow

        let duplicate = UIContextualAction(style: .normal, title: "Duplicate") { [weak self] _, _, completion in
            do { _ = try self?.environment.duplicate(document); completion(true) }
            catch { completion(false); if let self { ExtensionUI.alert(title: "Duplicate failed", message: error.localizedDescription, from: self) } }
        }
        duplicate.backgroundColor = .systemBlue

        var actions = [favorite, duplicate]
        if !environment.isBuiltin(document) {
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                do { try self?.environment.delete(document); completion(true) }
                catch { completion(false); if let self { ExtensionUI.alert(title: "Delete failed", message: error.localizedDescription, from: self) } }
            }
            actions.append(delete)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }

    private func icon(for kind: PresetKind) -> String {
        switch kind {
        case .velocity: return "speedometer"
        case .graph: return "chart.xyaxis.line"
        case .motion: return "move.3d"
        case .color: return "paintpalette"
        case .text: return "textformat"
        case .transition: return "rectangle.2.swap"
        case .editableTemplate: return "rectangle.on.rectangle"
        case .audioReactive: return "waveform"
        default: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class PresetDetailViewController: UIViewController {
    private let environment = PresetLibraryEnvironment.shared
    private var document: PresetDocument
    private var workingDocument: PresetDocument
    private let content = UIStackView()

    init(document: PresetDocument) {
        self.document = document
        self.workingDocument = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = document.name
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportPreset)),
            UIBarButtonItem(title: environment.isBuiltin(document) ? "Duplicate" : "Edit", style: .plain, target: self, action: #selector(editPreset)),
        ]
        rebuild()
    }

    private func rebuild() {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.axis = .vertical
        content.spacing = 12

        if let data = workingDocument.previewImagePNG, let image = UIImage(data: data) {
            let preview = UIImageView(image: image)
            preview.contentMode = .scaleAspectFit
            preview.layer.cornerRadius = 12
            preview.clipsToBounds = true
            preview.heightAnchor.constraint(equalToConstant: 180).isActive = true
            content.addArrangedSubview(preview)
        }
        content.addArrangedSubview(ExtensionUI.label(workingDocument.name, style: .title2))
        content.addArrangedSubview(ExtensionUI.label(workingDocument.summary.isEmpty ? "No description." : workingDocument.summary))
        content.addArrangedSubview(ExtensionUI.label("Type: \(workingDocument.kind.rawValue)\nTargets: \(workingDocument.targets.joined(separator: ", "))\nAuthor: \(workingDocument.author.isEmpty ? "Unknown" : workingDocument.author)", style: .footnote))

        if !workingDocument.tags.isEmpty {
            content.addArrangedSubview(ExtensionUI.label("Tags: \(workingDocument.tags.joined(separator: " · "))", style: .footnote))
        }

        if !workingDocument.macros.isEmpty {
            content.addArrangedSubview(ExtensionUI.label("Easy Controls", style: .headline))
            for macro in workingDocument.macros { content.addArrangedSubview(macroControl(macro)) }
        }
        let diff = PresetDiff.compare(document, workingDocument)
        if !diff.isEmpty {
            content.addArrangedSubview(ExtensionUI.secondaryButton("Review Macro Changes", action: UIAction { [weak self] _ in
                self?.showDiff(diff)
            }))
        }

        content.addArrangedSubview(ExtensionUI.label("Parameters", style: .headline))
        for parameter in workingDocument.parameters {
            content.addArrangedSubview(ExtensionUI.label("\(parameter.name)\n\(parameter.value.displayString)", style: .subheadline))
        }

        let dependencies = dependencySummary(workingDocument.dependencies)
        if !dependencies.isEmpty {
            content.addArrangedSubview(ExtensionUI.label("Dependencies", style: .headline))
            content.addArrangedSubview(ExtensionUI.label(dependencies, style: .footnote))
        }

        let validation = PresetValidator.validate(workingDocument)
        if !validation.issues.isEmpty {
            let label = ExtensionUI.label(validation.issues.map { "• \($0.message)" }.joined(separator: "\n"), style: .footnote)
            label.textColor = validation.isValid ? .systemOrange : .systemRed
            content.addArrangedSubview(label)
        }
        let compatibility = PresetCompatibilityEvaluator.evaluate(workingDocument, context: environment.runtimeContext())
        if !compatibility.issues.isEmpty {
            content.addArrangedSubview(ExtensionUI.label("Compatibility", style: .headline))
            let label = ExtensionUI.label(compatibility.issues.map { "• \($0.message)" }.joined(separator: "\n"), style: .footnote)
            label.textColor = compatibility.isValid ? .systemOrange : .systemRed
            content.addArrangedSubview(label)
        }

        let apply = ExtensionUI.button("Apply Preset", action: UIAction { [weak self] _ in self?.applyPreset() })
        apply.isEnabled = validation.isValid && compatibility.isValid
        let favorite = ExtensionUI.secondaryButton(environment.isFavorite(document) ? "Remove Favorite" : "Add Favorite", action: UIAction { [weak self] _ in
            guard let self else { return }
            self.environment.toggleFavorite(self.document)
            self.rebuild()
        })
        let collectionsButton = UIButton(type: .system)
        collectionsButton.configuration = .tinted()
        collectionsButton.setTitle("Collections", for: .normal)
        collectionsButton.menu = collectionsMenu()
        collectionsButton.showsMenuAsPrimaryAction = true
        content.addArrangedSubview(apply)
        content.addArrangedSubview(favorite)
        content.addArrangedSubview(collectionsButton)
        content.addArrangedSubview(ExtensionUI.label("Used \(environment.usageCount(document)) time(s).", style: .footnote))

        if content.superview == nil { ExtensionUI.installScrollStack(content, in: self) }
    }

    private func macroControl(_ macro: PresetMacro) -> UIView {
        let currentValue = (try? PresetMacroEngine.value(macroID: macro.id, in: workingDocument)) ?? macro.defaultValue
        let title = ExtensionUI.label("\(macro.name): \(String(format: "%.2f", currentValue))")
        let slider = UISlider()
        slider.minimumValue = Float(macro.minimum)
        slider.maximumValue = Float(macro.maximum)
        slider.value = Float(currentValue)
        slider.addAction(UIAction { [weak self, weak title, weak slider] _ in
            guard let self, let slider else { return }
            do {
                self.workingDocument = try PresetMacroEngine.applying(macroID: macro.id, value: Double(slider.value), to: self.workingDocument)
                title?.text = "\(macro.name): \(String(format: "%.2f", slider.value))"
            } catch {
                ExtensionUI.alert(title: "Macro failed", message: error.localizedDescription, from: self)
            }
        }, for: .valueChanged)
        return ExtensionUI.stack([title, slider], spacing: 4)
    }

    private func showDiff(_ diff: PresetDiffResult) {
        let message = diff.entries.map { entry in
            let before = entry.before.map { "Before: \($0)" } ?? ""
            let after = entry.after.map { "After: \($0)" } ?? ""
            return "\(entry.kind.rawValue.uppercased()) · \(entry.path)\n\(before)\(before.isEmpty || after.isEmpty ? "" : "\n")\(after)"
        }.joined(separator: "\n\n")
        ExtensionUI.alert(title: "Preset Changes", message: message, from: self)
    }

    private func applyPreset() {
        let target = workingDocument.targets.first ?? ""
        let controller: UIViewController
        switch target {
        case "speed.remap": controller = SpeedRemapStudioViewController(initialPreset: workingDocument)
        case "easing.curve": controller = EasingCurveViewController(initialPreset: workingDocument)
        case "camera.shake": controller = CameraShakeViewController(initialPreset: workingDocument)
        case "color.palette": controller = ColorPaletteViewController(initialPreset: workingDocument)
        default:
            ExtensionUI.alert(title: "No application adapter", message: "This preset is valid, but target \(target) does not yet have a runtime adapter in v2.0.", from: self)
            return
        }
        environment.recordUse(document)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func collectionsMenu() -> UIMenu {
        let existing = environment.collectionNames.map { name in
            UIAction(title: name, state: environment.isInCollection(document, name: name) ? .on : .off) { [weak self] _ in
                guard let self else { return }
                let enabled = !self.environment.isInCollection(self.document, name: name)
                self.environment.setCollection(name, contains: self.document, enabled: enabled)
                self.rebuild()
            }
        }
        let create = UIAction(title: "New Collection…", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            self?.createCollection()
        }
        return UIMenu(children: existing + [create])
    }

    private func createCollection() {
        let alert = UIAlertController(title: "New Collection", message: "Create a collection and add this preset.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Collection name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            self.environment.setCollection(name, contains: self.document, enabled: true)
            self.rebuild()
        })
        present(alert, animated: true)
    }

    @objc private func editPreset() {
        if environment.isBuiltin(document) {
            do {
                let copy = try environment.duplicate(document)
                navigationController?.pushViewController(PresetEditorViewController(document: copy, mode: .edit), animated: true)
            } catch { ExtensionUI.alert(title: "Duplicate failed", message: error.localizedDescription, from: self) }
        } else {
            navigationController?.pushViewController(PresetEditorViewController(document: document, mode: .edit), animated: true)
        }
    }

    @objc private func exportPreset() {
        do {
            let url = try environment.exportURL(for: workingDocument)
            ExtensionUI.share(fileURL: url, from: self)
        } catch { ExtensionUI.alert(title: "Export failed", message: error.localizedDescription, from: self) }
    }

    private func dependencySummary(_ manifest: DependencyManifest) -> String {
        var lines: [String] = []
        for value in manifest.fonts { lines.append("Font: \(value.name)\(value.optional ? " (optional)" : "")") }
        for value in manifest.effects { lines.append("Effect: \(value.name)\(value.optional ? " (optional)" : "")") }
        for value in manifest.media { lines.append("Media: \(value.name)\(value.optional ? " (optional)" : "")") }
        for value in manifest.models { lines.append("Model: \(value.name)\(value.optional ? " (optional)" : "")") }
        return lines.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
