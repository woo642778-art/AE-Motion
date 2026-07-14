import Foundation

public enum PerformanceMode: String, Codable, CaseIterable, Sendable {
    case batterySaver
    case balanced
    case maximumQuality
    case backgroundExport
    case thermalProtection
}

public enum ThermalLevel: String, Codable, CaseIterable, Sendable { case nominal, fair, serious, critical }
public enum PreviewScale: Int, Codable, CaseIterable, Sendable { case full = 1, half = 2, quarter = 4, eighth = 8 }

public enum ProxyPolicy {
    public static func recommendedScale(width: Int, height: Int, mode: PerformanceMode, thermal: ThermalLevel) -> PreviewScale {
        let longest = max(width, height)
        if thermal == .critical { return .eighth }
        if thermal == .serious { return longest >= 2160 ? .eighth : .quarter }
        switch mode {
        case .batterySaver: return longest >= 2160 ? .eighth : .quarter
        case .balanced: return longest >= 2160 ? .quarter : longest > 1280 ? .half : .full
        case .maximumQuality: return longest >= 3840 ? .half : .full
        case .backgroundExport: return .full
        case .thermalProtection: return thermal == .fair ? .quarter : .half
        }
    }
}

public struct CacheSummary: Codable, Equatable, Sendable {
    public var entryCount: Int
    public var totalBytes: Int64
    public var budgetBytes: Int64
    public var corruptCount: Int
}

public actor ProjectCacheStore {
    public let rootURL: URL
    public var budgetBytes: Int64
    private let fileManager: FileManager
    private var entries: [UUID: CacheReference] = [:]
    private var loaded = false

    public init(rootURL: URL, budgetBytes: Int64 = 2_000_000_000, fileManager: FileManager = .default) {
        self.rootURL = rootURL; self.budgetBytes = max(0, budgetBytes); self.fileManager = fileManager
    }

    private var indexURL: URL { rootURL.appendingPathComponent("cache-index.json") }
    private func fileURL(_ entry: CacheReference) -> URL { rootURL.appendingPathComponent(entry.relativePath) }

    public func register(_ entry: CacheReference) throws {
        try ensureLoaded(); entries[entry.id] = entry; try persist(); try evictIfNeeded()
    }

    public func registerFile(at url: URL, kind: CacheKind, dependencyKeys: [String] = []) throws -> CacheReference {
        try ensureLoaded(); let data = try Data(contentsOf: url)
        let relative = url.path.hasPrefix(rootURL.path) ? String(url.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : url.lastPathComponent
        let entry = CacheReference(kind: kind, relativePath: relative, sizeBytes: Int64(data.count), checksum: StableChecksum.hexDigest(data), dependencyKeys: dependencyKeys)
        entries[entry.id] = entry; try persist(); try evictIfNeeded(); return entry
    }

    public func touch(_ id: UUID, at date: Date = Date()) throws {
        try ensureLoaded(); guard var entry = entries[id] else { return }; entry.lastAccessedAt = date; entries[id] = entry; try persist()
    }

    public func invalidate(dependencyKey: String) throws -> [UUID] {
        try ensureLoaded(); let ids = entries.values.filter { $0.dependencyKeys.contains(dependencyKey) }.map(\.id)
        for id in ids { try remove(id) }; return ids
    }

    public func validate() throws -> [UUID] {
        try ensureLoaded(); return entries.values.compactMap { entry in
            let url = fileURL(entry)
            guard let data = try? Data(contentsOf: url), StableChecksum.hexDigest(data) == entry.checksum else { return entry.id }
            return nil
        }
    }

    public func purgeCorrupt() throws -> [UUID] {
        let corrupt = try validate(); for id in corrupt { try remove(id) }; return corrupt
    }

    public func clear() throws {
        try ensureLoaded()
        for id in Array(entries.keys) { try remove(id) }
        try persist()
    }

    public func summary() throws -> CacheSummary {
        try ensureLoaded(); return CacheSummary(entryCount: entries.count, totalBytes: entries.values.reduce(0) { $0 + $1.sizeBytes }, budgetBytes: budgetBytes, corruptCount: try validate().count)
    }

    public func allEntries() throws -> [CacheReference] { try ensureLoaded(); return entries.values.sorted { $0.lastAccessedAt > $1.lastAccessedAt } }

    private func remove(_ id: UUID) throws {
        guard let entry = entries.removeValue(forKey: id) else { return }
        let url = fileURL(entry); if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try persist()
    }

    private func evictIfNeeded() throws {
        var total = entries.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
        for entry in entries.values.sorted(by: { $0.lastAccessedAt < $1.lastAccessedAt }) where total > budgetBytes {
            total -= entry.sizeBytes; try remove(entry.id)
        }
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }; loaded = true
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        let values = try ProjectStore.decoder().decode([CacheReference].self, from: Data(contentsOf: indexURL))
        entries = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ProjectStore.encoder().encode(Array(entries.values)).write(to: indexURL, options: .atomic)
    }
}
