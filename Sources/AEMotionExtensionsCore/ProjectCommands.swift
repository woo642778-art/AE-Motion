import Foundation

public enum ProjectMutation: Equatable, Sendable {
    case renameProject(String)
    case setMetadata(key: String, value: String?)
    case addMedia(MediaReference)
    case removeMedia(UUID)
    case addSequence(ProjectSequence)
    case removeSequence(UUID)
}

extension ProjectMutation: Codable {
    private enum CodingKeys: String, CodingKey { case type, name, key, value, media, id, sequence }
    private enum Kind: String, Codable { case renameProject, setMetadata, addMedia, removeMedia, addSequence, removeSequence }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .renameProject: self = .renameProject(try c.decode(String.self, forKey: .name))
        case .setMetadata: self = .setMetadata(key: try c.decode(String.self, forKey: .key), value: try c.decodeIfPresent(String.self, forKey: .value))
        case .addMedia: self = .addMedia(try c.decode(MediaReference.self, forKey: .media))
        case .removeMedia: self = .removeMedia(try c.decode(UUID.self, forKey: .id))
        case .addSequence: self = .addSequence(try c.decode(ProjectSequence.self, forKey: .sequence))
        case .removeSequence: self = .removeSequence(try c.decode(UUID.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .renameProject(name): try c.encode(Kind.renameProject, forKey: .type); try c.encode(name, forKey: .name)
        case let .setMetadata(key, value): try c.encode(Kind.setMetadata, forKey: .type); try c.encode(key, forKey: .key); try c.encodeIfPresent(value, forKey: .value)
        case let .addMedia(media): try c.encode(Kind.addMedia, forKey: .type); try c.encode(media, forKey: .media)
        case let .removeMedia(id): try c.encode(Kind.removeMedia, forKey: .type); try c.encode(id, forKey: .id)
        case let .addSequence(sequence): try c.encode(Kind.addSequence, forKey: .type); try c.encode(sequence, forKey: .sequence)
        case let .removeSequence(id): try c.encode(Kind.removeSequence, forKey: .type); try c.encode(id, forKey: .id)
        }
    }

    public func inverse(in document: ProjectDocument) -> ProjectMutation? {
        switch self {
        case .renameProject: return .renameProject(document.name)
        case let .setMetadata(key, _): return .setMetadata(key: key, value: document.metadata[key])
        case let .addMedia(media): return .removeMedia(media.id)
        case let .removeMedia(id): return document.media.first(where: { $0.id == id }).map(ProjectMutation.addMedia)
        case let .addSequence(sequence): return .removeSequence(sequence.id)
        case let .removeSequence(id): return document.sequences.first(where: { $0.id == id }).map(ProjectMutation.addSequence)
        }
    }

    public func apply(to document: inout ProjectDocument, sequence: UInt64, now: Date = Date()) {
        switch self {
        case let .renameProject(name): document.name = name
        case let .setMetadata(key, value):
            if let value { document.metadata[key] = value } else { document.metadata.removeValue(forKey: key) }
        case let .addMedia(media):
            document.media.removeAll { $0.id == media.id }; document.media.append(media)
        case let .removeMedia(id): document.media.removeAll { $0.id == id }
        case let .addSequence(newSequence):
            document.sequences.removeAll { $0.id == newSequence.id }; document.sequences.append(newSequence)
        case let .removeSequence(id): document.sequences.removeAll { $0.id == id }
        }
        document.modifiedAt = now
        document.lastAppliedCommandSequence = max(document.lastAppliedCommandSequence, sequence)
    }
}

public struct ProjectCommand: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sequence: UInt64
    public var createdAt: Date
    public var mutation: ProjectMutation
    public var label: String

    public init(id: UUID = UUID(), sequence: UInt64, createdAt: Date = Date(), mutation: ProjectMutation, label: String) {
        self.id = id; self.sequence = sequence; self.createdAt = createdAt; self.mutation = mutation; self.label = label
    }
}
