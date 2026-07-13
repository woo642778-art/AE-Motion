#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class ExtensionsViewController: UITableViewController, UISearchResultsUpdating {
    private struct HubSection: Equatable {
        let title: String
        let subtitle: String?
        let toolIDs: [String]
    }

    private let favoritesKey = "AEMotionExtensions.favorites"
    private let recentKey = "AEMotionExtensions.recent"
    private var favorites = Set<String>()
    private var recentIDs: [String] = []
    private var query = ""

    private var visibleSections: [HubSection] {
        if !query.isEmpty {
            let matches = ToolRegistry.all.filter(matchesQuery)
            return matches.isEmpty ? [] : [
                HubSection(title: "Results", subtitle: nil, toolIDs: matches.map(\.id)),
            ]
        }

        var sections: [HubSection] = []
        let knownIDs = Set(ToolRegistry.all.map(\.id))
        let recent = recentIDs.filter(knownIDs.contains).prefix(5)
        if !recent.isEmpty {
            sections.append(HubSection(
                title: "Recent",
                subtitle: "Tools opened most recently",
                toolIDs: Array(recent)
            ))
        }

        let favoriteIDs = ToolRegistry.all.map(\.id).filter(favorites.contains)
        if !favoriteIDs.isEmpty {
            sections.append(HubSection(
                title: "Favorites",
                subtitle: nil,
                toolIDs: favoriteIDs
            ))
        }

        let editingIDs = ToolRegistry.all
            .filter {
                ToolPlacementRegistry.placement(for: $0.id) != .extensionsHub
                    && $0.id != "preset.library"
            }
            .map(\.id)
        if !editingIDs.isEmpty {
            sections.append(HubSection(
                title: "Editing Shortcuts",
                subtitle: "These tools are also available from contextual AE Motion menus.",
                toolIDs: editingIDs
            ))
        }

        let scripts = ToolRegistry.all.filter { $0.section == .scripts }.map(\.id)
        if !scripts.isEmpty {
            sections.append(HubSection(title: "Scripts", subtitle: nil, toolIDs: scripts))
        }

        let presets = ["preset.library"].filter(knownIDs.contains)
        if !presets.isEmpty {
            sections.append(HubSection(title: "Presets", subtitle: nil, toolIDs: presets))
        }

        let resources = ["resource.hub", "bpm.frames", "layer.offset"].filter(knownIDs.contains)
        if !resources.isEmpty {
            sections.append(HubSection(title: "Resources", subtitle: nil, toolIDs: resources))
        }

        let diagnostics = ["host.diagnostics"].filter(knownIDs.contains)
        if !diagnostics.isEmpty {
            sections.append(HubSection(title: "Diagnostics", subtitle: nil, toolIDs: diagnostics))
        }
        return sections
    }

    override init(style: UITableView.Style) {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Extensions & Scripts"
        AEMotionTheme.apply(to: self)
        AEMotionTheme.apply(to: tableView)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tool")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        tableView.tableFooterView = UIView()

        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search AE Motion tools"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        updateBackgroundState()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func descriptor(at indexPath: IndexPath) -> ToolDescriptor? {
        let sections = visibleSections
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].toolIDs.indices.contains(indexPath.row) else {
            return nil
        }
        return ToolControllerFactory.descriptor(for: sections[indexPath.section].toolIDs[indexPath.row])
    }

    private func matchesQuery(_ item: ToolDescriptor) -> Bool {
        item.title.localizedCaseInsensitiveContains(query)
            || item.subtitle.localizedCaseInsensitiveContains(query)
            || ToolPlacementRegistry.placement(for: item.id).rawValue.localizedCaseInsensitiveContains(query)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
        updateBackgroundState()
    }

    private func updateBackgroundState() {
        guard visibleSections.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        tableView.backgroundView = AEMotionTheme.emptyState(
            title: query.isEmpty ? "No tools available" : "No matching tools",
            message: query.isEmpty
                ? "AE Motion tools will appear here when they are available."
                : "Try a different tool name or task.",
            systemImage: query.isEmpty ? "wand.and.stars" : "magnifyingglass"
        )
    }

    private func recordRecent(_ toolID: String) {
        recentIDs.removeAll { $0 == toolID }
        recentIDs.insert(toolID, at: 0)
        if recentIDs.count > 12 {
            recentIDs.removeLast(recentIDs.count - 12)
        }
        UserDefaults.standard.set(recentIDs, forKey: recentKey)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        visibleSections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        visibleSections[section].subtitle
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleSections[section].toolIDs.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = descriptor(at: indexPath) else { return UITableViewCell() }
        let cell = tableView.dequeueReusableCell(withIdentifier: "tool", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: iconName(for: item.id))
        config.textProperties.color = AEMotionTheme.primaryText
        config.secondaryTextProperties.color = AEMotionTheme.secondaryText
        config.secondaryTextProperties.numberOfLines = 2
        config.imageProperties.tintColor = AEMotionTheme.accent
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        AEMotionTheme.configure(cell: cell, iconName: nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = descriptor(at: indexPath),
              let controller = ToolControllerFactory.controller(for: item.id) else { return }
        recordRecent(item.id)
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = descriptor(at: indexPath) else { return nil }
        let isFavorite = favorites.contains(item.id)
        let action = UIContextualAction(
            style: .normal,
            title: isFavorite ? "Unfavorite" : "Favorite"
        ) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            if isFavorite { self.favorites.remove(item.id) }
            else { self.favorites.insert(item.id) }
            UserDefaults.standard.set(Array(self.favorites).sorted(), forKey: self.favoritesKey)
            self.tableView.reloadData()
            self.updateBackgroundState()
            completion(true)
        }
        action.image = UIImage(systemName: isFavorite ? "star.slash" : "star")
        action.backgroundColor = isFavorite ? .systemGray : AEMotionTheme.accent
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func iconName(for id: String) -> String {
        switch id {
        case "speed.remap": return "speedometer"
        case "easing.curve": return "chart.xyaxis.line"
        case "cutout.person": return "person.crop.rectangle"
        case "depth.map": return "square.3.layers.3d.down.right"
        case "dead.frames": return "film.stack"
        case "camera.shake": return "waveform.path"
        case "random.values": return "dice"
        case "expression.helper": return "function"
        case "preset.library": return "slider.horizontal.3"
        case "resource.hub": return "link"
        case "bpm.frames": return "metronome"
        case "color.palette": return "paintpalette"
        case "layer.offset": return "square.stack.3d.down.right"
        case "host.diagnostics": return "stethoscope"
        default: return "puzzlepiece.extension"
        }
    }
}
#endif
