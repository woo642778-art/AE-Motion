#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

final class ExtensionsViewController: UITableViewController, UISearchResultsUpdating {
    private let sections: [ToolDescriptor.Section] = [.extensions, .scripts, .presets, .utilities, .favorites]
    private let favoritesKey = "AEMotionExtensions.favorites"
    private var favorites = Set<String>()
    private var query = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Extensions & Scripts"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tool")
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search tools"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    @objc private func close() { dismiss(animated: true) }

    private func tools(in section: ToolDescriptor.Section) -> [ToolDescriptor] {
        let base: [ToolDescriptor]
        if section == .favorites {
            base = ToolRegistry.all.filter { favorites.contains($0.id) }
        } else {
            base = ToolRegistry.all.filter { $0.section == section }
        }
        guard !query.isEmpty else { return base }
        return base.filter { item in
            item.title.localizedCaseInsensitiveContains(query) || item.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].rawValue.capitalized
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tools(in: sections[section]).count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = tools(in: sections[indexPath.section])[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "tool", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: iconName(for: item.id))
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = tools(in: sections[indexPath.section])[indexPath.row]
        navigationController?.pushViewController(controller(for: item), animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = tools(in: sections[indexPath.section])[indexPath.row]
        let isFavorite = favorites.contains(item.id)
        let action = UIContextualAction(style: .normal, title: isFavorite ? "Unfavorite" : "Favorite") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            if isFavorite { self.favorites.remove(item.id) } else { self.favorites.insert(item.id) }
            UserDefaults.standard.set(Array(self.favorites).sorted(), forKey: self.favoritesKey)
            self.tableView.reloadData()
            completion(true)
        }
        action.backgroundColor = isFavorite ? .systemGray : .systemYellow
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func controller(for item: ToolDescriptor) -> UIViewController {
        switch item.id {
        case "speed.remap": return SpeedRemapStudioViewController()
        case "easing.curve": return EasingCurveViewController()
        case "camera.shake": return CameraShakeViewController()
        case "random.values": return RandomValuesViewController()
        case "expression.helper": return ExpressionHelperViewController()
        case "text.animator", "motion.presets": return PresetBrowserViewController()
        case "bpm.frames": return BPMCalculatorViewController()
        case "color.palette": return ColorPaletteViewController()
        case "layer.offset": return LayerOffsetViewController()
        case "host.diagnostics": return HostDiagnosticsViewController()
        default: return UIViewController()
        }
    }

    private func iconName(for id: String) -> String {
        switch id {
        case "speed.remap": return "speedometer"
        case "easing.curve": return "chart.xyaxis.line"
        case "camera.shake": return "waveform.path"
        case "random.values": return "dice"
        case "expression.helper": return "function"
        case "bpm.frames": return "metronome"
        case "color.palette": return "paintpalette"
        case "layer.offset": return "square.stack.3d.down.right"
        case "host.diagnostics": return "stethoscope"
        default: return "puzzlepiece.extension"
        }
    }
}
#endif
