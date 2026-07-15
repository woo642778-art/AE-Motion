import SwiftUI
import UIKit
import AEMotionExtensionsHost

@main
struct AEMotionTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            TestHostRootView()
        }
    }
}

@MainActor
private struct TestHostRootView: View {
    @State private var presentsExtensions = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 52, weight: .semibold))
                    .accessibilityHidden(true)

                Text("AE Motion Test Host")
                    .font(.title2.bold())

                Text("\(AEMotionTestHostBridge.registeredToolCount) tools registered")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("testhost.toolCount")

                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("testhost.ready")

                Button("Open Extensions & Scripts") {
                    presentsExtensions = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("testhost.openExtensions")
            }
            .padding(24)
            .navigationTitle("Test Host")
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(isPresented: $presentsExtensions) {
            ExtensionsControllerContainer()
                .ignoresSafeArea()
        }
    }
}

@MainActor
private struct ExtensionsControllerContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        AEMotionTestHostBridge.makeExtensionsRootViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
