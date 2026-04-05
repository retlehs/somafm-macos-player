import Foundation
@testable import SomaFM

@MainActor
final class MockAudioPlayer: AudioPlayerProtocol {
    var isPlaying: Bool = false
    var currentChannel: Channel?
    var currentSong: String?
    var currentArtist: String?
    var volume: Float = 0.8
    weak var delegate: AudioPlayerDelegate?

    var playCalledWith: Channel?
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false

    func play(channel: Channel) {
        playCalledWith = channel
        currentChannel = channel

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
    }

    func pause() {
        pauseCalled = true
        isPlaying = false
    }

    func resume() {
        resumeCalled = true
        isPlaying = true
    }

    func stop() {
        stopCalled = true
        isPlaying = false
        currentChannel = nil
        currentSong = nil
        currentArtist = nil
    }
}
