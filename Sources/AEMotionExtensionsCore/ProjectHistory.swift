import Foundation

public struct ProjectSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var projectID: UUID
    public var createdAt: Date
    public var label: String
    public var commandSequence: UInt64
    public var isBookmark: Bool
    public var document: ProjectDocument

    public init(id: UUID = UUID(), projectID: UUID, createdAt: Date = Date(), label: String, commandSequence: UInt64, isBookmark: Bool = false, document: ProjectDocument) {
        self.id = id; self.projectID = projectID; self.createdAt = createdAt; self.label = label
        self.commandSequence = commandSequence; self.isBookmark = isBookmark; self.document = document
    }
}

public struct ProjectDiff: Codable, Equatable, Sendable {
    public var nameChanged: Bool
    public var sequenceDelta: Int
    public var mediaDelta: Int
    public var cacheDelta: Int
    public var metadataKeysChanged: [String]
}

public actor ProjectHistoryStore {
    public let rootURL: URL
    public let maximumSnapshots: Int
    private let fileManager: FileManager

    public init(rootURL: URL, maximumSnapshots: Int = 30, fileManager: FileManager = .default) {
        self.rootURL = rootURL; self.maximumSnapshots = max(3, maximumSnapshots); self.fileManager = fileManager
    }

    private func directory(for projectID: UUID) -> URL { rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true) }

    public func save(_ snapshot: ProjectSnapshot) throws {
        let directory = directory(for: snapshot.projectID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = String(format: "%020llu-%@.json", snapshot.commandSequence, snapshot.id.uuidString)
        try ProjectStore.encoder().encode(snapshot).write(to: directory.appendingPathComponent(name), options: .atomic)
        try trim(projectID: snapshot.projectID)
    }

    public func list(projectID: UUID) throws -> [ProjectSnapshot] {
        let directory = directory(for: projectID)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? ProjectStore.decoder().decode(ProjectSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func bookmark(snapshotID: UUID, projectID: UUID, isBookmark: Bool = true) throws {
        let directory = directory(for: projectID)
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard var snapshot = try? ProjectStore.decoder().decode(ProjectSnapshot.self, from: Data(contentsOf: url)), snapshot.id == snapshotID else { continue }
            snapshot.isBookmark = isBookmark
            try ProjectStore.encoder().encode(snapshot).write(to: url, options: .atomic)
            return
        }
    }

    public func recoveryPoints(projectID: UUID, now: Date = Date()) throws -> [ProjectSnapshot] {
        let snapshots = try list(projectID: projectID)
        guard !snapshots.isEmpty else { return [] }
        var selected: [UUID: ProjectSnapshot] = [snapshots[0].id: snapshots[0]]
        for target in [60.0, 300.0, 600.0] {
            if let nearest = snapshots.min(by: { abs(now.timeIntervalSince($0.createdAt) - target) < abs(now.timeIntervalSince($1.createdAt) - target) }) {
                selected[nearest.id] = nearest
            }
        }
        for snapshot in snapshots where snapshot.isBookmark { selected[snapshot.id] = snapshot }
        return selected.values.sorted { $0.createdAt > $1.createdAt }
    }

    public static func diff(_ older: ProjectSnapshot, _ newer: ProjectSnapshot) -> ProjectDiff {
        let keys = Set(older.document.metadata.keys).union(newer.document.metadata.keys)
        return ProjectDiff(
            nameChanged: older.document.name != newer.document.name,
            sequenceDelta: newer.document.sequences.count - older.document.sequences.count,
            mediaDelta: newer.document.media.count - older.document.media.count,
            cacheDelta: newer.document.caches.count - older.document.caches.count,
            metadataKeysChanged: keys.filter { older.document.metadata[$0] != newer.document.metadata[$0] }.sorted()
        )
    }

    private func trim(projectID: UUID) throws {
        let directory = directory(for: projectID)
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let values: [(URL, ProjectSnapshot)] = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url), let snapshot = try? ProjectStore.decoder().decode(ProjectSnapshot.self, from: data) else { return nil }
            return (url, snapshot)
        }.sorted { $0.1.createdAt > $1.1.createdAt }
        let removable = values.filter { !$0.1.isBookmark }.dropFirst(maximumSnapshots)
        for item in removable { try fileManager.removeItem(at: item.0) }
    }
}

public actor ProjectSession {
    public private(set) var document: ProjectDocument?
    private let store: ProjectStore
    private let journal: ProjectJournal
    private let history: ProjectHistoryStore
    private var undoStack: [(forward: ProjectMutation, inverse: ProjectMutation, label: String)] = []
    private var redoStack: [(forward: ProjectMutation, inverse: ProjectMutation, label: String)] = []

    public init(store: ProjectStore, journal: ProjectJournal, history: ProjectHistoryStore) {
        self.store = store; self.journal = journal; self.history = history
    }

    public func create(_ document: ProjectDocument) async throws {
        try await store.save(document)
        self.document = document
        try await history.save(ProjectSnapshot(projectID: document.id, label: "Created", commandSequence: 0, isBookmark: true, document: document))
    }

    @discardableResult
    public func open(_ id: UUID) async throws -> ProjectDocument {
        var loaded = try await store.load(id)
        let commands = try await journal.committedCommands(projectID: id, after: loaded.lastAppliedCommandSequence)
        for command in commands { command.mutation.apply(to: &loaded, sequence: command.sequence, now: command.createdAt) }
        if !commands.isEmpty {
            try await store.save(loaded)
            try await history.save(ProjectSnapshot(projectID: id, label: "Recovered \(commands.count) change(s)", commandSequence: loaded.lastAppliedCommandSequence, document: loaded))
            try await journal.compact(projectID: id, through: loaded.lastAppliedCommandSequence)
        }
        document = loaded; undoStack.removeAll(); redoStack.removeAll(); return loaded
    }

    @discardableResult
    public func perform(_ mutation: ProjectMutation, label: String) async throws -> ProjectDocument {
        guard var current = document else { throw ProjectStoreError.projectNotFound(UUID()) }
        let inverse = mutation.inverse(in: current)
        let highest = try await journal.highestSequence(projectID: current.id)
        let command = ProjectCommand(sequence: max(highest, current.lastAppliedCommandSequence) + 1, mutation: mutation, label: label)
        try await journal.append(JournalRecord(phase: .prepared, command: command), projectID: current.id)
        try await journal.append(JournalRecord(phase: .committed, command: command), projectID: current.id)
        mutation.apply(to: &current, sequence: command.sequence, now: command.createdAt)
        try await store.save(current)
        try await history.save(ProjectSnapshot(projectID: current.id, label: label, commandSequence: command.sequence, document: current))
        try await journal.compact(projectID: current.id, through: command.sequence)
        document = current
        if let inverse { undoStack.append((mutation, inverse, label)); redoStack.removeAll() }
        return current
    }

    @discardableResult
    public func undo() async throws -> ProjectDocument? {
        guard let entry = undoStack.popLast() else { return document }
        let result = try await applyWithoutHistoryStack(entry.inverse, label: "Undo: \(entry.label)")
        redoStack.append(entry); return result
    }

    @discardableResult
    public func redo() async throws -> ProjectDocument? {
        guard let entry = redoStack.popLast() else { return document }
        let result = try await applyWithoutHistoryStack(entry.forward, label: "Redo: \(entry.label)")
        undoStack.append(entry); return result
    }

    public func branch(name: String) async throws -> ProjectDocument {
        guard var copy = document else { throw ProjectStoreError.projectNotFound(UUID()) }
        let parent = copy.id
        copy.id = UUID(); copy.name = name; copy.createdAt = Date(); copy.modifiedAt = copy.createdAt
        copy.lastAppliedCommandSequence = 0; copy.metadata["parentProjectID"] = parent.uuidString
        try await store.save(copy)
        try await history.save(ProjectSnapshot(projectID: copy.id, label: "Branched from \(parent.uuidString)", commandSequence: 0, isBookmark: true, document: copy))
        return copy
    }

    private func applyWithoutHistoryStack(_ mutation: ProjectMutation, label: String) async throws -> ProjectDocument {
        let savedUndo = undoStack, savedRedo = redoStack
        let result = try await perform(mutation, label: label)
        undoStack = savedUndo; redoStack = savedRedo
        return result
    }
}

public enum ProjectRecoverySelfTest {
    public static func run(in rootURL: URL) async throws -> Bool {
        let store = ProjectStore(rootURL: rootURL.appendingPathComponent("Projects"))
        let journal = ProjectJournal(rootURL: rootURL.appendingPathComponent("Journals"))
        let history = ProjectHistoryStore(rootURL: rootURL.appendingPathComponent("History"))
        let original = ProjectDocument.empty(name: "Recovery Test")
        try await store.save(original)
        let command = ProjectCommand(sequence: 1, mutation: .renameProject("Recovered Project"), label: "Simulated crash change")
        try await journal.append(JournalRecord(phase: .prepared, command: command), projectID: original.id)
        try await journal.append(JournalRecord(phase: .committed, command: command), projectID: original.id)
        let session = ProjectSession(store: store, journal: journal, history: history)
        let recovered = try await session.open(original.id)
        return recovered.name == "Recovered Project" && recovered.lastAppliedCommandSequence == 1
    }
}
