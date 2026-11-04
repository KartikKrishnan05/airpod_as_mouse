import AVFoundation
import Foundation
import MediaPlayer

/// Turns AirPods stem presses into callbacks.
///
/// AirPods don't expose raw taps to macOS. A press is delivered as a media
/// remote command to whichever app is the system "Now Playing" app:
///   single press → play / pause / toggle
///   double press → next track
///   triple press → previous track
///
/// To receive those, this app claims Now Playing status by publishing
/// now-playing info and keeping a silent audio stream running.
final class TapController {
    var onSingle: (() -> Void)?
    var onDouble: (() -> Void)?
    var onTriple: (() -> Void)?

    private let engine = AVAudioEngine()
    private var lastFire = Date.distantPast
    private var configObserver: NSObjectProtocol?

    func start() {
        startSilentAudio()
        registerCommands()
        claimNowPlaying()

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Output device changed (e.g. AirPods reconnected) — restart the stream.
            self?.restartSilentAudio()
        }
    }

    /// Re-assert Now Playing status (e.g. after Music/Spotify took it over).
    func claimNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "AirPods Mouse",
            MPMediaItemPropertyArtist: "Head tracking active",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        center.playbackState = .playing
        if !engine.isRunning { restartSilentAudio() }
    }

    // MARK: Remote commands

    private func registerCommands() {
        let c = MPRemoteCommandCenter.shared()

        for cmd in [c.togglePlayPauseCommand, c.playCommand, c.pauseCommand] {
            cmd.isEnabled = true
            cmd.addTarget { [weak self] _ in
                self?.fire(self?.onSingle)
                return .success
            }
        }
        c.nextTrackCommand.isEnabled = true
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.fire(self?.onDouble)
            return .success
        }
        c.previousTrackCommand.isEnabled = true
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.fire(self?.onTriple)
            return .success
        }
    }

    private func fire(_ action: (() -> Void)?) {
        // macOS sometimes delivers both e.g. `pause` and `togglePlayPause` for
        // one press; collapse anything arriving within 150 ms.
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.15 else { return }
        lastFire = now
        DispatchQueue.main.async {
            action?()
            // A play/pause press may have flipped our state to paused; flip it back
            // so we stay the Now Playing app.
            self.claimNowPlaying()
        }
    }

    // MARK: Silent audio

    private var sourceNode: AVAudioSourceNode?

    private func startSilentAudio() {
        let node = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
            for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            NSLog("AirPodsMouse: failed to start silent audio: \(error)")
        }
    }

    private func restartSilentAudio() {
        engine.stop()
        do {
            try engine.start()
        } catch {
            NSLog("AirPodsMouse: failed to restart silent audio: \(error)")
        }
    }
}
