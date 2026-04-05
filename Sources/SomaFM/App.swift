import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var audioPlayer: AudioPlayer!
    private var somaFMService: SomaFMService!
    private var viewModel: StatusBarViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SomaFM Player launched

        // Initialize dependencies
        somaFMService = SomaFMService()
        audioPlayer = AudioPlayer()

        // Create view model with MVVM pattern
        viewModel = StatusBarViewModel(
            audioPlayer: audioPlayer,
            somaFMService: somaFMService
        )

        // Create controller that binds to view model
        statusBarController = StatusBarController(viewModel: viewModel)

        // Media keys handled by MPRemoteCommandCenter in AudioPlayer
        // No CGEventTap needed for App Store compatibility
    }
}

// MARK: - Main Entry Point

public func runApp() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    app.run()
}
