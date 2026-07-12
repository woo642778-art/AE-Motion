import Foundation

public struct HostCategory: Equatable, Sendable, Codable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct ToolDescriptor: Identifiable, Equatable, Sendable, Codable {
    public enum Section: String, Codable, Sendable { case extensions, scripts, presets, utilities, favorites }
    public let id: String
    public let title: String
    public let subtitle: String
    public let section: Section
    public init(id: String, title: String, subtitle: String, section: Section) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.section = section
    }
}

public struct KeyframePoint: Equatable, Sendable, Codable {
    public let frame: Int
    public let value: Double
    public init(frame: Int, value: Double) { self.frame = frame; self.value = value }
}

public struct RGBAColor: Equatable, Sendable, Codable {
    public let red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}
