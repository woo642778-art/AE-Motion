#if canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
import AEMotionExtensionsCore

@MainActor
enum ProxyGenerationError: Error, LocalizedError {
    case unsupportedPreset
    case exportSessionUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPreset: return "The requested proxy quality is unavailable on this device."
        case .exportSessionUnavailable: return "A proxy export session could not be created."
        case let .exportFailed(message): return message
        }
    }
}

@MainActor
final class ProxyGenerationService {
    private var activeExport: AVAssetExportSession?

    func generate(
        sourceURL: URL,
        destinationURL: URL,
        scale: PreviewScale,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        let preferred: String
        switch scale {
        case .full: preferred = AVAssetExportPresetHighestQuality
        case .half: preferred = AVAssetExportPreset1280x720
        case .quarter, .eighth: preferred = AVAssetExportPreset960x540
        }
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = compatible.contains(preferred) ? preferred : compatible.first(where: { $0 == AVAssetExportPresetMediumQuality })
        guard let preset else { completion(.failure(ProxyGenerationError.unsupportedPreset)); return }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(.failure(ProxyGenerationError.exportSessionUnavailable)); return
        }
        try? FileManager.default.removeItem(at: destinationURL)
        exporter.outputURL = destinationURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        activeExport = exporter
        exporter.exportAsynchronously { [weak self] in
            Task { @MainActor in
                defer { self?.activeExport = nil }
                switch exporter.status {
                case .completed: completion(.success(destinationURL))
                case .cancelled: completion(.failure(CancellationError()))
                default: completion(.failure(ProxyGenerationError.exportFailed(exporter.error?.localizedDescription ?? "Proxy export failed.")))
                }
            }
        }
    }

    func cancel() { activeExport?.cancelExport() }
}
#endif
