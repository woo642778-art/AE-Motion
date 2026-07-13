#if canImport(UIKit)
import Foundation
import UIKit
import AEMotionExtensionsCore

@MainActor
final class PresetLibraryEnvironment {
    static let shared = PresetLibraryEnvironment()
    static let didChangeNotification = Notification.Name("AEMotionPresetLibraryDidChange")

    private let favoritesKey = "AEMotionPresetLibrary.favorites"
    private let collectionsKey = "AEMotionPresetLibrary.collections"
    private let recentKey = "AEMotionPresetLibrary.recent"
    private let usageKey = "AEMotionPresetLibrary.usage"

    let store: PresetFileStore
    private(set) var documents: [PresetDocument] = []
    private(set) var loadIssues: [PresetLoadIssue] = []
    private(set) var favoriteIDs: Set<String>
    private(set) var collections: [String: Set<String>]
    private(set) var recentIDs: [String]
    private(set) var usageCounts: [String: Int]

    private init() {
        let defaults = UserDefaults.standard
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        store = PresetFileStore(rootDirectory: base.appendingPathComponent("AE-Motion-Presets", isDirectory: true))
        favoriteIDs = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        recentIDs = defaults.stringArray(forKey: recentKey) ?? []
        usageCounts = (defaults.dictionary(forKey: usageKey) ?? [:]).reduce(into: [:]) { result, entry in
            if let value = entry.value as? NSNumber { result[entry.key] = value.intValue }
        }
        collections = (defaults.dictionary(forKey: collectionsKey) ?? [:]).reduce(into: [:]) { result, entry in
            if let values = entry.value as? [String] { result[entry.key] = Set(values) }
        }
        do { try store.bootstrap(builtins: PresetBuiltins.all) } catch {
            loadIssues = [.init(fileURL: store.rootDirectory, message: error.localizedDescription)]
        }
        reload(postNotification: false)
    }

    func reload(postNotification: Bool = true) {
        let result = store.loadAll()
        documents = result.documents
        loadIssues = result.issues
        let validIDs = Set(documents.map(\.id))
        favoriteIDs.formIntersection(validIDs)
        recentIDs = recentIDs.filter(validIDs.contains)
        collections = collections.reduce(into: [:]) { output, entry in
            let values = entry.value.intersection(validIDs)
            if !values.isEmpty { output[entry.key] = values }
        }
        usageCounts = usageCounts.filter { validIDs.contains($0.key) }
        persistMetadata()
        if postNotification { notify() }
    }

    func save(_ document: PresetDocument) throws {
        _ = try store.save(document)
        reload()
    }

    func duplicate(_ document: PresetDocument, name: String? = nil) throws -> PresetDocument {
        let copy = try store.duplicate(document, newName: name ?? document.name + " Copy")
        reload()
        return copy
    }

    func rename(_ document: PresetDocument, name: String) throws -> PresetDocument {
        let renamed = try store.rename(document, to: name)
        reload()
        return renamed
    }

    func delete(_ document: PresetDocument) throws {
        try store.delete(document)
        favoriteIDs.remove(document.id)
        recentIDs.removeAll { $0 == document.id }
        usageCounts.removeValue(forKey: document.id)
        for key in Array(collections.keys) { collections[key]?.remove(document.id) }
        persistMetadata()
        reload()
    }

    func importFile(_ url: URL) throws -> PresetDocument {
        let document = try store.importFile(url)
        reload()
        return document
    }

    func exportURL(for document: PresetDocument) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AE-Motion-Preset-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = document.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(safe).aemotionpreset.xml")
        try store.export(document, to: url)
        return url
    }

    func toggleFavorite(_ document: PresetDocument) {
        if favoriteIDs.contains(document.id) { favoriteIDs.remove(document.id) }
        else { favoriteIDs.insert(document.id) }
        persistMetadata()
        notify()
    }

    func recordUse(_ document: PresetDocument) {
        usageCounts[document.id, default: 0] += 1
        recentIDs.removeAll { $0 == document.id }
        recentIDs.insert(document.id, at: 0)
        if recentIDs.count > 50 { recentIDs.removeLast(recentIDs.count - 50) }
        persistMetadata()
        notify()
    }

    func usageCount(_ document: PresetDocument) -> Int { usageCounts[document.id, default: 0] }
    func recentRank(_ document: PresetDocument) -> Int? { recentIDs.firstIndex(of: document.id) }
    func isFavorite(_ document: PresetDocument) -> Bool { favoriteIDs.contains(document.id) }
    func isBuiltin(_ document: PresetDocument) -> Bool { document.id.hasPrefix("builtin.") }

    var collectionNames: [String] {
        collections.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func isInCollection(_ document: PresetDocument, name: String) -> Bool {
        collections[name]?.contains(document.id) ?? false
    }

    func setCollection(_ name: String, contains document: PresetDocument, enabled: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if enabled { collections[clean, default: []].insert(document.id) }
        else {
            collections[clean]?.remove(document.id)
            if collections[clean]?.isEmpty == true { collections.removeValue(forKey: clean) }
        }
        persistMetadata()
        notify()
    }

    func documents(inCollection name: String?) -> [PresetDocument] {
        guard let name else { return documents }
        let ids = collections[name] ?? []
        return documents.filter { ids.contains($0.id) }
    }

    func runtimeContext() -> PresetRuntimeContext {
        PresetRuntimeContext(
            appVersion: "2.0.2",
            iOSVersion: UIDevice.current.systemVersion,
            availableTargets: ["speed.remap", "easing.curve", "camera.shake", "color.palette", "text.animator", "effect.generic", "template.editable"],
            availableFonts: Set(UIFont.familyNames),
            availableEffects: nil,
            availableMedia: nil,
            availableModels: nil,
            availableFeatures: ["preset.xml.1", "macro.controls", "resource.hub", "native.ui.theme", "contextual.tool.placement", "effect-picker.empty-state"]
        )
    }

    func userTemplate(kind: PresetKind = .motion) -> PresetDocument {
        let now = ISO8601DateFormatter().string(from: Date())
        return PresetDocument(
            id: "user.\(UUID().uuidString.lowercased())",
            name: "Untitled Preset",
            summary: "",
            author: "",
            kind: kind,
            targets: [defaultTarget(for: kind)],
            tags: [],
            template: kind == .editableTemplate ? EditableTemplateDefinition() : nil,
            createdAt: now,
            modifiedAt: now
        )
    }

    private func defaultTarget(for kind: PresetKind) -> String {
        switch kind {
        case .velocity: return "speed.remap"
        case .graph: return "easing.curve"
        case .motion: return "camera.shake"
        case .color: return "color.palette"
        case .text: return "text.animator"
        case .editableTemplate: return "template.editable"
        default: return "effect.generic"
        }
    }

    private func persistMetadata() {
        let defaults = UserDefaults.standard
        defaults.set(Array(favoriteIDs).sorted(), forKey: favoritesKey)
        defaults.set(recentIDs, forKey: recentKey)
        defaults.set(usageCounts, forKey: usageKey)
        defaults.set(collections.mapValues { Array($0).sorted() }, forKey: collectionsKey)
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
#endif
