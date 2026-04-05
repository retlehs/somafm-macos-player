import Cocoa
import Combine

// MARK: - Layout Constants
private enum Layout {
    static let nowPlayingWidth: CGFloat = 280
    static let nowPlayingHeight: CGFloat = 50
    static let albumArtSize: CGFloat = 40
    static let stationArtSize: CGFloat = 30
    static let stationViewWidth: CGFloat = 350
    static let stationViewHeight: CGFloat = 50
    static let padding: CGFloat = 10
    static let textFieldWidth: CGFloat = 160
    static let cornerRadius: CGFloat = 4
}

// MARK: - StatusBarController

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let viewModel: StatusBarViewModel
    private let settings = Settings.shared

    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // Cached UI elements for direct updates
    private var currentSongMenuItem: NSMenuItem?
    private var nowPlayingTitleLabel: NSTextField?
    private var nowPlayingStationLabel: NSTextField?
    private var nowPlayingArtworkView: NSImageView?
    private var playButton: NSButton?
    private var stopButton: NSButton?

    // Track station checkmarks for updating
    private var stationCheckmarks: [String: NSTextField] = [:]

    init(viewModel: StatusBarViewModel) {
        self.viewModel = viewModel
        super.init()
        setupStatusItem()
        setupBindings()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "S"
            button.toolTip = "SomaFM Player"
        }
        buildMenu()
    }

    private func setupBindings() {
        // Rebuild menu when channels load or change
        viewModel.$channels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)

        // Observe current song changes
        viewModel.$currentSong
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingView()
            }
            .store(in: &cancellables)

        // Observe current channel changes
        viewModel.$currentChannel
            .receive(on: DispatchQueue.main)
            .removeDuplicates() // Only trigger when channel actually changes
            .sink { [weak self] channel in
                self?.updateNowPlayingView()
                self?.updateStationCheckmarks()
                // Update artwork only when channel changes
                if let artworkView = self?.nowPlayingArtworkView,
                   let current = channel {
                    artworkView.loadImage(from: current.image)
                }
            }
            .store(in: &cancellables)

        // Observe playing state changes
        viewModel.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingView()
            }
            .store(in: &cancellables)

        // Error handling
        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.showError(title: "Failed to Load Stations",
                                message: "Unable to connect to SomaFM. Please check your internet connection.\n\nDetails: \(error)")
            }
            .store(in: &cancellables)
    }

    // Remove loadChannels - handled by view model automatically

    // MARK: - Error Handling

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Retry")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // Retry button clicked
            viewModel.retryLoading()
        }
    }

    func buildMenu() {
        // Clear cached references when rebuilding
        nowPlayingTitleLabel = nil
        nowPlayingStationLabel = nil
        nowPlayingArtworkView = nil
        playButton = nil
        stopButton = nil
        currentSongMenuItem = nil
        stationCheckmarks.removeAll()

        // Force complete menu refresh
        statusItem.menu = nil
        let menu = NSMenu()

        // Now Playing widget (macOS style)
        if let current = viewModel.currentChannel {
            let nowPlayingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

            // Create the now playing view
            let nowPlayingView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.nowPlayingWidth, height: Layout.nowPlayingHeight))

            // Clear any existing subviews to prevent stacking
            nowPlayingView.subviews.forEach { $0.removeFromSuperview() }

            // Album art
            let artImageView = NSImageView(frame: NSRect(x: Layout.padding, y: 5, width: Layout.albumArtSize, height: Layout.albumArtSize))
            artImageView.imageScaling = .scaleProportionallyUpOrDown
            artImageView.wantsLayer = true
            artImageView.layer?.cornerRadius = Layout.cornerRadius
            artImageView.layer?.masksToBounds = true
            artImageView.loadImage(from: current.largeimage ?? current.image)
            self.nowPlayingArtworkView = artImageView // Cache reference for updates

            // Song title (display)
            let titleLabel = NSTextField(frame: NSRect(x: 60, y: 25, width: Layout.textFieldWidth, height: 17))
            titleLabel.stringValue = viewModel.currentSong ?? "SomaFM"
            titleLabel.isEditable = false
            titleLabel.isBordered = false
            titleLabel.backgroundColor = .clear
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.toolTip = "Click to search for this song"
            self.nowPlayingTitleLabel = titleLabel // Cache reference for updates

            // Invisible button overlay for song title clicks
            let titleClickButton = NSButton(frame: NSRect(x: 60, y: 25, width: Layout.textFieldWidth, height: 17))
            titleClickButton.title = ""
            titleClickButton.isBordered = false
            titleClickButton.isTransparent = true
            titleClickButton.target = self
            titleClickButton.action = #selector(searchForSong)

            // Station subtitle (display) - ALWAYS "SomaFM – Station"
            let stationLabel = NSTextField(frame: NSRect(x: 60, y: 8, width: Layout.textFieldWidth, height: 15))
            stationLabel.stringValue = "SomaFM – \(current.title)"
            stationLabel.isEditable = false
            stationLabel.isBordered = false
            stationLabel.backgroundColor = .clear
            stationLabel.font = NSFont.systemFont(ofSize: 11)
            stationLabel.textColor = .secondaryLabelColor
            stationLabel.lineBreakMode = .byTruncatingTail
            self.nowPlayingStationLabel = stationLabel // Cache reference for updates

            // Play button - use alpha to show disabled state more clearly
            let playBtn = NSButton(frame: NSRect(x: 225, y: 15, width: 20, height: 20))
            playBtn.bezelStyle = .regularSquare
            playBtn.isBordered = false
            playBtn.title = "▶"
            playBtn.target = self
            playBtn.action = #selector(resumePlayback)
            playBtn.font = NSFont.systemFont(ofSize: 14)
            if viewModel.isPlaying {
                playBtn.isEnabled = false
                playBtn.alphaValue = 0.3
            } else {
                playBtn.isEnabled = true
                playBtn.alphaValue = 1.0
            }
            self.playButton = playBtn

            // Stop button - use alpha to show disabled state more clearly
            let stopBtn = NSButton(frame: NSRect(x: 250, y: 15, width: 20, height: 20))
            stopBtn.bezelStyle = .regularSquare
            stopBtn.isBordered = false
            stopBtn.title = "⏹"
            stopBtn.target = self
            stopBtn.action = #selector(stopPlayback)
            stopBtn.font = NSFont.systemFont(ofSize: 14)
            if viewModel.isPlaying {
                stopBtn.isEnabled = true
                stopBtn.alphaValue = 1.0
            } else {
                stopBtn.isEnabled = false
                stopBtn.alphaValue = 0.3
            }
            self.stopButton = stopBtn

            nowPlayingView.addSubview(artImageView)
            nowPlayingView.addSubview(titleLabel)
            nowPlayingView.addSubview(stationLabel)
            nowPlayingView.addSubview(titleClickButton)  // Add invisible button on top for song search
            nowPlayingView.addSubview(playBtn)
            nowPlayingView.addSubview(stopBtn)

            // Store references for updates
            currentSongMenuItem = nowPlayingItem

            nowPlayingItem.view = nowPlayingView
            menu.addItem(nowPlayingItem)
        } else {
            menu.addItem(NSMenuItem(title: "SomaFM Player", action: nil, keyEquivalent: ""))
            if viewModel.channels.isEmpty {
                if viewModel.isLoading {
                    menu.addItem(NSMenuItem(title: "Loading stations...", action: nil, keyEquivalent: ""))
                } else {
                    menu.addItem(NSMenuItem(title: "No stations loaded", action: nil, keyEquivalent: ""))
                }
            } else {
                menu.addItem(NSMenuItem(title: "No station playing", action: nil, keyEquivalent: ""))
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Volume slider
        menu.addItem(createVolumeMenuItem())

        menu.addItem(NSMenuItem.separator())

        // Stations submenu
        menu.addItem(createStationsSubmenu())

        // Preferences submenu
        menu.addItem(createPreferencesSubmenu())

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.menu?.delegate = self
    }

    private func createStationsSubmenu() -> NSMenuItem {
        let stationsMenu = NSMenu()
        let stationsItem = NSMenuItem(title: "Stations", action: nil, keyEquivalent: "")
        stationsItem.submenu = stationsMenu

        if viewModel.channels.isEmpty {
            let loadingText = viewModel.isLoading ? "Loading..." : "No stations available"
            stationsMenu.addItem(NSMenuItem(title: loadingText, action: nil, keyEquivalent: ""))
        } else {
            // Top 10 with rich display
            for channel in viewModel.topChannels {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                // No target or action needed - the button inside handles it

                // Create custom view with artwork and description
                let customView = createStationView(for: channel, showListeners: true)
                item.view = customView

                stationsMenu.addItem(item)
            }

            // Rest alphabetically with simpler display
            if viewModel.channels.count > 10 {
                stationsMenu.addItem(NSMenuItem.separator())

                for channel in viewModel.remainingChannelsAlphabetical {
                    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                    // No target or action needed - the button inside handles it

                    // Create custom view with artwork and description (no listener count)
                    let customView = createStationView(for: channel, showListeners: false)
                    item.view = customView

                    stationsMenu.addItem(item)
                }
            }
        }

        return stationsItem
    }

    private func createStationView(for channel: Channel, showListeners: Bool) -> NSView {
        let view = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: Layout.stationViewWidth, height: Layout.stationViewHeight))
        view.onSelect = { [weak self] in
            self?.playChannel(channel)
        }

        // Station artwork
        let artworkView = NSImageView(frame: NSRect(x: Layout.padding, y: Layout.padding, width: Layout.stationArtSize, height: Layout.stationArtSize))
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = Layout.cornerRadius
        artworkView.layer?.masksToBounds = true
        artworkView.loadImage(from: channel.image)

        // Station title (with optional listener count) - moved down slightly
        let titleString = showListeners ? "\(channel.title) (\(channel.listeners) listeners)" : channel.title
        let titleLabel = NSTextField(frame: NSRect(x: 50, y: 25, width: 290, height: 16))
        titleLabel.stringValue = titleString
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        // Station description - moved up slightly for tighter spacing
        let descLabel = NSTextField(frame: NSRect(x: 50, y: 10, width: 290, height: 14))
        descLabel.stringValue = channel.description
        descLabel.isEditable = false
        descLabel.isBordered = false
        descLabel.backgroundColor = .clear
        descLabel.font = NSFont.systemFont(ofSize: 10)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.tag = 1

        // Add checkmark (always create it, but hide if not current)
        let checkmark = NSTextField(frame: NSRect(x: 330, y: 18, width: 15, height: 15))
        checkmark.stringValue = "✓"
        checkmark.isEditable = false
        checkmark.isBordered = false
        checkmark.backgroundColor = .clear
        checkmark.font = NSFont.systemFont(ofSize: 12)
        checkmark.textColor = .systemBlue

        // Show/hide based on whether this is the current station
        let isCurrentStation = viewModel.currentChannel?.id == channel.id
        checkmark.isHidden = !isCurrentStation

        // Store reference for updating later
        stationCheckmarks[channel.id] = checkmark

        view.addSubview(checkmark)
        view.addSubview(artworkView)
        view.addSubview(titleLabel)
        view.addSubview(descLabel)

        return view
    }

    private func createVolumeMenuItem() -> NSMenuItem {
        let volumeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        // Create a custom view matching the Now Playing width
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.nowPlayingWidth, height: 26))

        // Create the slider - full width with padding, better vertical centering
        let slider = NSSlider(frame: NSRect(x: 10, y: 5, width: 260, height: 16))
        slider.minValue = 0.0
        slider.maxValue = 1.0
        slider.floatValue = viewModel.volume
        slider.target = self
        slider.action = #selector(volumeSliderChanged(_:))
        slider.isContinuous = true

        sliderView.addSubview(slider)
        volumeItem.view = sliderView

        return volumeItem
    }

    private func createPreferencesSubmenu() -> NSMenuItem {
        let prefsMenu = NSMenu()
        let prefsItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefsItem.submenu = prefsMenu

        let autoPlayItem = NSMenuItem(title: "Auto-play on Launch", action: #selector(toggleAutoPlay), keyEquivalent: "")
        autoPlayItem.target = self
        autoPlayItem.state = settings.autoPlayOnLaunch ? .on : .off
        prefsMenu.addItem(autoPlayItem)

        return prefsItem
    }

    // MARK: - Actions

    @objc private func playStation(_ sender: NSMenuItem) {
        guard let channel = sender.representedObject as? Channel else { return }
        playChannel(channel)
    }

    private func playChannel(_ channel: Channel) {
        viewModel.play(channel: channel)

        // Close the menu after a short delay to allow the click to register
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu?.cancelTracking()
        }
    }

    @objc private func resumePlayback() {
        viewModel.resume()
    }

    @objc private func stopPlayback() {
        viewModel.stop()
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        viewModel.setVolume(sender.floatValue)
    }

    @objc private func toggleAutoPlay() {
        viewModel.toggleAutoPlay()
        buildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func searchForSong() {
        guard let song = viewModel.currentSong else { return }

        // URL encode the song string
        let searchQuery = song.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song

        // Create Google search URL
        if let url = URL(string: "https://www.google.com/search?q=\(searchQuery)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func searchForArtist() {
        guard let artist = viewModel.currentArtist else { return }

        // URL encode the artist string
        let searchQuery = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? artist

        // Create Google search URL
        if let url = URL(string: "https://www.google.com/search?q=\(searchQuery)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - UI Updates (handled by view model via Combine)

    private func updateNowPlayingView() {
        // Update all now playing elements efficiently
        if let titleLabel = nowPlayingTitleLabel {
            titleLabel.stringValue = viewModel.currentSong ?? "SomaFM"
        }

        if let stationLabel = nowPlayingStationLabel,
           let current = viewModel.currentChannel {
            stationLabel.stringValue = "SomaFM – \(current.title)"
        }

        // Update button states
        playButton?.isEnabled = !viewModel.isPlaying
        playButton?.alphaValue = viewModel.isPlaying ? 0.3 : 1.0

        stopButton?.isEnabled = viewModel.isPlaying
        stopButton?.alphaValue = viewModel.isPlaying ? 1.0 : 0.3
    }

    private func updateStationCheckmarks() {
        // Hide all checkmarks
        for checkmark in stationCheckmarks.values {
            checkmark.isHidden = true
        }

        // Show checkmark for current station
        if let currentChannel = viewModel.currentChannel,
           let checkmark = stationCheckmarks[currentChannel.id] {
            checkmark.isHidden = false
        }
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController {
    func menuWillOpen(_ menu: NSMenu) {
        // Just update the dynamic elements
        updateNowPlayingView()
        updateStationCheckmarks()
    }
}
