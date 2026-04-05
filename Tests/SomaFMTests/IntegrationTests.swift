import Testing
import Foundation
@testable import SomaFM

extension Tag {
    @Tag static var integration: Self
}

@Suite(.serialized, .tags(.integration))
struct SomaFMIntegrationTests {
    private let service = SomaFMService()

    // MARK: - Live API Tests

    @Test("Fetch channels from real API")
    func fetchChannelsFromRealAPI() async throws {
        let channels = try await service.fetchChannels()

        #expect(!channels.isEmpty)

        let grooveSalad = try #require(channels.first { $0.id == "groovesalad" }, "Groove Salad should exist")
        #expect(!grooveSalad.title.isEmpty)
        #expect(!grooveSalad.description.isEmpty)
        #expect(grooveSalad.listeners > 0)
        #expect(!grooveSalad.playlists.isEmpty)

        for playlist in grooveSalad.playlists {
            #expect(URL(string: playlist.url) != nil)
            #expect(!playlist.format.isEmpty)
            #expect(!playlist.quality.isEmpty)
        }

        #expect(channels.contains { $0.id == "defcon" }, "DEF CON Radio should exist")
    }

    @Test("Channels sortable by popularity")
    func channelsSortedByPopularity() async throws {
        let channels = try await service.fetchChannels()
        let sorted = channels.sorted { $0.listeners > $1.listeners }
        let top5 = Array(sorted.prefix(5))

        for index in 0..<(top5.count - 1) {
            #expect(top5[index].listeners >= top5[index + 1].listeners)
        }

        let mostPopular = try #require(top5.first)
        #expect(mostPopular.listeners > 10)
    }

    @Test("Fetch current song for popular channel")
    func fetchCurrentSongForPopularChannel() async throws {
        let channels = try await service.fetchChannels()
        let channel = try #require(channels.max { $0.listeners < $1.listeners })

        let song = try await service.fetchCurrentSong(for: channel.id)

        if let song {
            #expect(!song.isEmpty, "Song title should not be empty")
        }
        // song can be nil during station breaks, so we don't require it
    }

    @Test("All channels have valid stream URLs")
    func allChannelsHaveValidStreamURLs() async throws {
        let channels = try await service.fetchChannels()

        for channel in channels {
            #expect(!channel.playlists.isEmpty, "Channel '\(channel.title)' should have playlists")

            let playlist = try #require(
                channel.playlists.first { $0.quality == "highest" } ?? channel.playlists.first,
                "Channel '\(channel.title)' should have at least one playlist"
            )

            let url = try #require(URL(string: playlist.url), "Channel '\(channel.title)' playlist URL should be valid")
            #expect(
                url.absoluteString.hasPrefix("https://") || url.absoluteString.hasPrefix("http://"),
                "URL should be HTTP(S)"
            )
        }
    }

    @Test("Known genres present", arguments: ["electronic", "ambient", "rock", "alternative", "eclectic"])
    func knownGenre(genre: String) async throws {
        let channels = try await service.fetchChannels()
        let genres = Set(channels.map { $0.genre })
        #expect(genres.contains { $0.lowercased().contains(genre) }, "Should have at least one \(genre) channel")
    }

    // MARK: - Error Handling Tests

    @Test("Invalid base URL throws error")
    func invalidBaseURL() async {
        let badService = SomaFMService(baseURL: "https://invalid.somafm.com")
        await #expect(throws: (any Error).self) {
            try await badService.fetchChannels()
        }
    }
}
