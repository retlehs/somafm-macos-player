import Foundation

// MARK: - Error Types

enum PlayerError: LocalizedError {
    case networkError(String)
    case invalidURL
    case decodingError(String)
    case noPlaylistAvailable

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .decodingError(let message):
            return "Failed to parse data: \(message)"
        case .noPlaylistAvailable:
            return "No playlist available for this station"
        }
    }
}

// MARK: - Data Models

struct Channel: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    let listeners: Int
    let genre: String
    let lastPlaying: String?
    let playlists: [Playlist]
    let largeimage: String?
    let image: String?
    let xlimage: String?

    // Custom decoding since API returns listeners as String
    enum CodingKeys: String, CodingKey {
        case id, title, description, genre, lastPlaying, playlists
        case listeners, largeimage, image, xlimage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        genre = try container.decode(String.self, forKey: .genre)
        lastPlaying = try container.decodeIfPresent(String.self, forKey: .lastPlaying)
        playlists = try container.decode([Playlist].self, forKey: .playlists)
        largeimage = try container.decodeIfPresent(String.self, forKey: .largeimage)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        xlimage = try container.decodeIfPresent(String.self, forKey: .xlimage)

        // Convert String listeners to Int
        if let listenersString = try? container.decode(String.self, forKey: .listeners),
           let listenersInt = Int(listenersString) {
            listeners = listenersInt
        } else {
            listeners = 0
        }
    }

    // For testing
    init(id: String, title: String, description: String, listeners: Int, genre: String, lastPlaying: String?, playlists: [Playlist], largeimage: String? = nil, image: String? = nil, xlimage: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.listeners = listeners
        self.genre = genre
        self.lastPlaying = lastPlaying
        self.playlists = playlists
        self.largeimage = largeimage
        self.image = image
        self.xlimage = xlimage
    }
}

struct Playlist: Codable, Equatable, Sendable {
    let url: String
    let format: String
    let quality: String
}

struct ChannelsResponse: Codable, Sendable {
    let channels: [Channel]
}
