#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import AEMotionExtensionsCore

@MainActor
final class ProjectReliabilityViewController: UIViewController, UIDocumentPickerDelegate {
    private let status = ExtensionUI.label("No reliability test has been run.")
    private let reportView = UITextView()
    private var report = ""
    private var latestProjectID: UUID?

    private lazy var rootURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AE Motion/StudioCore", isDirectory: true)
    }()
    private lazy var store = ProjectStore(rootURL: rootURL.appendingPathComponent("Projects"))
    private lazy var journal = ProjectJournal(rootURL: rootURL.appendingPathComponent("Journals"))
    private lazy var history = ProjectHistoryStore(rootURL: rootURL.appendingPathComponent("History"))
    private lazy var cache = ProjectCacheStore(rootURL: rootURL.appendingPathComponent("Cache"))

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Project Reliability"
        AEMotionTheme.apply(to: self)
        reportView.isEditable = false
        reportView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        reportView.heightAnchor.constraint(equalToConstant: 310).isActive = true
        reportView.text = "Project schema v\(ProjectSchema.currentVersion)\nWrite-ahead autosave, recovery snapshots, managed cache, and Project Doctor are ready."

        let mode = UISegmentedControl(items: ["Battery", "Balanced", "Quality"])
        mode.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "AEMotion.performanceMode")
        mode.addAction(UIAction { action in
            guard let control = action.sender as? UISegmentedControl else { return }
            UserDefaults.standard.set(control.selectedSegmentIndex, forKey: "AEMotion.performanceMode")
        }, for: .valueChanged)

        let create = ExtensionUI.button("Create Recovery Project", action: UIAction { [weak self] _ in self?.createProject() })
        let recovery = ExtensionUI.button("Run Crash-Recovery Self-Test", action: UIAction { [weak self] _ in self?.runRecoveryTest() })
        let doctor = ExtensionUI.secondaryButton("Run Project Doctor", action: UIAction { [weak self] _ in self?.runDoctor() })
        let importButton = ExtensionUI.secondaryButton("Import Project", action: UIAction { [weak self] _ in self?.importProject() })
        let exportButton = ExtensionUI.secondaryButton("Export Latest Project", action: UIAction { [weak self] action in self?.exportLatest(source: action.sender as? UIView) })
        let clearCache = ExtensionUI.secondaryButton("Clear Managed Cache", action: UIAction { [weak self] _ in self?.clearManagedCache() })
        let share = ExtensionUI.secondaryButton("Share Report", action: UIAction { [weak self] action in
            guard let self, !self.report.isEmpty else { return }
            ExtensionUI.share(text: self.report, from: self, source: action.sender as? UIView)
        })

        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Host-safe Studio Core foundation. It manages AE Motion project packages and never writes to Alight Motion's private project database."),
            ExtensionUI.label("Performance Mode"), mode,
            create, recovery,
            ExtensionUI.horizontalStack([doctor, clearCache]),
            ExtensionUI.horizontalStack([importButton, exportButton]),
            share, status, reportView,
        ]), in: self)
    }

    private func createProject() {
        status.text = "Creating project…"
        Task {
            do {
                let session = ProjectSession(store: store, journal: journal, history: history)
                var project = ProjectDocument.empty(name: "AE Motion Recovery Project")
                project.sequences = [.init(name: "Main", duration: 10)]
                try await session.create(project)
                _ = try await session.perform(.setMetadata(key: "createdBy", value: "AE motion v2.1"), label: "Set provenance")
                latestProjectID = project.id
                try await refreshReport(prefix: "Created project \(project.id.uuidString).")
            } catch { show(error) }
        }
    }

    private func runRecoveryTest() {
        status.text = "Simulating committed change before snapshot…"
        Task {
            do {
                let testRoot = rootURL.appendingPathComponent("SelfTest-\(UUID().uuidString)")
                let passed = try await ProjectRecoverySelfTest.run(in: testRoot)
                report = "Crash-recovery self-test: \(passed ? "PASS" : "FAIL")\nRoot: \(testRoot.path)"
                reportView.text = report; status.text = passed ? "Recovery self-test passed." : "Recovery self-test failed."
            } catch { show(error) }
        }
    }

    private func runDoctor() {
        Task {
            do {
                let projects = try await store.listProjects()
                guard let project = projects.first else { throw ProjectStoreError.projectNotFound(UUID()) }
                let summary = try await cache.summary()
                let doctor = ProjectDoctor.inspect(project, cacheRoot: rootURL.appendingPathComponent("Cache"), cacheBudgetBytes: summary.budgetBytes)
                report = (["Project Doctor", "Project: \(project.name)", "Findings: \(doctor.findings.count)"] + doctor.findings.map { "[\($0.severity.rawValue.uppercased())] \($0.message)" }).joined(separator: "\n")
                reportView.text = report; status.text = doctor.findings.isEmpty ? "No project issues found." : "Project Doctor found \(doctor.findings.count) issue(s)."
            } catch { show(error) }
        }
    }

    private func clearManagedCache() {
        Task { do { try await cache.clear(); try await refreshReport(prefix: "Managed cache cleared.") } catch { show(error) } }
    }

    private func importProject() {
        let type = UTType(filenameExtension: ProjectSchema.fileExtension) ?? .json
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [type, .json], asCopy: true)
        picker.delegate = self; present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task { do { let project = try await store.importDocument(Data(contentsOf: url)); latestProjectID = project.id; try await refreshReport(prefix: "Imported \(project.name).") } catch { show(error) } }
    }

    private func exportLatest(source: UIView?) {
        Task {
            do {
                let id: UUID?
                if let latestProjectID {
                    id = latestProjectID
                } else {
                    id = try await store.listProjects().first?.id
                }
                guard let id else { throw ProjectStoreError.projectNotFound(UUID()) }
                let data = try await store.exportDocument(id)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("AE-Motion-\(id.uuidString).\(ProjectSchema.fileExtension)")
                try data.write(to: url, options: .atomic)
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activity.popoverPresentationController?.sourceView = source ?? view
                present(activity, animated: true)
            } catch { show(error) }
        }
    }

    private func refreshReport(prefix: String) async throws {
        let projects = try await store.listProjects(); let cacheSummary = try await cache.summary()
        report = [prefix, "Projects: \(projects.count)", "Cache entries: \(cacheSummary.entryCount)", "Cache bytes: \(cacheSummary.totalBytes)", "Schema: \(ProjectSchema.currentVersion)"].joined(separator: "\n")
        reportView.text = report; status.text = prefix
    }

    private func show(_ error: Error) {
        report = "ERROR: \(error.localizedDescription)"; reportView.text = report; status.text = "Operation failed."
    }
}
#endif
