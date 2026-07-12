import Foundation

public enum CategoryInjector {
    public static let extensions = HostCategory(id: "com.aemotion.extensions", title: "Extensions & Scripts")

    public static func insertExtensionsCategory(in categories: [HostCategory]) -> [HostCategory] {
        guard !categories.contains(where: { $0.id == extensions.id }) else { return categories }
        var result = categories
        if let index = result.firstIndex(where: { isMoveTransform($0) }) {
            result.insert(extensions, at: result.index(after: index))
        } else {
            result.append(extensions)
        }
        return result
    }

    public static func isMoveTransform(_ category: HostCategory) -> Bool {
        let normalized = normalize(category.id + " " + category.title)
        return normalized.contains("move") && normalized.contains("transform")
    }

    public static func normalize(_ input: String) -> String {
        input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
