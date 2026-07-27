import Foundation

#if canImport(UIKit)
import UIKit
#endif

@_cdecl("AEMotionUI272Install")
public func AEMotionUI272Install() {
#if canImport(UIKit)
    DispatchQueue.main.async {
        AEMotionUI272Installer.start()
    }
#endif
}

enum AEMotionUI272Installer {
#if canImport(UIKit)
    @MainActor private static var hasStarted = false
    @MainActor private static var hasInstalled = false
    @MainActor private static var retryCount = 0
    @MainActor private static var retryScheduled = false
    @MainActor private static var observers: [NSObjectProtocol] = []
    private static let maximumRetryCount = 120
    private static let retryDelay: TimeInterval = 0.10

    @MainActor
    static func start() {
        if !hasStarted {
            hasStarted = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in attemptInstall() }
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in attemptInstall() }
            })
        }
        attemptInstall()
    }

    @MainActor
    private static func attemptInstall() {
        guard !hasInstalled else { return }
        retryScheduled = false
        if hostClassesAreReady(), AEMotionRuntimeResolver.install() {
            hasInstalled = true
            retryCount = 0
            return
        }
        guard retryCount < maximumRetryCount else { return }
        retryCount += 1
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            Task { @MainActor in attemptInstall() }
        }
    }

    @MainActor
    private static func hostClassesAreReady() -> Bool {
        let home = [
            "AlightMotion.HomeVC", "_TtC12AlightMotion6HomeVC",
            "AlightMotion.HomeViewVC", "_TtC12AlightMotion10HomeViewVC",
        ].contains { NSClassFromString($0) != nil }
        let projects = [
            "AlightMotion.ProjectsVC", "_TtC12AlightMotion10ProjectsVC",
        ].contains { NSClassFromString($0) != nil }
        let templates = [
            "AlightMotion.TemplatesVC", "_TtC12AlightMotion11TemplatesVC",
        ].contains { NSClassFromString($0) != nil }
        return home && projects && templates
    }
#else
    static func start() {}
#endif
}
