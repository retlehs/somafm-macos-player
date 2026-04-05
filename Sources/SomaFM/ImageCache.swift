import Foundation
import AppKit

// MARK: - Image Cache Manager

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let urlSession: URLSession
    // Store download tasks to allow multiple views to await the same download
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var downloadResults: [String: NSImage] = [:]
    private var downloadFailures: Set<String> = []

    private init() {
        // Configure cache limits
        cache.countLimit = 100  // Max 100 images
        cache.totalCostLimit = 50 * 1_024 * 1_024  // Max 50MB

        // Configure URL session for image downloads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)

        // Clear cache on low memory (macOS doesn't have memory warning notifications like iOS)
        // We'll clear cache when app becomes inactive or on manual triggers
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Load image from cache or download if needed
    func loadImage(from urlString: String?) async -> NSImage? {
        guard let urlString = urlString,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        let cacheKey = NSString(string: urlString)

        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        // Check if already downloading - if so, await the existing task
        if let existingTask = downloadTasks[urlString] {
            await existingTask.value
            return downloadResults[urlString]
        }

        // Create new download task
        let task = Task<Void, Never> { [weak self] in
            guard let self = self else { return }

            do {
                let (data, response) = try await self.urlSession.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty else {
                    self.downloadFailures.insert(urlString)
                    return
                }

                guard let image = NSImage(data: data),
                      image.isValid else {
                    self.downloadFailures.insert(urlString)
                    return
                }

                let optimizedImage = self.optimizeImageForDisplay(image)
                let cost = self.estimateImageMemoryCost(optimizedImage)
                self.cache.setObject(optimizedImage, forKey: cacheKey, cost: cost)
                self.downloadResults[urlString] = optimizedImage
            } catch {
                self.downloadFailures.insert(urlString)
            }
        }

        downloadTasks[urlString] = task
        await task.value

        let result = downloadResults[urlString]

        // Clean up
        downloadTasks.removeValue(forKey: urlString)
        downloadResults.removeValue(forKey: urlString)
        downloadFailures.remove(urlString)

        return result
    }

    /// Preload images for better performance
    func preloadImages(_ urls: [String]) {
        Task { @MainActor in
            for url in urls.prefix(5) { // Only preload first 5
                _ = await loadImage(from: url)
            }
        }
    }

    /// Clear all cached images
    func clearCache() {
        cache.removeAllObjects()
        // Cancel all pending download tasks
        for task in downloadTasks.values {
            task.cancel()
        }
        downloadTasks.removeAll()
        downloadResults.removeAll()
        downloadFailures.removeAll()
    }

    /// Get cache statistics
    var cacheInfo: (count: Int, cost: Int) {
        // NSCache doesn't expose current cost, so we estimate
        let count = cache.name.isEmpty ? 0 : 1 // NSCache doesn't expose count either
        return (count: count, cost: 0)
    }

    // MARK: - Private Methods

    private func optimizeImageForDisplay(_ image: NSImage) -> NSImage {
        // For small images (like station artwork), limit size to prevent memory bloat
        let maxSize: CGFloat = 120 // 3x the display size of 40pt

        if image.size.width <= maxSize && image.size.height <= maxSize {
            return image
        }

        // Resize large images
        let aspectRatio = image.size.width / image.size.height
        let newSize: NSSize

        if aspectRatio > 1 {
            newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        // Use modern API instead of deprecated lockFocus/unlockFocus
        let resizedImage = NSImage(size: newSize, flipped: false) { drawingRect in
            image.draw(in: drawingRect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy,
                       fraction: 1.0)
            return true
        }

        return resizedImage
    }

    private func estimateImageMemoryCost(_ image: NSImage) -> Int {
        // Rough estimate: width * height * 4 bytes per pixel (RGBA)
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        return width * height * 4
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    var isValid: Bool {
        return size.width > 0 && size.height > 0 && !representations.isEmpty
    }
}
