#if canImport(UIKit)
import UIKit

@MainActor
final class ResourceHubViewController: UITableViewController {
    private struct Resource {
        let title: String
        let subtitle: String
        let url: URL
        let warning: String?
    }

    private let sections: [(String, [Resource])] = [
        ("Fonts", [
            Resource(
                title: "DaFont",
                subtitle: "Browse downloadable fonts. Check each font's license before commercial use.",
                url: URL(string: "https://www.dafont.com/")!,
                warning: "DaFont hosts fonts with different licenses. Verify the license on the individual font page before using or packaging it."
            ),
        ]),
        ("Editing Resources", [
            Resource(
                title: "Keyframe Resources",
                subtitle: "Editing links, assets and references collected by Keyfla.me.",
                url: URL(string: "https://keyfla.me/resources")!,
                warning: "This opens an external website. Review each resource's license and download terms."
            ),
        ]),
        ("Learning", [
            Resource(
                title: "AE Motion Preset Folder",
                subtitle: "Open Files to manage exported XML preset documents.",
                url: URL(string: "shareddocuments://")!,
                warning: nil
            ),
        ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Resource Hub"
        AEMotionTheme.apply(to: self)
        AEMotionTheme.apply(to: tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "resource")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let resource = sections[indexPath.section].1[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "resource", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = resource.title
        configuration.secondaryText = resource.subtitle
        configuration.image = UIImage(systemName: "link")
        configuration.textProperties.color = AEMotionTheme.primaryText
        configuration.secondaryTextProperties.color = AEMotionTheme.secondaryText
        configuration.imageProperties.tintColor = AEMotionTheme.accent
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        AEMotionTheme.configure(cell: cell, iconName: nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let resource = sections[indexPath.section].1[indexPath.row]
        if let warning = resource.warning {
            let alert = UIAlertController(title: resource.title, message: warning, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
                UIApplication.shared.open(resource.url)
            })
            present(alert, animated: true)
        } else {
            UIApplication.shared.open(resource.url)
        }
    }
}
#endif
