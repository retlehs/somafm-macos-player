import Foundation
import Testing
@testable import SomaFM

struct ModelTests {
    // MARK: - Channel Decoding Tests

    @Test("Channel decodes correctly from JSON")
    func channelDecodesCorrectly() throws {
        let json = """
        {
            "id": "groovesalad",
            "title": "Groove Salad",
            "description": "A nicely chilled plate of beats and grooves.",
            "genre": "ambient",
            "listeners": "450",
            "lastPlaying": "Thievery Corporation - Lebanese Blonde",
            "playlists": [
                {
                    "url": "https://somafm.com/groovesalad.pls",
                    "format": "mp3",
                    "quality": "highest"
                }
            ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let channel = try JSONDecoder().decode(Channel.self, from: data)

        #expect(channel.id == "groovesalad")
        #expect(channel.title == "Groove Salad")
        #expect(channel.listeners == 450)
        #expect(channel.lastPlaying == "Thievery Corporation - Lebanese Blonde")
        #expect(channel.playlists.count == 1)
        #expect(channel.playlists.first?.quality == "highest")
    }

    @Test("Listener string parsing", arguments: [
        ("0", 0),
        ("invalid", 0),
        ("450", 450)
    ])
    func listenerParsing(input: String, expected: Int) throws {
        let json = """
        {
            "id": "test",
            "title": "Test",
            "description": "Test station",
            "genre": "test",
            "listeners": "\(input)",
            "playlists": []
        }
        """

        let data = try #require(json.data(using: .utf8))
        let channel = try JSONDecoder().decode(Channel.self, from: data)

        #expect(channel.listeners == expected)
    }

    @Test("Channel handles missing lastPlaying")
    func channelHandlesMissingLastPlaying() throws {
        let json = """
        {
            "id": "test",
            "title": "Test",
            "description": "Test station",
            "genre": "test",
            "listeners": "100",
            "playlists": []
        }
        """

        let data = try #require(json.data(using: .utf8))
        let channel = try JSONDecoder().decode(Channel.self, from: data)

        #expect(channel.lastPlaying == nil)
    }

    // MARK: - Playlist Tests

    @Test("Playlist decodes correctly")
    func playlistDecodesCorrectly() throws {
        let json = """
        {
            "url": "https://somafm.com/test.pls",
            "format": "mp3",
            "quality": "highest"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let playlist = try JSONDecoder().decode(Playlist.self, from: data)

        #expect(playlist.url == "https://somafm.com/test.pls")
        #expect(playlist.format == "mp3")
        #expect(playlist.quality == "highest")
    }

    // MARK: - ChannelsResponse Tests

    @Test("ChannelsResponse decodes multiple channels")
    func channelsResponseDecodesCorrectly() throws {
        let json = """
        {
            "channels": [
                {
                    "id": "test1",
                    "title": "Test 1",
                    "description": "First test",
                    "genre": "test",
                    "listeners": "100",
                    "playlists": []
                },
                {
                    "id": "test2",
                    "title": "Test 2",
                    "description": "Second test",
                    "genre": "test",
                    "listeners": "200",
                    "playlists": []
                }
            ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(ChannelsResponse.self, from: data)

        #expect(response.channels.count == 2)
        #expect(response.channels[0].id == "test1")
        #expect(response.channels[1].id == "test2")
        #expect(response.channels[0].listeners == 100)
        #expect(response.channels[1].listeners == 200)
    }

    // MARK: - Error Tests

    @Test("PlayerError descriptions", arguments: [
        (PlayerError.networkError("Connection failed"), "Network error: Connection failed"),
        (PlayerError.invalidURL, "Invalid URL"),
        (PlayerError.decodingError("Invalid JSON"), "Failed to parse data: Invalid JSON"),
        (PlayerError.noPlaylistAvailable, "No playlist available for this station")
    ])
    func errorDescription(error: PlayerError, expected: String) {
        #expect(error.localizedDescription == expected)
    }
}
