#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class EffectIntegrityViewController: UITableViewController {
    private struct Section {
        let title: String
        let records: [EffectIntegrityRecord]
    }

    private var report: EffectIntegrityReport?
    private var sections: [Section] = []
    private var loadState: EffectIntegrityLoadResult = .missing

    override init(style: UITableView.Style) {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Effect Integrity"
        AEMotionTheme.apply(to: self)
        AEMotionTheme.apply(to: tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "integrity")
        reloadReport()
    }

    private func reloadReport() {
        loadState = EffectIntegrityStore.loadResult()
        switch loadState {
        case let .loaded(report):
            self.report = report
            let quarantined = report.records.filter { !EffectVisibilityPolicy.isVisible($0.status) }
            let warnings = report.records.filter { record in
                EffectVisibilityPolicy.isVisible(record.status)
                    && record.findings.contains { $0.severity == "warning" || $0.severity == "error" }
            }
            let verified = report.records.filter { $0.status == .implementedVerified }
            sections = [
                Section(title: "Summary", records: []),
                Section(title: "Quarantined", records: sorted(quarantined)),
                Section(title: "Warnings", records: sorted(warnings)),
                Section(title: "Verified", records: sorted(verified)),
            ].filter { $0.title == "Summary" || !$0.records.isEmpty }
            tableView.backgroundView = nil
        case .missing:
            report = nil
            sections = []
            tableView.backgroundView = AEMotionTheme.emptyState(
                title: "No integrity report",
                message: "Package this build with the v2.0.3 effect audit before signing.",
                systemImage: "checkmark.shield"
            )
        case .malformed:
            report = nil
            sections = []
            tableView.backgroundView = AEMotionTheme.emptyState(
                title: "Integrity report unavailable",
                message: "The packaged report is malformed. The original Add Effects interface remains unchanged.",
                systemImage: "exclamationmark.triangle"
            )
        }
        tableView.reloadData()
    }

    private func sorted(_ records: [EffectIntegrityRecord]) -> [EffectIntegrityRecord] {
        records.sorted {
            let left = severityRank($0)
            let right = severityRank($1)
            if left != right { return left < right }
            return displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending
        }
    }

    private func severityRank(_ record: EffectIntegrityRecord) -> Int {
        if record.findings.contains(where: { $0.severity == "blocker" }) { return 0 }
        if record.findings.contains(where: { $0.severity == "error" }) { return 1 }
        if record.findings.contains(where: { $0.severity == "warning" }) { return 2 }
        return 3
    }

    private func displayName(_ record: EffectIntegrityRecord) -> String {
        let value = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? record.fileName : value
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].title == "Summary" ? 1 : sections[section].records.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "integrity", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if sections[indexPath.section].title == "Summary", let report {
            let summary = EffectIntegrityStore.summary(report)
            content.text = "\(summary.visibleCount) visible · \(summary.quarantinedCount) quarantined"
            content.secondaryText = "\(summary.totalCount) effects · app \(report.sourceAppVersion) (\(report.sourceBuild))"
            content.image = UIImage(systemName: "checkmark.shield")
            cell.accessoryType = .none
        } else {
            let record = sections[indexPath.section].records[indexPath.row]
            content.text = displayName(record)
            content.secondaryText = "\(record.status.rawValue) · \(record.effectID.isEmpty ? record.fileName : record.effectID)"
            content.image = UIImage(systemName: icon(for: record.status))
            cell.accessoryType = .disclosureIndicator
        }
        content.textProperties.color = AEMotionTheme.primaryText
        content.secondaryTextProperties.color = AEMotionTheme.secondaryText
        content.secondaryTextProperties.numberOfLines = 2
        content.imageProperties.tintColor = AEMotionTheme.accent
        cell.contentConfiguration = content
        AEMotionTheme.configure(cell: cell, iconName: nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sections[indexPath.section].title != "Summary" else { return }
        let record = sections[indexPath.section].records[indexPath.row]
        navigationController?.pushViewController(EffectIntegrityDetailViewController(record: record), animated: true)
    }

    private func icon(for status: EffectIntegrityStatus) -> String {
        switch status {
        case .implementedVerified: return "checkmark.seal"
        case .existingWorking, .implementedUnverified: return "checkmark.circle"
        case .duplicate: return "square.on.square"
        case .unsupportedDependency: return "link.badge.plus"
        case .placeholder: return "rectangle.dashed"
        case .existingBroken, .rejected: return "xmark.octagon"
        case .cleanRoomCandidate: return "hammer"
        }
    }
}

@MainActor
private final class EffectIntegrityDetailViewController: UIViewController {
    private let record: EffectIntegrityRecord

    init(record: EffectIntegrityRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = record.name.isEmpty ? record.fileName : record.name
        AEMotionTheme.apply(to: self)

        let text = UITextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.text = detailText()
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        AEMotionTheme.styleControls(in: text)
    }

    private func detailText() -> String {
        let findings = record.findings.isEmpty
            ? "None"
            : record.findings.map { "[\($0.severity)] \($0.code): \($0.message)" }.joined(separator: "\n")
        return [
            "Status: \(record.status.rawValue)",
            "Effect ID: \(record.effectID)",
            "Category: \(record.category)",
            "File: \(record.fileName)",
            "Descriptor SHA-256: \(record.descriptorSHA256)",
            "Shader SHA-256: \(record.shaderSHA256 ?? "none")",
            "Parameters: \(record.parameterSignature.isEmpty ? "none" : record.parameterSignature)",
            "Dependencies: \(record.dependencies.isEmpty ? "none" : record.dependencies.joined(separator: ", "))",
            "Resources: \(record.resources.isEmpty ? "none" : record.resources.joined(separator: ", "))",
            "Quarantine reason: \(record.quarantineReason ?? "none")",
            "",
            "Findings",
            findings,
        ].joined(separator: "\n")
    }
}
#endif
