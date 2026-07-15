#if canImport(UIKit)
import UIKit
import AEMotionExtensionsCore

@MainActor
final class CompositionInspectorViewController: UITableViewController {
    enum PreferredSection: String, Sendable {
        case blend
        case matte
        case parent
        case alpha
        case channels
    }

    private enum Section: CaseIterable {
        case blend
        case matte
        case parent
        case alpha
        case channels

        var title: String {
            switch self {
            case .blend: return "Blend"
            case .matte: return "Track Matte"
            case .parent: return "Parent"
            case .alpha: return "Alpha"
            case .channels: return "Channels"
            }
        }
    }

    private enum OutputChannel: CaseIterable {
        case red
        case green
        case blue
        case alpha

        var title: String {
            switch self {
            case .red: return "Red Output"
            case .green: return "Green Output"
            case .blue: return "Blue Output"
            case .alpha: return "Alpha Output"
            }
        }
    }

    private let session: CompositionHostSession
    private let selectedLayerIDs: [UUID]
    private let compositionID: UUID
    private let coordinator = CompositionLivePreviewCoordinator()
    private let preferredSection: PreferredSection?
    private var document: CompositionDocument
    private var didCommit = false
    private var pendingMatteMode: MatteMode = .alpha
    private weak var pickWhipButton: UIButton?

    init?(
        session: CompositionHostSession,
        selectedLayerIDs: [UUID],
        preferredSection: PreferredSection? = nil
    ) {
        guard !selectedLayerIDs.isEmpty,
              session.adapter.verifiedCapabilities.contains(.previewComposition),
              let snapshot = session.adapter.snapshot(),
              let document = session.adapter.readCompositionDocument(),
              document.compositions.contains(where: { $0.id == snapshot.compositionID }) else { return nil }
        let layerIDs = Set(
            document.compositions
                .first(where: { $0.id == snapshot.compositionID })?
                .layers.map(\.id) ?? []
        )
        guard Set(selectedLayerIDs).isSubset(of: layerIDs) else { return nil }
        self.session = session
        self.selectedLayerIDs = selectedLayerIDs
        self.compositionID = snapshot.compositionID
        self.document = document
        self.preferredSection = preferredSection
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compositing"
        tableView.accessibilityIdentifier = "aemotion.composition.inspector"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(done)
        )
        do {
            try coordinator.begin(session: session)
            scrollToPreferredSectionIfNeeded()
        } catch {
            navigationItem.prompt = "Live preview is unavailable for this host state."
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didCommit { coordinator.cancel(reason: .userCancelled) }
    }

    private var sections: [Section] {
        var result: [Section] = []
        let capabilities = session.adapter.verifiedCapabilities
        if capabilities.contains(.blendModes), !session.adapter.supportedBlendModeIDs.isEmpty {
            result.append(.blend)
        }
        if capabilities.contains(.structuralMatte) { result.append(.matte) }
        if capabilities.contains(.structuralParenting) { result.append(.parent) }
        if capabilities.contains(.channelAlpha) { result.append(contentsOf: [.alpha, .channels]) }
        return result
    }

    private var composition: Composition? {
        document.compositions.first(where: { $0.id == compositionID })
    }

    private var selectedLayers: [CompositionLayer] {
        let selected = Set(selectedLayerIDs)
        return composition?.layers.filter { selected.contains($0.id) } ?? []
    }

    private var representativeLayer: CompositionLayer? { selectedLayers.first }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .blend: return 1
        case .matte: return 2
        case .parent: return 2
        case .alpha: return 3
        case .channels: return OutputChannel.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        switch sections[indexPath.section] {
        case .blend:
            configureBlendCell(cell)
        case .matte:
            configureMatteCell(cell, row: indexPath.row)
        case .parent:
            configureParentCell(cell, row: indexPath.row)
        case .alpha:
            configureAlphaCell(cell, row: indexPath.row)
        case .channels:
            configureChannelCell(cell, output: OutputChannel.allCases[indexPath.row])
        }
        return cell
    }

    private func configureBlendCell(_ cell: UITableViewCell) {
        cell.textLabel?.text = "Mode"
        let current = representativeLayer?.blendModeID ?? "normal"
        cell.detailTextLabel?.text = BlendModeCatalogue.descriptor(id: current)?.displayName ?? current
        cell.accessoryView = menuButton(title: cell.detailTextLabel?.text ?? "Normal", menu: blendMenu(currentID: current))
    }

    private func blendMenu(currentID: String) -> UIMenu {
        let supportedBlendModeIDs = session.adapter.supportedBlendModeIDs
        let groups = BlendModeGroup.allCases.compactMap { group -> UIMenu? in
            let actions = BlendModeCatalogue.modes(in: group).map { descriptor in
                UIAction(
                    title: descriptor.displayName,
                    attributes: supportedBlendModeIDs.contains(descriptor.id) ? [] : [.disabled],
                    state: descriptor.id == currentID ? .on : .off
                ) { [weak self] _ in
                    self?.applyBlendMode(descriptor.id)
                }
            }
            guard !actions.isEmpty else { return nil }
            return UIMenu(title: groupTitle(group), options: .displayInline, children: actions)
        }
        return UIMenu(title: "Blend", children: groups)
    }

    private func groupTitle(_ group: BlendModeGroup) -> String {
        switch group {
        case .normal: return "Normal"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .contrast: return "Contrast"
        case .inversion: return "Difference"
        case .component: return "HSL"
        case .utility: return "Stencil & Silhouette"
        }
    }

    private func configureMatteCell(_ cell: UITableViewCell, row: Int) {
        if row == 0 {
            cell.textLabel?.text = "Source"
            let sourceID = representativeLayer?.matte?.sourceLayerID
            cell.detailTextLabel?.text = sourceID.flatMap(layerName) ?? "None"
            cell.accessoryView = menuButton(title: cell.detailTextLabel?.text ?? "None", menu: matteSourceMenu(currentID: sourceID))
        } else {
            cell.textLabel?.text = "Mode"
            let mode = representativeLayer?.matte?.mode ?? pendingMatteMode
            cell.detailTextLabel?.text = matteModeTitle(mode)
            cell.accessoryView = menuButton(title: matteModeTitle(mode), menu: matteModeMenu(current: mode))
        }
    }

    private func matteSourceMenu(currentID: UUID?) -> UIMenu {
        let none = UIAction(title: "None", state: currentID == nil ? .on : .off) { [weak self] _ in
            self?.applyMatte(nil)
        }
        let selected = Set(selectedLayerIDs)
        let sources = compatibleLayerHandles().filter { !selected.contains($0.id) }.map { handle in
            UIAction(title: handle.displayName, state: handle.id == currentID ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.applyMatte(MatteBinding(sourceLayerID: handle.id, mode: self.pendingMatteMode))
            }
        }
        return UIMenu(title: "Track Matte Source", children: [none] + sources)
    }

    private func matteModeMenu(current: MatteMode) -> UIMenu {
        let actions = MatteMode.allCases.map { mode in
            UIAction(title: matteModeTitle(mode), state: mode == current ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.pendingMatteMode = mode
                if let sourceID = self.representativeLayer?.matte?.sourceLayerID {
                    self.applyMatte(MatteBinding(sourceLayerID: sourceID, mode: mode))
                } else {
                    self.tableView.reloadData()
                }
            }
        }
        return UIMenu(title: "Track Matte Mode", children: actions)
    }

    private func matteModeTitle(_ mode: MatteMode) -> String {
        switch mode {
        case .alpha: return "Alpha"
        case .alphaInverted: return "Alpha Inverted"
        case .luma: return "Luma"
        case .lumaInverted: return "Luma Inverted"
        }
    }

    private func configureParentCell(_ cell: UITableViewCell, row: Int) {
        if row == 0 {
            cell.textLabel?.text = "Parent"
            let parentID = representativeLayer?.parent?.parentLayerID
            cell.detailTextLabel?.text = parentID.flatMap(layerName) ?? "None"
            cell.accessoryView = menuButton(title: cell.detailTextLabel?.text ?? "None", menu: parentMenu(currentID: parentID))
        } else {
            cell.textLabel?.text = "Pick Whip"
            cell.detailTextLabel?.text = "Drag to layer"
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath"), for: .normal)
            button.accessibilityLabel = "Parent Pick Whip"
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePickWhip(_:)))
            button.addGestureRecognizer(pan)
            pickWhipButton = button
            cell.accessoryView = button
        }
    }

    private func parentMenu(currentID: UUID?) -> UIMenu {
        let none = UIAction(title: "None", state: currentID == nil ? .on : .off) { [weak self] _ in
            self?.applyParent(nil)
        }
        let selected = Set(selectedLayerIDs)
        let parents = compatibleLayerHandles().filter { !selected.contains($0.id) }.map { handle in
            UIAction(title: handle.displayName, state: handle.id == currentID ? .on : .off) { [weak self] _ in
                self?.applyParent(handle.id)
            }
        }
        return UIMenu(title: "Parent", children: [none] + parents)
    }

    @objc private func handlePickWhip(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: session.timelineView)
        let target = compatibleLayerHandles().first { handle in
            !selectedLayerIDs.contains(handle.id) && handle.timelineFrame?.contains(point) == true
        }
        switch recognizer.state {
        case .began, .changed:
            navigationItem.prompt = target.map { "Parent → \($0.displayName)" } ?? "Drag to a compatible layer"
        case .ended:
            navigationItem.prompt = nil
            if let target { applyParent(target.id) }
        case .cancelled, .failed:
            navigationItem.prompt = nil
        default:
            break
        }
    }

    private func configureAlphaCell(_ cell: UITableViewCell, row: Int) {
        switch row {
        case 0:
            cell.textLabel?.text = "Interpretation"
            let current = representativeLayer?.alphaInterpretation ?? .straight
            cell.detailTextLabel?.text = current == .straight ? "Straight" : "Premultiplied"
            let actions = AlphaInterpretation.allCases.map { interpretation in
                UIAction(
                    title: interpretation == .straight ? "Straight" : "Premultiplied",
                    state: interpretation == current ? .on : .off
                ) { [weak self] _ in
                    self?.applyAlphaInterpretation(interpretation)
                }
            }
            cell.accessoryView = menuButton(title: cell.detailTextLabel?.text ?? "Straight", menu: UIMenu(title: "Alpha", children: actions))
        case 1:
            cell.textLabel?.text = "Alpha Inverted"
            let toggle = UISwitch()
            toggle.isOn = representativeLayer?.isAlphaInverted ?? false
            toggle.addTarget(self, action: #selector(alphaInvertedChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        default:
            cell.textLabel?.text = "Create Alpha from Luminance"
            cell.detailTextLabel?.text = representativeLayer?.channelMapping.alpha == .luminance ? "On" : "Off"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard sections[indexPath.section] == .alpha, indexPath.row == 2 else { return }
        var mapping = representativeLayer?.channelMapping ?? .identity
        mapping.alpha = mapping.alpha == .luminance ? .alpha : .luminance
        applyChannelMapping(mapping)
    }

    @objc private func alphaInvertedChanged(_ sender: UISwitch) {
        applyChannelMapping(
            representativeLayer?.channelMapping ?? .identity,
            interpretation: representativeLayer?.alphaInterpretation ?? .straight,
            invertAlpha: sender.isOn
        )
    }

    private func configureChannelCell(_ cell: UITableViewCell, output: OutputChannel) {
        cell.textLabel?.text = output.title
        let mapping = representativeLayer?.channelMapping ?? .identity
        let current = channelSource(for: output, mapping: mapping)
        cell.detailTextLabel?.text = channelSourceTitle(current)
        let actions = ChannelSource.allCases.map { source in
            UIAction(title: channelSourceTitle(source), state: source == current ? .on : .off) { [weak self] _ in
                self?.applyChannelSource(source, output: output)
            }
        }
        cell.accessoryView = menuButton(
            title: channelSourceTitle(current),
            menu: UIMenu(title: output.title, children: actions)
        )
    }

    private func channelSource(for output: OutputChannel, mapping: ChannelMapping) -> ChannelSource {
        switch output {
        case .red: return mapping.red
        case .green: return mapping.green
        case .blue: return mapping.blue
        case .alpha: return mapping.alpha
        }
    }

    private func channelSourceTitle(_ source: ChannelSource) -> String {
        switch source {
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .alpha: return "Alpha"
        case .luminance: return "Luminance"
        case .fullOn: return "Full On"
        case .fullOff: return "Full Off"
        }
    }

    private func applyBlendMode(_ modeID: String) {
        guard session.adapter.supportedBlendModeIDs.contains(modeID) else { return }
        mutate { document in
            try CompositionMutationEngine.setBlendMode(
                modeID,
                layerIDs: selectedLayerIDs,
                compositionID: compositionID,
                document: &document
            )
        }
    }

    private func applyMatte(_ binding: MatteBinding?) {
        mutate { document in
            try CompositionMutationEngine.setMatte(
                binding,
                layerIDs: selectedLayerIDs,
                compositionID: compositionID,
                document: &document
            )
        }
    }

    private func applyParent(_ parentID: UUID?) {
        mutate { document in
            try CompositionMutationEngine.setParent(
                parentID,
                layerIDs: selectedLayerIDs,
                compositionID: compositionID,
                document: &document
            )
        }
    }

    private func applyAlphaInterpretation(_ interpretation: AlphaInterpretation) {
        applyChannelMapping(
            representativeLayer?.channelMapping ?? .identity,
            interpretation: interpretation,
            invertAlpha: representativeLayer?.isAlphaInverted ?? false
        )
    }

    private func applyChannelSource(_ source: ChannelSource, output: OutputChannel) {
        var mapping = representativeLayer?.channelMapping ?? .identity
        switch output {
        case .red: mapping.red = source
        case .green: mapping.green = source
        case .blue: mapping.blue = source
        case .alpha: mapping.alpha = source
        }
        applyChannelMapping(mapping)
    }

    private func applyChannelMapping(
        _ mapping: ChannelMapping,
        interpretation: AlphaInterpretation? = nil,
        invertAlpha: Bool? = nil
    ) {
        let resolvedInterpretation = interpretation ?? representativeLayer?.alphaInterpretation ?? .straight
        let resolvedInversion = invertAlpha ?? representativeLayer?.isAlphaInverted ?? false
        mutate { document in
            try CompositionMutationEngine.setChannelMapping(
                mapping,
                alphaInterpretation: resolvedInterpretation,
                invertAlpha: resolvedInversion,
                layerIDs: selectedLayerIDs,
                compositionID: compositionID,
                document: &document
            )
        }
    }

    private func mutate(_ operation: (inout CompositionDocument) throws -> Void) {
        var candidate = document
        do {
            try operation(&candidate)
            document = candidate
            coordinator.update(candidate)
            navigationItem.prompt = "Live preview"
            tableView.reloadData()
        } catch {
            navigationItem.prompt = "This edit is not valid for the current layer graph."
        }
    }

    private func layerName(_ id: UUID) -> String? {
        composition?.layers.first(where: { $0.id == id })?.name
    }

    private func compatibleLayerHandles() -> [HostLayerHandle] {
        session.adapter.snapshot()?.layers.filter { $0.isCompatible && !$0.isLocked } ?? []
    }

    private func menuButton(title: String, menu: UIMenu) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = menu
        button.sizeToFit()
        return button
    }

    private func scrollToPreferredSectionIfNeeded() {
        guard let preferredSection else { return }
        let target: Section
        switch preferredSection {
        case .blend: target = .blend
        case .matte: target = .matte
        case .parent: target = .parent
        case .alpha: target = .alpha
        case .channels: target = .channels
        }
        guard let section = sections.firstIndex(of: target), tableView.numberOfRows(inSection: section) > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
        }
    }

    @objc private func cancel() {
        coordinator.cancel(reason: .userCancelled)
        dismiss(animated: true)
    }

    @objc private func done() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let committed = await self.coordinator.commit(
                label: "Composition Edit",
                affectedCompositionID: self.compositionID
            )
            if committed {
                self.didCommit = true
                self.dismiss(animated: true)
            } else {
                self.navigationItem.prompt = "The host rejected the edit. The original state was restored."
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }
        }
    }
}
#endif
