import Foundation

// MARK: - Protocol for testability

protocol SomaFMServiceProtocol {
    func fetchChannels() async throws -> [Channel]
    func fetchCurrentSong(for channelId: String) async throws -> String?
}

// MARK: - Implementation

final class SomaFMService: SomaFMServiceProtocol {
    private let session: URLSession
    private let baseURL: String

    // Cache for channels to avoid re-fetching (actor-isolated for thread safety)
    private actor ChannelCache {
        private var cache: (channels: [Channel], timestamp: Date)?
        private let timeout: TimeInterval = 60 // 60 seconds cache

        func get() -> [Channel]? {
            guard let cache = cache,
                  Date().timeIntervalSince(cache.timestamp) < timeout else {
                return nil
            }
            return cache.channels
        }

        func set(_ channels: [Channel]) {
            cache = (channels, Date())
        }
    }

    private let channelCache = ChannelCache()

    // Retry configuration
    private struct RetryConfig {
        static let maxRetries = 3
        static let baseDelay: TimeInterval = 1.0
        static let maxDelay: TimeInterval = 8.0
        static let jitterRange: Double = 0.1
    }

    init(session: URLSession = .shared, baseURL: String = "https://somafm.com") {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchChannels() async throws -> [Channel] {
        // Check cache first
        if let cachedChannels = await channelCache.get() {
            return cachedChannels
        }

        // Cache miss or expired, fetch with retry logic
        return try await withRetry { [weak self] in
            try await self?.fetchChannelsOnce() ?? []
        }
    }

    private func fetchChannelsOnce() async throws -> [Channel] {
        guard let url = URL(string: "\(baseURL)/channels.json") else {
            throw PlayerError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                break // Success
            case 500...599:
                throw PlayerError.networkError("Server error: \(httpResponse.statusCode)")
            case 429:
                throw PlayerError.networkError("Rate limited")
            default:
                throw PlayerError.networkError("HTTP error: \(httpResponse.statusCode)")
            }
        }

        do {
            let decoder = JSONDecoder()
            let channelsResponse = try decoder.decode(ChannelsResponse.self, from: data)

            // Update cache on success
            await channelCache.set(channelsResponse.channels)

            return channelsResponse.channels
        } catch {
            throw PlayerError.decodingError(error.localizedDescription)
        }
    }

    func fetchCurrentSong(for channelId: String) async throws -> String? {
        // Use cached channels if available, or fetch with retry
        let channels = try await fetchChannels()

        guard let channel = channels.first(where: { $0.id == channelId }) else {
            return nil
        }

        return channel.lastPlaying
    }

    // MARK: - Retry Logic

    private func withRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<RetryConfig.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry for certain error types
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't delay on the last attempt
                if attempt < RetryConfig.maxRetries - 1 {
                    let delay = calculateDelay(for: attempt)
                    // Request failed, retrying
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? PlayerError.networkError("All retry attempts failed")
    }

    private func shouldRetry(error: Error) -> Bool {
        // Don't retry for certain error types
        if let playerError = error as? PlayerError {
            switch playerError {
            case .invalidURL, .decodingError:
                return false // These won't fix themselves with retry
            case .networkError(let message):
                // Don't retry for client errors (4xx)
                if message.contains("HTTP error: 4") {
                    return false
                }
                return true
            case .noPlaylistAvailable:
                return false
            }
        }

        // Retry for URLError types (network issues)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }

        return true // Default to retry for unknown errors
    }

    private func calculateDelay(for attempt: Int) -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialDelay = RetryConfig.baseDelay * pow(2.0, Double(attempt))
        let cappedDelay = min(exponentialDelay, RetryConfig.maxDelay)

        // Add random jitter to avoid thundering herd
        let jitter = Double.random(in: -RetryConfig.jitterRange...RetryConfig.jitterRange)
        let finalDelay = cappedDelay * (1.0 + jitter)

        return max(0.1, finalDelay) // Minimum 100ms delay
    }
}

// MARK: - Mock for testing

#if DEBUG
final class MockSomaFMService: SomaFMServiceProtocol {
    var mockChannels: [Channel] = []
    var shouldThrowError = false
    var errorToThrow: Error = PlayerError.networkError("Mock error")

    func fetchChannels() async throws -> [Channel] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockChannels
    }

    func fetchCurrentSong(for channelId: String) async throws -> String? {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockChannels.first { $0.id == channelId }?.lastPlaying
    }
}
#endif
