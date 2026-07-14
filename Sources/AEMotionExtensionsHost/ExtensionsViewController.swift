#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class ExtensionsViewController: UITableViewController, UISearchResultsUpdating {
    private struct HubSection: Equatable {
        let title: String
        let subtitle: String?
        let entries: [SafeToolRegistryEntry]
    }

    private let favoritesKey = "AEMotionExtensions.favorites"
    private let recentKey = "AEMotionExtensions.recent"
    private var registrySnapshot: [SafeToolRegistryEntry] = []
    private var favorites = Set<String>()
    private var recentIDs: [String] = []
    private var query = ""
    private var isOpeningTool = false

    private var entriesByID: [String: SafeToolRegistryEntry] {
        Dictionary(uniqueKeysWithValues: registrySnapshot.map { ($0.id, $0) })
    }

    private var visibleSections: [HubSection] {
        if !query.isEmpty {
            let matches = registrySnapshot.filter(matchesQuery)
            return matches.isEmpty ? [] : [HubSection(title: "Results", subtitle: nil, entries: matches)]
        }

        var sections: [HubSection] = []
        let byID = entriesByID
        let recent = recentIDs.compactMap { byID[$0] }.prefix(5)
        if !recent.isEmpty {
            sections.append(HubSection(title: "Recent", subtitle: "Tools opened most recently", entries: Array(recent)))
        }

        let favoriteEntries = registrySnapshot.filter { favorites.contains($0.id) }
        if !favoriteEntries.isEmpty {
            sections.append(HubSection(title: "Favorites", subtitle: nil, entries: favoriteEntries))
        }

        appendSection("Scripts", ids: ["random.values", "expression.helper"], to: &sections)
        appendSection("Presets", ids: ["preset.library"], to: &sections)
        appendSection("Resources", ids: ["resource.hub", "bpm.frames", "layer.offset"], to: &sections)
        appendSection(
            "Diagnostics",
            ids: ["effects.integrity", "project.reliability", "host.diagnostics"],
            to: &sections
        )
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
        registrySnapshot = SafeToolRegistry.snapshot()
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        prunePersistedIDs()

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

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search independent AE motion tools"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        updateBackgroundState()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func appendSection(_ title: String, ids: [String], to sections: inout [HubSection]) {
        let byID = entriesByID
        let entries = ids.compactMap { byID[$0] }
        guard !entries.isEmpty else { return }
        sections.append(HubSection(title: title, subtitle: nil, entries: entries))
    }

    private func entry(at indexPath: IndexPath) -> SafeToolRegistryEntry? {
        let sections = visibleSections
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].entries.indices.contains(indexPath.row) else {
            return nil
        }
        return sections[indexPath.section].entries[indexPath.row]
    }

    private func matchesQuery(_ entry: SafeToolRegistryEntry) -> Bool {
        entry.title.localizedCaseInsensitiveContains(query)
            || entry.subtitle.localizedCaseInsensitiveContains(query)
            || entry.id.localizedCaseInsensitiveContains(query)
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
                ? "Independent utilities and diagnostics appear here. Editing controls remain beside the native editor controls."
                : "Try a different utility or diagnostic name.",
            systemImage: query.isEmpty ? "wand.and.stars" : "magnifyingglass"
        )
    }

    private func prunePersistedIDs() {
        let known = Set(registrySnapshot.map(\.id))
        favorites.formIntersection(known)
        recentIDs = recentIDs.filter(known.contains)
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: favoritesKey)
        UserDefaults.standard.set(recentIDs, forKey: recentKey)
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
        visibleSections[section].entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let entry = entry(at: indexPath) else { return UITableViewCell() }
        let cell = tableView.dequeueReusableCell(withIdentifier: "tool", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = entry.title
        config.secondaryText = entry.subtitle
        config.image = UIImage(systemName: iconName(for: entry.id))
        config.secondaryTextProperties.numberOfLines = 2
        switch entry.availability {
        case .available:
            config.textProperties.color = AEMotionTheme.primaryText
            config.secondaryTextProperties.color = AEMotionTheme.secondaryText
            cell.accessoryType = .disclosureIndicator
        case .unavailable(let reason):
            config.textProperties.color = .secondaryLabel
            config.secondaryText = reason
            config.secondaryTextProperties.color = .tertiaryLabel
            cell.accessoryType = .none
        }
        config.imageProperties.tintColor = AEMotionTheme.accent
        cell.contentConfiguration = config
        AEMotionTheme.configure(cell: cell, iconName: nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isOpeningTool, let entry = entry(at: indexPath) else { return }
        isOpeningTool = true
        recordRecent(entry.id)
        ToolPresentationGuard.push(entry.id, from: navigationController)
        DispatchQueue.main.async { [weak self] in self?.isOpeningTool = false }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let entry = entry(at: indexPath) else { return nil }
        let isFavorite = favorites.contains(entry.id)
        let action = UIContextualAction(style: .normal, title: isFavorite ? "Unfavorite" : "Favorite") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            if isFavorite { self.favorites.remove(entry.id) }
            else { self.favorites.insert(entry.id) }
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
        case "random.values": return "dice"
        case "expression.helper": return "function"
        case "preset.library": return "slider.horizontal.3"
        case "resource.hub": return "link"
        case "bpm.frames": return "metronome"
        case "layer.offset": return "square.stack.3d.down.right"
        case "effects.integrity": return "checkmark.shield"
        case "project.reliability": return "externaldrive.badge.checkmark"
        case "host.diagnostics": return "stethoscope"
        default: return "puzzlepiece.extension"
        }
    }
}
#endif
