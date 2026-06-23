import SwiftUI

#if canImport(UIKit)
import AVFoundation
import AVKit
import UIKit
#endif

#if canImport(UIKit)
/// Plays a bundled MP4 (e.g. splash / onboarding animations).
struct MeshBundleVideoPlayer: UIViewControllerRepresentable {
    let resourceName: String
    let fileExtension: String
    var loops: Bool = false
    /// When set, `onFadeOutStart` fires this many seconds before the video ends.
    var fadeOutLeadTime: TimeInterval? = nil
    /// Delays `onReady` until playback has advanced (avoids a static first frame during fade-in).
    var readyWhenPlaybackAdvances: Bool = false
    let onReady: () -> Void
    var onFadeOutStart: (() -> Void)? = nil
    var onFinished: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            loops: loops,
            fadeOutLeadTime: fadeOutLeadTime,
            readyWhenPlaybackAdvances: readyWhenPlaybackAdvances,
            onReady: onReady,
            onFadeOutStart: onFadeOutStart,
            onFinished: onFinished
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        context.coordinator.configure(controller: controller, resourceName: resourceName, fileExtension: fileExtension)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        private let loops: Bool
        private let fadeOutLeadTime: TimeInterval?
        private let readyWhenPlaybackAdvances: Bool
        private let onReady: () -> Void
        private let onFadeOutStart: (() -> Void)?
        private let onFinished: (() -> Void)?
        private weak var controller: AVPlayerViewController?
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var endObserver: NSObjectProtocol?
        private var statusObserver: NSKeyValueObservation?
        private var timeObserver: Any?
        private var playbackAdvanceObserver: Any?
        private var didSignalReady = false
        private var didSignalFadeOut = false

        private let playbackAdvanceThreshold: TimeInterval = 0.05

        init(
            loops: Bool,
            fadeOutLeadTime: TimeInterval?,
            readyWhenPlaybackAdvances: Bool,
            onReady: @escaping () -> Void,
            onFadeOutStart: (() -> Void)?,
            onFinished: (() -> Void)?
        ) {
            self.loops = loops
            self.fadeOutLeadTime = fadeOutLeadTime
            self.readyWhenPlaybackAdvances = readyWhenPlaybackAdvances
            self.onReady = onReady
            self.onFadeOutStart = onFadeOutStart
            self.onFinished = onFinished
        }

        func configure(controller: AVPlayerViewController, resourceName: String, fileExtension: String) {
            self.controller = controller

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
                print("[MeshVideo] \(resourceName).\(fileExtension) not found in bundle")
                signalReady()
                onFinished?()
                return
            }

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = loops ? .none : .pause
            controller.player = player
            self.player = player
            self.playerItem = item

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.loops {
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        player.play()
                    }
                } else {
                    self.onFinished?()
                }
            }

            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        self.installFadeOutObserverIfNeeded()
                        self.beginPlayback(player: player)
                    }
                case .failed:
                    print("[MeshVideo] playback failed: \(item.error?.localizedDescription ?? "unknown")")
                    self.signalReady()
                    self.onFinished?()
                default:
                    break
                }
            }
        }

        private func beginPlayback(player: AVPlayer) {
            if readyWhenPlaybackAdvances {
                installPlaybackAdvanceObserver(player: player)
            } else {
                signalReady()
            }
            player.play()
        }

        private func installPlaybackAdvanceObserver(player: AVPlayer) {
            guard playbackAdvanceObserver == nil else { return }

            let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
            playbackAdvanceObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self, !self.didSignalReady else { return }
                guard player.rate > 0, time.seconds >= self.playbackAdvanceThreshold else { return }
                self.removePlaybackAdvanceObserver(player: player)
                self.signalReady()
            }
        }

        private func removePlaybackAdvanceObserver(player: AVPlayer) {
            if let playbackAdvanceObserver {
                player.removeTimeObserver(playbackAdvanceObserver)
            }
            playbackAdvanceObserver = nil
        }

        private func signalReady() {
            guard !didSignalReady else { return }
            didSignalReady = true
            onReady()
        }

        private func installFadeOutObserverIfNeeded() {
            guard !loops,
                  let fadeOutLeadTime,
                  fadeOutLeadTime > 0,
                  onFadeOutStart != nil,
                  let player,
                  timeObserver == nil else { return }

            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.checkFadeOutStart(at: time)
            }
        }

        private func checkFadeOutStart(at time: CMTime) {
            guard !didSignalFadeOut,
                  let fadeOutLeadTime,
                  let item = playerItem else { return }

            let current = time.seconds
            let total = item.duration.seconds
            guard current.isFinite, total.isFinite, total > 0 else { return }

            if total - current <= fadeOutLeadTime {
                didSignalFadeOut = true
                onFadeOutStart?()
            }
        }

        func teardown() {
            statusObserver?.invalidate()
            statusObserver = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            if let player {
                if let timeObserver {
                    player.removeTimeObserver(timeObserver)
                }
                removePlaybackAdvanceObserver(player: player)
            }
            timeObserver = nil
            player?.pause()
            player = nil
            playerItem = nil
            controller = nil
        }
    }
}
#endif
