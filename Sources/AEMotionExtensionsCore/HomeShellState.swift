import Foundation

public enum HomeShellTab: String, Codable, CaseIterable, Sendable {
    case home
    case tutorials
    case create
    case projects
    case templates
}

public enum HomeShellDestination: String, Codable, Equatable, Sendable {
    case root
    case detail
    case editor
    case templatePreview
    case tool
}

public struct HomeShellState: Codable, Equatable, Sendable {
    public var selectedTab: HomeShellTab
    public var destination: HomeShellDestination
    public var isCreateTrayExpanded: Bool

    public init(
        selectedTab: HomeShellTab = .home,
        destination: HomeShellDestination = .root,
        isCreateTrayExpanded: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.destination = destination
        self.isCreateTrayExpanded = isCreateTrayExpanded
    }

    public var isRootNavigationVisible: Bool { destination == .root }
}

public enum HomeShellEvent: Equatable, Sendable {
    case selectTab(HomeShellTab)
    case openDestination(HomeShellDestination)
    case returnToRoot
    case setCreateTrayExpanded(Bool)
}

public enum HomeShellReducer {
    public static func reduce(state: inout HomeShellState, event: HomeShellEvent) {
        switch event {
        case .selectTab(let tab):
            state.selectedTab = tab
            state.destination = .root
            state.isCreateTrayExpanded = false
        case .openDestination(let destination):
            state.destination = destination
            state.isCreateTrayExpanded = false
        case .returnToRoot:
            state.destination = .root
            state.isCreateTrayExpanded = false
        case .setCreateTrayExpanded(let isExpanded):
            guard state.destination == .root else {
                state.isCreateTrayExpanded = false
                return
            }
            state.isCreateTrayExpanded = isExpanded
        }
    }
}
