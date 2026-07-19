#if canImport(UIKit)
import Foundation
import UIKit
import ObjectiveC.runtime

@MainActor
enum GoogleSignInCallbackRepair {
    private static var installedDelegateClasses = Set<ObjectIdentifier>()

    static func install() -> Bool {
        guard let delegate = UIApplication.shared.delegate,
              let delegateClass = object_getClass(delegate) else {
            return false
        }

        let classID = ObjectIdentifier(delegateClass)
        if installedDelegateClasses.contains(classID) {
            return true
        }

        let selector = NSSelectorFromString("application:openURL:options:")
        let originalMethod = class_getInstanceMethod(delegateClass, selector)
        let originalIMP = originalMethod.map(method_getImplementation)

        let block: @convention(block) (AnyObject, UIApplication, NSURL, NSDictionary) -> Bool = {
            object,
            application,
            url,
            options in

            var originalHandled = false
            if let originalIMP {
                typealias OriginalImplementation = @convention(c) (
                    AnyObject,
                    Selector,
                    UIApplication,
                    NSURL,
                    NSDictionary
                ) -> Bool
                let original = unsafeBitCast(originalIMP, to: OriginalImplementation.self)
                originalHandled = original(object, selector, application, url, options)
            }

            if originalHandled {
                return true
            }

            let handled = handleGoogleURL(url as URL)
            if handled {
                Task { @MainActor in
                    AuthenticationTimeoutGuard.noteCallbackHandled()
                }
            }
            return handled
        }

        let replacementIMP = imp_implementationWithBlock(block)
        if let originalMethod,
           let typeEncoding = method_getTypeEncoding(originalMethod) {
            class_replaceMethod(delegateClass, selector, replacementIMP, typeEncoding)
        } else {
            "B@:@@@".withCString { typeEncoding in
                class_addMethod(delegateClass, selector, replacementIMP, typeEncoding)
            }
        }

        installedDelegateClasses.insert(classID)
        return true
    }

    nonisolated private static func handleGoogleURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme.hasPrefix("com.googleusercontent.apps.") else {
            return false
        }

        guard let signInClass = NSClassFromString("GIDSignIn") else {
            return false
        }

        let sharedSelector = NSSelectorFromString("sharedInstance")
        guard let sharedMethod = class_getClassMethod(signInClass, sharedSelector) else {
            return false
        }

        typealias SharedImplementation = @convention(c) (AnyClass, Selector) -> AnyObject?
        let sharedFunction = unsafeBitCast(
            method_getImplementation(sharedMethod),
            to: SharedImplementation.self
        )
        guard let sharedInstance = sharedFunction(signInClass, sharedSelector),
              let instanceClass = object_getClass(sharedInstance) else {
            return false
        }

        let handleSelector = NSSelectorFromString("handleURL:")
        guard let handleMethod = class_getInstanceMethod(instanceClass, handleSelector) else {
            return false
        }

        typealias HandleImplementation = @convention(c) (AnyObject, Selector, NSURL) -> Bool
        let handleFunction = unsafeBitCast(
            method_getImplementation(handleMethod),
            to: HandleImplementation.self
        )
        return handleFunction(sharedInstance, handleSelector, url as NSURL)
    }
}
#endif
