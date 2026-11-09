import AppKit

/// One clickable row (folder, file, or "Back"): icon, title, optional
/// chevron, rounded accent-color highlight on hover. Rows backed by a real
/// file (`url != nil`) get the standard Open / Show in Finder / Move to
/// Trash context menu on right-click.
final class FolderRowView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()
    private var trackingArea: NSTrackingArea?
    private let highlightColor: NSColor
    private let url: URL?

    let titleText: String
    var onClick: (() -> Void)?
    /// Lets the enclosing view track just the one hovered row (O(1) to
    /// clear on scroll) instead of sweeping every row on each scroll tick.
    var onHoverChange: ((Bool) -> Void)?

    init(icon: NSImage?, title: String, showsChevron: Bool, highlightColor: NSColor = .controlAccentColor, url: URL? = nil) {
        titleText = title
        self.highlightColor = highlightColor
        self.url = url
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
        highlight.frame = bounds.insetBy(dx: 4, dy: 2)
        iconView.frame = NSRect(x: 12, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let chevronWidth: CGFloat = chevron != nil ? 22 : 10
        titleLabel.frame = NSRect(x: 34, y: (bounds.height - 16) / 2, width: bounds.width - 34 - chevronWidth, height: 16)
        chevron?.frame = NSRect(x: bounds.width - 20, y: (bounds.height - 12) / 2, width: 10, height: 12)
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || titleText.lowercased().contains(query)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // .inVisibleRect keeps the tracking rect synced to the row's
        // on-screen position as the scroll view moves it — without it,
        // AppKit doesn't re-evaluate mouse-in/out during a scroll, so rows
        // that scrolled out from under the cursor stay stuck "highlighted"
        // (the "fake selection artifact" while scrolling).
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHighlighted(true)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(false)
        onHoverChange?(false)
    }

    /// Scroll-wheel scrolling moves rows under a stationary cursor, which
    /// generates no mouse-moved event — so AppKit never gets a chance to
    /// re-evaluate which row the mouse is now over, and a row can stay
    /// "hovered" after it has visually scrolled away. Called directly by the
    /// enclosing view when it knows this was the hovered row, so only one
    /// row's layer gets touched per scroll, not every row in the list.
    func clearHighlight() {
        setHighlighted(false)
    }

    private func setHighlighted(_ highlighted: Bool) {
        // Disable the implicit CALayer fade: this can run many times during
        // a single scroll gesture (clip-view bounds notifications fire per
        // tick), and an animated color change per tick is wasted work and
        // looks like a flicker rather than an instant, crisp state change.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.layer?.backgroundColor = (highlighted ? highlightColor : .clear).cgColor
        CATransaction.commit()
        titleLabel.textColor = highlighted ? .white : .labelColor
        chevron?.contentTintColor = highlighted ? .white : .secondaryLabelColor
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(contextOpen), keyEquivalent: "")
        menu.addItem(withTitle: "Show in Finder", action: #selector(contextReveal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move to Trash", action: #selector(contextTrash), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func contextOpen() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func contextReveal() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func contextTrash() {
        guard let url else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// Small uppercase section header ("FOLDERS" / "FILES"), matching the mockup.
private func captionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    let attributed = NSMutableAttributedString(string: text.uppercased())
    attributed.addAttribute(.kern, value: 0.4, range: NSRange(location: 0, length: attributed.length))
    label.attributedStringValue = attributed
    label.font = .systemFont(ofSize: 10.5, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.isBordered = false
    label.isEditable = false
    label.drawsBackground = false
    return label
}

/// Top-down document view for the scroll area (AppKit's default bottom-left
/// origin makes a "first row at the top" list awkward to reason about).
private final class TopDownView: NSView {
    override var isFlipped: Bool { true }
}

/// The glass panel itself: a tinted, bordered `NSVisualEffectView` with a
/// search field, section-grouped rows (folders ahead of files, as in the
/// mockup), and a persistent "Reveal in Finder" row.
final class GlassFolderView: NSView, NSSearchFieldDelegate {
    static let width: CGFloat = 300
    static let maxListHeight: CGFloat = 340
    /// The mockup's fixed accent blue, used for row selection regardless of
    /// the user's system accent color — matches the approved design exactly.
    static let accentBlue = NSColor(red: 0x0a / 255.0, green: 0x84 / 255.0, blue: 0xff / 255.0, alpha: 1)

    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 32
    private static let searchAreaHeight: CGFloat = 40
    private static let revealHeight: CGFloat = 34
    /// Extra right-side clearance for rows *inside the scroll view* so a
    /// visible scroller (overlay or legacy) draws past the row's rounded
    /// highlight instead of covering its right edge/corner.
    private static let scrollerGutter: CGFloat = 10
    private static let scrolledRowWidth: CGFloat = width - 12 - scrollerGutter

    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    private let searchField = NSSearchField()
    private let topSeparator = NSView()
    private let bottomSeparator = NSView()
    private let scroll = NSScrollView()
    private let content = TopDownView()
    private let revealRow = FolderRowView(icon: NSImage(systemSymbolName: "star", accessibilityDescription: nil),
                                           title: "Reveal in Finder", showsChevron: false,
                                           highlightColor: GlassFolderView.accentBlue)
    private var entryRows: [FolderRowView] = []
    /// The one row currently showing hover highlight, if any — tracked so a
    /// scroll only has to clear this single row instead of walking the list.
    private weak var hoveredRow: FolderRowView?

    var onSearch: ((String) -> Void)?

    private func trackHover(_ row: FolderRowView) {
        row.onHoverChange = { [weak self, weak row] isHovering in
            guard let self, let row else { return }
            if isHovering {
                hoveredRow = row
            } else if hoveredRow === row {
                hoveredRow = nil
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        addSubview(effectView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.95, alpha: 0.10).cgColor
        effectView.addSubview(tintView)

        searchField.placeholderString = "Filter…"
        searchField.delegate = self
        effectView.addSubview(searchField)

        topSeparator.wantsLayer = true
        topSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        effectView.addSubview(topSeparator)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = content
        effectView.addSubview(scroll)

        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )

        bottomSeparator.wantsLayer = true
        bottomSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        effectView.addSubview(bottomSeparator)

        effectView.addSubview(revealRow)
        updateBorderColor()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func scrollBoundsDidChange() {
        hoveredRow?.clearHighlight()
        hoveredRow = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        effectView.layer?.borderColor = NSColor(white: 1, alpha: isDark ? 0.14 : 0.6).cgColor
    }

    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }

    func filter(_ text: String) {
        let query = text.lowercased()
        for row in entryRows { row.isHidden = !row.matches(query) }
    }

    /// Rebuilds the row list for a (possibly new) directory: folders grouped
    /// under a "FOLDERS" caption ahead of files under "FILES", matching the
    /// mockup rather than one flat undifferentiated list.
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

        var y: CGFloat = 8

        if showsBack {
            let back = FolderRowView(icon: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil),
                                      title: "Back", showsChevron: false, highlightColor: Self.accentBlue)
            back.frame = NSRect(x: 6, y: y, width: Self.scrolledRowWidth, height: Self.rowHeight)
            back.onClick = onBack
            trackHover(back)
            content.addSubview(back)
            y += Self.rowSpacing + 4
        }

        func addGroup(_ caption: String, _ group: [(title: String, icon: NSImage?, isDirectory: Bool, url: URL)]) {
            guard !group.isEmpty else { return }
            let label = captionLabel(caption)
            label.frame = NSRect(x: 16, y: y, width: Self.width - 32, height: 14)
            content.addSubview(label)
            y += 22

            for entry in group {
                let row = FolderRowView(icon: entry.icon, title: entry.title, showsChevron: entry.isDirectory,
                                         highlightColor: Self.accentBlue, url: entry.url)
                row.frame = NSRect(x: 6, y: y, width: Self.scrolledRowWidth, height: Self.rowHeight)
                row.onClick = { onSelect(entry.url, entry.isDirectory) }
                trackHover(row)
                content.addSubview(row)
                entryRows.append(row)
                y += Self.rowSpacing
            }
            y += 6
        }

        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "No content")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 16, y: y + 4, width: Self.width - 32, height: 18)
            content.addSubview(empty)
            y += 28
        } else {
            addGroup("Folders", entries.filter { $0.isDirectory })
            addGroup("Files", entries.filter { !$0.isDirectory })
        }

        content.frame = NSRect(x: 0, y: 0, width: Self.width, height: y + 6)
        revealRow.onClick = onReveal
        layoutChrome()
    }

    private func layoutChrome() {
        let listHeight = min(content.frame.height, Self.maxListHeight)
        let totalHeight = Self.searchAreaHeight + listHeight + Self.revealHeight

        frame = NSRect(x: 0, y: 0, width: Self.width, height: totalHeight)
        effectView.frame = bounds
        tintView.frame = bounds
        searchField.frame = NSRect(x: 10, y: totalHeight - 34, width: Self.width - 20, height: 22)
        topSeparator.frame = NSRect(x: 8, y: totalHeight - Self.searchAreaHeight, width: Self.width - 16, height: 1)
        scroll.frame = NSRect(x: 0, y: Self.revealHeight, width: Self.width, height: listHeight)
        bottomSeparator.frame = NSRect(x: 8, y: Self.revealHeight, width: Self.width - 16, height: 1)
        revealRow.frame = NSRect(x: 6, y: 4, width: Self.width - 12, height: Self.rowHeight)
    }
}
