#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

final class ExtensionsViewController: UITableViewController {
    private let sections: [ToolDescriptor.Section] = [.extensions, .scripts, .presets, .utilities, .favorites]
    private var favorites = Set<String>()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Extensions & Scripts"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tool")
    }
    @objc private func close() { dismiss(animated: true) }
    private func tools(in section: ToolDescriptor.Section) -> [ToolDescriptor] {
        if section == .favorites { return ToolRegistry.all.filter { favorites.contains($0.id) } }
        return ToolRegistry.all.filter { $0.section == section }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].rawValue.capitalized }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tools(in: sections[section]).count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = tools(in: sections[indexPath.section])[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "tool", for: indexPath)
        var config = cell.defaultContentConfiguration(); config.text = item.title; config.secondaryText = item.subtitle
        cell.contentConfiguration = config; cell.accessoryType = .disclosureIndicator; return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = tools(in: sections[indexPath.section])[indexPath.row]
        navigationController?.pushViewController(ToolPlaceholderViewController(tool: item), animated: true)
    }
}

final class ToolPlaceholderViewController: UIViewController {
    private let tool: ToolDescriptor
    init(tool: ToolDescriptor) { self.tool = tool; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = tool.title; view.backgroundColor = .systemBackground
        let label = UILabel(); label.numberOfLines = 0; label.textAlignment = .center
        label.text = tool.subtitle + "\n\nThe utility engine is included in AEMotionExtensionsCore. Native controls are connected during the macOS/Xcode integration build."
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }
}
#endif
