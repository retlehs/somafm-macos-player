import Cocoa

// MARK: - Image Loading Helper

extension NSImageView {
    func loadImage(from urlString: String?) {
        showPlaceholder()

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            if let image = await ImageCache.shared.loadImage(from: urlString) {
                self.image = image
                self.wantsLayer = false
            } else {
                self.showPlaceholder()
            }
        }
    }

    private func showPlaceholder() {
        self.image = nil
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.3).cgColor
        self.layer?.cornerRadius = 4
    }
}

// MARK: - Highlighting Menu Item View

class HighlightingMenuItemView: NSView {
    var onSelect: (() -> Void)?
    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        updateTextColors()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        updateTextColors()
        needsDisplay = true
    }

    private func updateTextColors() {
        for subview in subviews {
            guard let textField = subview as? NSTextField else { continue }
            if isHighlighted {
                textField.textColor = .white
            } else if textField.tag == 1 {
                textField.textColor = .secondaryLabelColor
            } else {
                textField.textColor = .labelColor
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }
}
