import AppKit

/// One clickable row (folder, file, or "Back"): icon, title, optional
/// chevron, rounded accent-color highlight on hover.
final class FolderRowView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()
    private var trackingArea: NSTrackingArea?

    let titleText: String
    var onClick: (() -> Void)?

    init(icon: NSImage?, title: String, showsChevron: Bool) {
        titleText = title
        super.init(frame: .zero)
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 6
        highlight.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(highlight)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        if showsChevron {
            let chevron = NSImageView()
            chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            chevron.contentTintColor = .secondaryLabelColor
            addSubview(chevron)
            self.chevron = chevron
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private var chevron: NSImageView?

    override func layout() {
        super.layout()
        highlight.frame = bounds.insetBy(dx: 4, dy: 1)
        iconView.frame = NSRect(x: 10, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let chevronWidth: CGFloat = chevron != nil ? 20 : 8
        titleLabel.frame = NSRect(x: 32, y: (bounds.height - 16) / 2, width: bounds.width - 32 - chevronWidth, height: 16)
        chevron?.frame = NSRect(x: bounds.width - 18, y: (bounds.height - 12) / 2, width: 10, height: 12)
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || titleText.lowercased().contains(query)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        highlight.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        titleLabel.textColor = .white
        chevron?.contentTintColor = .white
    }

    override func mouseExited(with event: NSEvent) {
        highlight.layer?.backgroundColor = NSColor.clear.cgColor
        titleLabel.textColor = .labelColor
        chevron?.contentTintColor = .secondaryLabelColor
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

/// Top-down document view for the scroll area (AppKit's default bottom-left
/// origin makes a "first row at the top" list awkward to reason about).
private final class TopDownView: NSView {
    override var isFlipped: Bool { true }
}

/// The glass panel itself: a tinted `NSVisualEffectView` with a search field,
/// a scrolling row list, and a persistent "Reveal in Finder" row — the real
/// implementation of the look the mockup promised, replacing the flat
/// default `NSMenu` chrome (which has no way to carry a custom tint).
final class GlassFolderView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 300
    static let maxListHeight: CGFloat = 320
    private static let searchAreaHeight: CGFloat = 38
    private static let revealHeight: CGFloat = 30

    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    private let searchField = NSSearchField()
    private let scroll = NSScrollView()
    private let content = TopDownView()
    private let revealRow = FolderRowView(icon: NSImage(systemSymbolName: "star", accessibilityDescription: nil),
                                           title: "Reveal in Finder", showsChevron: false)
    private var entryRows: [FolderRowView] = []

    var onSearch: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.95, alpha: 0.08).cgColor
        effectView.addSubview(tintView)

        searchField.placeholderString = "Filter…"
        searchField.delegate = self
        effectView.addSubview(searchField)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = content
        effectView.addSubview(scroll)

        effectView.addSubview(revealRow)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }

    func filter(_ text: String) {
        let query = text.lowercased()
        for row in entryRows { row.isHidden = !row.matches(query) }
    }

    /// Rebuilds the row list for a (possibly new) directory. Folders are
    /// expected to already be ordered ahead of files by the caller.
    func reload(
        showsBack: Bool,
        entries: [(title: String, icon: NSImage?, isDirectory: Bool, url: URL)],
        onBack: @escaping () -> Void,
        onSelect: @escaping (URL, Bool) -> Void,
        onReveal: @escaping () -> Void
    ) {
        content.subviews.forEach { $0.removeFromSuperview() }
        entryRows = []
        searchField.stringValue = ""

        var y: CGFloat = 4

        if showsBack {
            let back = FolderRowView(icon: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil),
                                      title: "Back", showsChevron: false)
            back.frame = NSRect(x: 6, y: y, width: Self.width - 12, height: 26)
            back.onClick = onBack
            content.addSubview(back)
            y += 28
        }

        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "No content")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 14, y: y + 2, width: Self.width - 28, height: 18)
            content.addSubview(empty)
            y += 24
        } else {
            for entry in entries {
                let row = FolderRowView(icon: entry.icon, title: entry.title, showsChevron: entry.isDirectory)
                row.frame = NSRect(x: 6, y: y, width: Self.width - 12, height: 26)
                row.onClick = { onSelect(entry.url, entry.isDirectory) }
                content.addSubview(row)
                entryRows.append(row)
                y += 27
            }
        }

        content.frame = NSRect(x: 0, y: 0, width: Self.width, height: y + 4)
        revealRow.onClick = onReveal
        layoutChrome()
    }

    private func layoutChrome() {
        let listHeight = min(content.frame.height, Self.maxListHeight)
        let totalHeight = Self.searchAreaHeight + listHeight + Self.revealHeight

        frame = NSRect(x: 0, y: 0, width: Self.width, height: totalHeight)
        effectView.frame = bounds
        tintView.frame = bounds
        searchField.frame = NSRect(x: 10, y: totalHeight - 32, width: Self.width - 20, height: 22)
        scroll.frame = NSRect(x: 0, y: Self.revealHeight, width: Self.width, height: listHeight)
        revealRow.frame = NSRect(x: 6, y: 2, width: Self.width - 12, height: 26)
    }
}
