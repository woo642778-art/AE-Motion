#if canImport(UIKit) && canImport(AVFoundation)
import UIKit
import AVFoundation

@MainActor
final class VideoPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor
final class VideoPreviewPanel: UIView {
    private let surface = VideoPreviewSurface()
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let player = AVPlayer()
    nonisolated(unsafe) private var periodicObserver: Any?
    private var isSeeking = false

    var currentTime: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }
    var duration: Double {
        let value = player.currentItem?.duration.seconds ?? 0
        return value.isFinite ? max(0, value) : 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.masksToBounds = true

        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.backgroundColor = .black
        surface.playerLayer.player = player
        surface.playerLayer.videoGravity = .resizeAspect

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.addAction(UIAction { [weak self] _ in self?.sliderChanged() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.beginSeeking() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.endSeeking() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textAlignment = .right
        timeLabel.text = "0:00.00 / 0:00.00"

        addSubview(surface)
        addSubview(playButton)
        addSubview(slider)
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.heightAnchor.constraint(equalTo: surface.widthAnchor, multiplier: 9.0 / 16.0),

            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            playButton.topAnchor.constraint(equalTo: surface.bottomAnchor, constant: 8),
            playButton.widthAnchor.constraint(equalToConstant: 34),
            playButton.heightAnchor.constraint(equalToConstant: 34),

            slider.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 2),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])

        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshTimeUI() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
    }

    func load(url: URL) {
        pause()
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        slider.value = 0
        refreshTimeUI()
    }

    func pause() {
        player.pause()
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    }

    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        let target = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in completion?() }
        }
    }

    private func togglePlayback() {
        if player.timeControlStatus == .playing {
            pause()
        } else {
            if duration > 0, currentTime >= duration - 0.02 { seek(to: 0) }
            player.play()
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }

    private func beginSeeking() {
        isSeeking = true
        player.pause()
    }

    private func sliderChanged() {
        guard duration > 0 else { return }
        let seconds = Double(slider.value) * duration
        timeLabel.text = "\(format(seconds)) / \(format(duration))"
        seek(to: seconds)
    }

    private func endSeeking() {
        isSeeking = false
        refreshTimeUI()
    }

    private func refreshTimeUI() {
        let total = duration
        let current = currentTime
        if !isSeeking, total > 0 {
            slider.value = Float(max(0, min(1, current / total)))
        }
        timeLabel.text = "\(format(current)) / \(format(total))"
        if player.timeControlStatus != .playing {
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00.00" }
        let value = max(0, seconds)
        let minutes = Int(value) / 60
        let remainder = value - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remainder)
    }
}
#endif
