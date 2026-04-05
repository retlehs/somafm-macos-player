import Foundation
import Combine
import AVFoundation

// MARK: - StatusBarViewModel

@MainActor
final class StatusBarViewModel: ObservableObject {
    // MARK: - Published Properties (UI State)

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var currentChannel: Channel?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentSong: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var volume: Float
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let audioPlayer: AudioPlayerProtocol
    private let somaFMService: SomaFMServiceProtocol
    private let settings = Settings.shared

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var songUpdateTimer: AnyCancellable?
    private var currentUpdateTask: Task<Void, Never>?
    private var loadChannelsTask: Task<Void, Never>?

    // MARK: - Initialization

    init(audioPlayer: AudioPlayerProtocol, somaFMService: SomaFMServiceProtocol) {
        self.audioPlayer = audioPlayer
        self.somaFMService = somaFMService
        self.volume = audioPlayer.volume

        // Set self as delegate
        audioPlayer.delegate = self

        // Initialize state from audio player
        self.isPlaying = audioPlayer.isPlaying
        self.currentChannel = audioPlayer.currentChannel
        self.currentSong = audioPlayer.currentSong
        self.currentArtist = audioPlayer.currentArtist

        loadChannels()
    }

    // MARK: - Public Methods

    func loadChannels() {
        loadChannelsTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadChannelsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedChannels = try await somaFMService.fetchChannels()
                guard !Task.isCancelled else { return }
                self.channels = fetchedChannels
                self.isLoading = false

                if settings.autoPlayOnLaunch,
                   audioPlayer.currentChannel == nil,
                   !fetchedChannels.isEmpty {
                    await autoPlay()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func play(channel: Channel) {
        audioPlayer.play(channel: channel)
        settings.lastPlayedChannelId = channel.id
        startSongUpdateTimer()
    }

    func resume() {
        if let channel = currentChannel {
            audioPlayer.play(channel: channel)
            startSongUpdateTimer()
        }
    }

    func stop() {
        audioPlayer.stop()
        stopSongUpdateTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            audioPlayer.pause()
            stopSongUpdateTimer()
        } else {
            resume()
        }
    }

    func setVolume(_ newVolume: Float) {
        audioPlayer.volume = newVolume
        settings.volume = newVolume
    }

    func toggleAutoPlay() {
        settings.autoPlayOnLaunch.toggle()
    }

    func retryLoading() {
        loadChannels()
    }

    // MARK: - Channel Helpers

    var sortedChannelsByPopularity: [Channel] {
        channels.sorted { $0.listeners > $1.listeners }
    }

    var topChannels: [Channel] {
        Array(sortedChannelsByPopularity.prefix(10))
    }

    var remainingChannelsAlphabetical: [Channel] {
        let top10 = Set(topChannels.map { $0.id })
        return channels
            .filter { !top10.contains($0.id) }
            .sorted { $0.title < $1.title }
    }

    // MARK: - Private Methods

    private func autoPlay() async {
        let sorted = sortedChannelsByPopularity

        // Try to play last played channel, or most popular
        let channelToPlay = settings.lastPlayedChannelId.flatMap { id in
            channels.first { $0.id == id }
        } ?? sorted.first

        if let channel = channelToPlay {
            // Auto-playing channel
            play(channel: channel)
        }
    }

    private func startSongUpdateTimer() {
        stopSongUpdateTimer()
        updateCurrentSong()

        // Use Combine timer instead of Timer
        songUpdateTimer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateCurrentSong()
            }
    }

    private func stopSongUpdateTimer() {
        songUpdateTimer?.cancel()
        songUpdateTimer = nil
        currentUpdateTask?.cancel()
        currentUpdateTask = nil
    }

    private func updateCurrentSong() {
        guard let channel = currentChannel else { return }

        // Cancel any existing update task
        currentUpdateTask?.cancel()

        currentUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()

                if let newSong = try await somaFMService.fetchCurrentSong(for: channel.id),
                   newSong != self.currentSong {
                    try Task.checkCancellation()

                    let parts = newSong.split(separator: " - ", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        self.audioPlayer.currentArtist = parts[0]
                        self.audioPlayer.currentSong = newSong
                    } else {
                        self.audioPlayer.currentArtist = nil
                        self.audioPlayer.currentSong = newSong
                    }
                }
            } catch is CancellationError {
                // Task was cancelled
            } catch {
                // Failed to update song
            }
        }
    }

    deinit {
        songUpdateTimer?.cancel()
        currentUpdateTask?.cancel()
        loadChannelsTask?.cancel()
        cancellables.removeAll()
    }
}

// MARK: - AudioPlayerDelegate

extension StatusBarViewModel: AudioPlayerDelegate {
    func audioPlayerStateChanged(_ player: AudioPlayerProtocol) {
        isPlaying = player.isPlaying
        currentChannel = player.currentChannel
    }

    func audioPlayerSongChanged(_ player: AudioPlayerProtocol) {
        currentSong = player.currentSong
        currentArtist = player.currentArtist
    }

    func audioPlayerVolumeChanged(_ player: AudioPlayerProtocol) {
        volume = player.volume
    }
}
