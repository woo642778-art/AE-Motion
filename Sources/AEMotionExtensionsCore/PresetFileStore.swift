import Foundation

public struct PresetLoadIssue: Equatable, Sendable {
    public var fileURL: URL
    public var message: String

    public init(fileURL: URL, message: String) {
        self.fileURL = fileURL
        self.message = message
    }
}

public struct PresetLoadResult: Sendable {
    public var documents: [PresetDocument]
    public var issues: [PresetLoadIssue]

    public init(documents: [PresetDocument], issues: [PresetLoadIssue]) {
        self.documents = documents
        self.issues = issues
    }
}

public struct PresetFileStore: Sendable {
    public let rootDirectory: URL
    public var builtinsDirectory: URL { rootDirectory.appendingPathComponent("Builtins", isDirectory: true) }
    public var userDirectory: URL { rootDirectory.appendingPathComponent("User", isDirectory: true) }
    public var quarantineDirectory: URL { rootDirectory.appendingPathComponent("Quarantine", isDirectory: true) }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func bootstrap(builtins: [PresetDocument]) throws {
        try createDirectories()
        for document in builtins {
            let validation = PresetValidator.validate(document)
            guard validation.isValid else {
                throw PresetXMLCodecError.invalidValue(validation.issues.map(\.message).joined(separator: "; "))
            }
            let destination = builtinsDirectory.appendingPathComponent(filename(for: document))
            let encoded = try PresetXMLCodec.encode(document)
            if (try? Data(contentsOf: destination)) != encoded {
                try encoded.write(to: destination, options: .atomic)
            }
        }
    }

    public func loadAll() -> PresetLoadResult {
        do { try createDirectories() } catch {
            return PresetLoadResult(documents: [], issues: [.init(fileURL: rootDirectory, message: error.localizedDescription)])
        }
        var documents: [PresetDocument] = []
        var issues: [PresetLoadIssue] = []
        for directory in [builtinsDirectory, userDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files.filter({ $0.pathExtension.lowercased() == "xml" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    let document = try PresetMigrator.migrate(PresetXMLCodec.decode(Data(contentsOf: file)))
                    let validation = PresetValidator.validate(document)
                    guard validation.isValid else {
                        throw PresetXMLCodecError.invalidValue(validation.issues.map(\.message).joined(separator: "; "))
                    }
                    documents.append(document)
                } catch {
                    issues.append(.init(fileURL: file, message: error.localizedDescription))
                    if directory == userDirectory { try? quarantine(file) }
                }
            }
        }
        var byID: [String: PresetDocument] = [:]
        for document in documents { byID[document.id] = document }
        return PresetLoadResult(documents: Array(byID.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, issues: issues)
    }

    @discardableResult
    public func save(_ document: PresetDocument) throws -> URL {
        try createDirectories()
        let validation = PresetValidator.validate(document)
        guard validation.isValid else {
            throw PresetXMLCodecError.invalidValue(validation.issues.map(\.message).joined(separator: "; "))
        }
        let destination = fileURL(for: document)
        try PresetXMLCodec.encode(document).write(to: destination, options: .atomic)
        return destination
    }

    public func importFile(_ source: URL, replacingExisting: Bool = false) throws -> PresetDocument {
        let document = try PresetMigrator.migrate(PresetXMLCodec.decode(Data(contentsOf: source)))
        let destination = fileURL(for: document)
        if FileManager.default.fileExists(atPath: destination.path), !replacingExisting {
            return try duplicate(document, newName: document.name + " Copy")
        }
        _ = try save(document)
        return document
    }

    public func export(_ document: PresetDocument, to destination: URL) throws {
        try PresetXMLCodec.encode(document).write(to: destination, options: .atomic)
    }

    @discardableResult
    public func duplicate(_ document: PresetDocument, newName: String) throws -> PresetDocument {
        var copy = document
        copy.id = "user.\(UUID().uuidString.lowercased())"
        copy.name = newName
        copy.createdAt = ISO8601DateFormatter().string(from: Date())
        copy.modifiedAt = copy.createdAt
        _ = try save(copy)
        return copy
    }

    @discardableResult
    public func rename(_ document: PresetDocument, to newName: String) throws -> PresetDocument {
        var copy = document
        copy.name = newName
        copy.modifiedAt = ISO8601DateFormatter().string(from: Date())
        _ = try save(copy)
        return copy
    }

    public func delete(_ document: PresetDocument) throws {
        let url = fileURL(for: document)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func fileURL(for document: PresetDocument) -> URL {
        userDirectory.appendingPathComponent(filename(for: document))
    }

    public func isBuiltin(_ document: PresetDocument) -> Bool {
        FileManager.default.fileExists(atPath: builtinsDirectory.appendingPathComponent(filename(for: document)).path)
    }

    private func filename(for document: PresetDocument) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let safe = document.id.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return (safe.isEmpty ? UUID().uuidString : safe) + ".xml"
    }

    private func createDirectories() throws {
        for directory in [rootDirectory, builtinsDirectory, userDirectory, quarantineDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func quarantine(_ file: URL) throws {
        try createDirectories()
        let destination = quarantineDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(file.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: file, to: destination)
    }
}
