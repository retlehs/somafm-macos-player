import Foundation
import AVFoundation
import MediaPlayer

// MARK: - AudioPlayer Delegate

@MainActor
protocol AudioPlayerDelegate: AnyObject {
    func audioPlayerStateChanged(_ player: AudioPlayerProtocol)
    func audioPlayerSongChanged(_ player: AudioPlayerProtocol)
    func audioPlayerVolumeChanged(_ player: AudioPlayerProtocol)
}

// MARK: - AudioPlayer Protocol

@MainActor
protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentChannel: Channel? { get }
    var currentSong: String? { get set }
    var currentArtist: String? { get set }
    var volume: Float { get set }
    var delegate: AudioPlayerDelegate? { get set }

    func play(channel: Channel)
    func pause()
    func resume()
    func stop()
}

// MARK: - AudioPlayer Implementation

@MainActor
final class AudioPlayer: NSObject, AudioPlayerProtocol {
    private var player: AVPlayer?
    private(set) var currentChannel: Channel?
    private(set) var isPlaying: Bool = false {
        didSet {
            if oldValue != isPlaying {
                delegate?.audioPlayerStateChanged(self)
            }
        }
    }
    private let settings = Settings.shared

    weak var delegate: AudioPlayerDelegate?

    // KVO Observations
    private var statusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?

    // Retry tracking
    private var retryCount = 0
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 8.0
    private var retryTask: Task<Void, Never>?

    var currentSong: String? {
        didSet {
            if oldValue != currentSong {
                delegate?.audioPlayerSongChanged(self)
            }
        }
    }
    var currentArtist: String? {
        didSet {
            if oldValue != currentArtist {
                delegate?.audioPlayerSongChanged(self)
            }
        }
    }
    var volume: Float {
        didSet {
            player?.volume = volume
            if oldValue != volume {
                delegate?.audioPlayerVolumeChanged(self)
            }
        }
    }

    override init() {
        self.volume = settings.volume
        super.init()
        setupRemoteCommandCenter()
        setupNotifications()
        setupAudioRouteNotifications()
    }

    func play(channel: Channel) {
        // Find highest quality playlist
        let playlist = channel.playlists.first { $0.quality == "highest" }
            ?? channel.playlists.first

        guard let playlist = playlist,
              let url = URL(string: playlist.url) else {
            // No valid playlist URL for channel
            return
        }

        // Playing channel

        // Stop current playback and remove observers
        cleanupPlayer()

        // Reset retry count when playing a new channel
        if channel.id != currentChannel?.id {
            retryCount = 0
        }

        // Create new player
        player = AVPlayer(url: url)
        player?.volume = volume

        // Setup block-based KVO observers
        setupPlayerObservations()

        player?.play()

        currentChannel = channel
        delegate?.audioPlayerStateChanged(self)

        // Parse artist and song from the format "Artist - Song Title"
        if let lastPlaying = channel.lastPlaying {
            let parts = lastPlaying.split(separator: " - ", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                currentArtist = parts[0]
                currentSong = lastPlaying  // Keep full string for display
            } else {
                currentArtist = nil
                currentSong = lastPlaying
            }
        } else {
            currentArtist = nil
            currentSong = nil
        }

        isPlaying = true

        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        cleanupPlayer()
        // Keep currentChannel so we can resume
        currentSong = nil
        isPlaying = false
        retryCount = 0  // Reset retry count when stopping

        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func cleanupPlayer() {
        // Clean up KVO observations
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil

        player?.pause()
        player = nil
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if player != nil {
            resume()
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        if let channel = currentChannel {
            var nowPlayingInfo = [String: Any]()
            nowPlayingInfo[MPMediaItemPropertyTitle] = currentSong ?? "SomaFM"
            nowPlayingInfo[MPMediaItemPropertyArtist] = channel.title
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = channel.description
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true

            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        // Listen for player item failures
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )

        // Listen for player stalls
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
    }

    @objc private func playerItemFailedToPlay(notification: Notification) {
        // Player item failed to play
        // Could retry or notify user here
    }

    @objc private func playerItemStalled(notification: Notification) {
        // Playback stalled, attempting to resume...
        player?.play()
    }

    // MARK: - Audio Route Changes (macOS)

    private func setupAudioRouteNotifications() {
        // macOS doesn't use AVAudioSession, but we can monitor device changes
        // through system notifications and AVPlayer's error handling

        // Listen for audio device changes via Core Audio
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemAudioDeviceChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )

        // Player status monitoring is handled via block-based KVO in setupPlayerObservations()
    }

    @objc private func handleSystemAudioDeviceChange(notification: Notification) {
        // Audio configuration changed (device added/removed, sample rate changed)
        // System audio configuration changed

        // If we were playing and the player failed, restart
        if isPlaying, currentChannel != nil {
            // Check if player is in failed state
            if player?.status == .failed {
                // Player failed after audio change, use the retry mechanism
                handlePlayerFailure()
            }
        }
    }

    // MARK: - Player Observations

    private func setupPlayerObservations() {
        guard let player = player else { return }

        statusObservation = player.observe(\.status, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.handlePlayerStatusChange()
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleTimeControlStatusChange()
            }
        }
    }

    private func handlePlayerStatusChange() {
        guard let player = player else { return }

        switch player.status {
        case .readyToPlay:
            // Player ready to play - reset retry count on success
            retryCount = 0
        case .failed:
            // Player failed
            handlePlayerFailure()
        case .unknown:
            // Player status unknown
            break
        @unknown default:
            break
        }
    }

    private func handleTimeControlStatusChange() {
        guard let player = player else { return }

        switch player.timeControlStatus {
        case .paused:
            // Player paused
            break
        case .waitingToPlayAtSpecifiedRate:
            // Player buffering...
            break
        case .playing:
            // Player playing
            break
        @unknown default:
            break
        }
    }

    private func handlePlayerFailure() {
        // Attempt recovery if we should be playing and haven't exceeded retry limit
        guard isPlaying, let channel = currentChannel else { return }

        if retryCount >= maxRetries {
            // Max retries reached, give up
            // Failed to play channel after max attempts
            stop()

            // Notify delegate about the failure (could show error to user)
            // For now, just stop trying
            return
        }

        retryCount += 1

        // Calculate exponential backoff with jitter
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(retryCount - 1))
        let cappedDelay = min(exponentialDelay, maxRetryDelay)
        let jitter = Double.random(in: -0.1...0.1) // ±10% jitter
        let finalDelay = cappedDelay * (1.0 + jitter)

        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(finalDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.isPlaying && self.currentChannel?.id == channel.id {
                self.play(channel: channel)
            }
        }
    }

    deinit {
        retryTask?.cancel()
        statusObservation?.invalidate()
        timeControlStatusObservation?.invalidate()
        player?.pause()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Disable unused commands
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false

        // Enable play/pause
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }
}
