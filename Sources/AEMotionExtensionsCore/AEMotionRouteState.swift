import Foundation

public enum AEMotionRootTab: String, Codable, CaseIterable, Sendable {
    case home
    case tutorials
    case projects
    case templates
}

public enum AEMotionModalRoute: String, Codable, Equatable, Sendable {
    case createTray
    case settings
    case account
    case officialChannel
}

public enum AEMotionNonRootRoute: String, Codable, Equatable, Sendable {
    case projectEditor
    case templatePreview
    case threeDStudio
    case worldStudio
    case tool
    case export
}

public struct AEMotionRouteState: Codable, Equatable, Sendable {
    public var selectedTab: AEMotionRootTab
    public var modal: AEMotionModalRoute?
    public var nonRoot: AEMotionNonRootRoute?
    public var isCreateTrayPresented: Bool

    public init(
        selectedTab: AEMotionRootTab = .home,
        modal: AEMotionModalRoute? = nil,
        nonRoot: AEMotionNonRootRoute? = nil,
        isCreateTrayPresented: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.modal = modal
        self.nonRoot = nonRoot
        self.isCreateTrayPresented = isCreateTrayPresented
        normalizeTransientState()
    }

    public var isAtRoot: Bool {
        modal == nil && nonRoot == nil
    }

    public var isRootChromeVisible: Bool {
        nonRoot == nil
    }

    mutating func normalizeTransientState() {
        if modal != .createTray {
            isCreateTrayPresented = false
        }
        if nonRoot != nil {
            modal = nil
            isCreateTrayPresented = false
        }
    }
}

public enum AEMotionRouteEvent: Equatable, Sendable {
    case selectTab(AEMotionRootTab)
    case toggleCreateTray
    case dismissCreateTray
    case presentModal(AEMotionModalRoute)
    case dismissModal
    case confirmNonRoot(AEMotionNonRootRoute)
    case returnToRoot(AEMotionRootTab)
    case routeFailed
    case applicationDidEnterBackground
}

public enum AEMotionRouteReducer {
    public static func reduce(
        state: inout AEMotionRouteState,
        event: AEMotionRouteEvent
    ) {
        switch event {
        case .selectTab(let tab):
            state.selectedTab = tab
            state.modal = nil
            state.nonRoot = nil
            state.isCreateTrayPresented = false

        case .toggleCreateTray:
            guard state.nonRoot == nil else {
                state.modal = nil
                state.isCreateTrayPresented = false
                return
            }
            let willPresent = !state.isCreateTrayPresented
            state.modal = willPresent ? .createTray : nil
            state.isCreateTrayPresented = willPresent

        case .dismissCreateTray:
            if state.modal == .createTray {
                state.modal = nil
            }
            state.isCreateTrayPresented = false

        case .presentModal(let route):
            state.modal = route
            state.nonRoot = nil
            state.isCreateTrayPresented = route == .createTray

        case .dismissModal:
            state.modal = nil
            state.isCreateTrayPresented = false

        case .confirmNonRoot(let route):
            state.modal = nil
            state.nonRoot = route
            state.isCreateTrayPresented = false

        case .returnToRoot(let tab):
            state.selectedTab = tab
            state.modal = nil
            state.nonRoot = nil
            state.isCreateTrayPresented = false

        case .routeFailed:
            break

        case .applicationDidEnterBackground:
            if state.modal == .createTray {
                state.modal = nil
            }
            state.isCreateTrayPresented = false
        }
    }
}
