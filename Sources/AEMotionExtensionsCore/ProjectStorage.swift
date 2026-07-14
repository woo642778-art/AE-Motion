import Foundation

public enum StableChecksum {
    public static func hexDigest(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash ^= UInt64(byte); hash &*= 0x100000001b3 }
        return String(format: "%016llx", hash)
    }
}

public enum ProjectStoreError: Error, Equatable, LocalizedError {
    case checksumMismatch
    case projectNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "Project checksum does not match the saved document."
        case let .projectNotFound(id): return "Project not found: \(id)"
        }
    }
}

public actor ProjectStore {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL; self.fileManager = fileManager
    }

    public func projectURL(for id: UUID) -> URL { rootURL.appendingPathComponent("\(id.uuidString).\(ProjectSchema.fileExtension)") }
    private func checksumURL(for id: UUID) -> URL { rootURL.appendingPathComponent("\(id.uuidString).checksum") }

    public func save(_ document: ProjectDocument) throws {
        try ProjectValidator.validate(document)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(document)
        try data.write(to: projectURL(for: document.id), options: .atomic)
        try Data((StableChecksum.hexDigest(data) + "\n").utf8).write(to: checksumURL(for: document.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> ProjectDocument {
        let url = projectURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { throw ProjectStoreError.projectNotFound(id) }
        return try decodeVerified(try Data(contentsOf: url), checksumURL: checksumURL(for: id))
    }

    public func importDocument(_ data: Data) throws -> ProjectDocument {
        let migrated = try ProjectSchemaMigrator.migrate(data)
        let document = try Self.decoder().decode(ProjectDocument.self, from: migrated)
        try save(document)
        return document
    }

    public func exportDocument(_ id: UUID) throws -> Data {
        let document = try load(id)
        return try Self.encoder().encode(document)
    }

    public func listProjects() throws -> [ProjectDocument] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ProjectSchema.fileExtension }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                return try? load(id)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func delete(_ id: UUID) throws {
        for url in [projectURL(for: id), checksumURL(for: id)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func decodeVerified(_ data: Data, checksumURL: URL) throws -> ProjectDocument {
        if fileManager.fileExists(atPath: checksumURL.path) {
            let expected = try String(contentsOf: checksumURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard expected == StableChecksum.hexDigest(data) else { throw ProjectStoreError.checksumMismatch }
        }
        let migrated = try ProjectSchemaMigrator.migrate(data)
        let document = try Self.decoder().decode(ProjectDocument.self, from: migrated)
        try ProjectValidator.validate(document)
        return document
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .secondsSince1970; return encoder
    }

    public static func compactEncoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .secondsSince1970; return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970; return decoder
    }
}

public enum JournalPhase: String, Codable, Sendable { case prepared, committed }

public struct JournalRecord: Codable, Equatable, Sendable {
    public var phase: JournalPhase
    public var command: ProjectCommand
    public init(phase: JournalPhase, command: ProjectCommand) { self.phase = phase; self.command = command }
}

public actor ProjectJournal {
    public let rootURL: URL
    private let fileManager: FileManager
    public init(rootURL: URL, fileManager: FileManager = .default) { self.rootURL = rootURL; self.fileManager = fileManager }
    private func url(for projectID: UUID) -> URL { rootURL.appendingPathComponent("\(projectID.uuidString).journal") }

    public func append(_ record: JournalRecord, projectID: UUID) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let url = url(for: projectID)
        if !fileManager.fileExists(atPath: url.path) { _ = fileManager.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try ProjectStore.compactEncoder().encode(record); data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    public func committedCommands(projectID: UUID, after sequence: UInt64) throws -> [ProjectCommand] {
        let url = url(for: projectID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        var committed: [UUID: ProjectCommand] = [:]
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            let record = try ProjectStore.decoder().decode(JournalRecord.self, from: Data(line))
            if record.phase == .committed, record.command.sequence > sequence { committed[record.command.id] = record.command }
        }
        return committed.values.sorted { $0.sequence < $1.sequence }
    }

    public func highestSequence(projectID: UUID) throws -> UInt64 {
        let url = url(for: projectID)
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).filter { !$0.isEmpty }.map {
            try ProjectStore.decoder().decode(JournalRecord.self, from: Data($0)).command.sequence
        }.max() ?? 0
    }

    public func compact(projectID: UUID, through sequence: UInt64) throws {
        let url = url(for: projectID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let remaining = try data.split(separator: 0x0A).filter { !$0.isEmpty }.compactMap { line -> Data? in
            let record = try ProjectStore.decoder().decode(JournalRecord.self, from: Data(line))
            guard record.command.sequence > sequence else { return nil }
            var encoded = try ProjectStore.compactEncoder().encode(record); encoded.append(0x0A); return encoded
        }.reduce(into: Data()) { $0.append($1) }
        try remaining.write(to: url, options: .atomic)
    }
}
