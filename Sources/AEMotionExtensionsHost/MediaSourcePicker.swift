#if canImport(UIKit) && canImport(PhotosUI) && canImport(UniformTypeIdentifiers)
import UIKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class MediaSourcePicker: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    enum PickerError: Error, LocalizedError {
        case noSelection
        case unsupportedItem
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSelection: return "No video was selected."
            case .unsupportedItem: return "The selected item is not a supported video."
            case .copyFailed(let message): return message
            }
        }
    }

    private weak var presenter: UIViewController?
    private let completion: (Result<URL, Error>) -> Void

    init(presenter: UIViewController, completion: @escaping (Result<URL, Error>) -> Void) {
        self.presenter = presenter
        self.completion = completion
    }

    func presentPhotos() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    func presentFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            completion(.failure(PickerError.noSelection))
            return
        }
        completion(.success(url))
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            completion(.failure(PickerError.noSelection))
            return
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
            completion(.failure(PickerError.unsupportedItem))
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.completion(.failure(PickerError.copyFailed(message)))
                }
                return
            }
            guard let url else {
                Task { @MainActor [weak self] in self?.completion(.failure(PickerError.noSelection)) }
                return
            }
            do {
                let copied = try Self.copyToTemporary(url)
                Task { @MainActor [weak self] in self?.completion(.success(copied)) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.completion(.failure(PickerError.copyFailed(message)))
                }
            }
        }
    }

    nonisolated private static func copyToTemporary(_ sourceURL: URL) throws -> URL {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("AE-Motion-Import-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            throw PickerError.copyFailed("Could not copy the selected Photos video: \(error.localizedDescription)")
        }
    }
}
#endif
