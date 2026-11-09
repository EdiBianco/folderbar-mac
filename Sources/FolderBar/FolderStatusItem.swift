import AppKit

/// One menu-bar item backed by one watched folder. A kqueue watch on the
/// current directory's FD invalidates the cached listing only when that
/// directory actually changes, so re-opening the menu is normally a cheap
/// redisplay of already-current items, not a guaranteed syscall storm.
final class FolderStatusItem: NSObject, NSMenuDelegate {
    private(set) var config: FolderConfig
    private let statusItem: NSStatusItem
    private var rootURL: URL?
    private var currentURL: URL?
    private var navStack: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var needsReload = true

    init(config: FolderConfig) {
        self.config = config
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: config.symbolName, accessibilityDescription: config.displayName)
        statusItem.button?.toolTip = config.displayName

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        openFolder()
    }

    deinit {
        watcher?.cancel()
        rootURL?.stopAccessingSecurityScopedResource()
    }

    private func openFolder() {
        guard let resolved = BookmarkStore.shared.resolve(config.bookmarkData) else { return }
        rootURL = resolved.url
        currentURL = resolved.url
        if let refreshed = resolved.refreshed {
            config.bookmarkData = refreshed
        }
        startWatching(resolved.url)
    }

    private func startWatching(_ url: URL) {
        watcher?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.needsReload = true }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard rootURL != nil else {
            menu.removeAllItems()
            menu.addItem(withTitle: "Folder unavailable", action: nil, keyEquivalent: "")
            return
        }
        // Bug fix: this used to be a single `guard needsReload, let folderURL`
        // — when needsReload was already false (the common case on every
        // open after the first) the guard failed and fell into an `else`
        // branch that called menu.removeAllItems() with nothing to replace
        // it, so every click after the first showed an empty menu. The two
        // conditions are independent: a missing root folder always needs
        // the "unavailable" message; an unchanged folder should just keep
        // showing what's already there.
        guard needsReload else { return }
        needsReload = false
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let search = SearchMenuItemView()
        search.onChange = { [weak self] text in self?.applyFilter(text) }
        let searchItem = NSMenuItem()
        searchItem.view = search
        menu.addItem(searchItem)
        menu.addItem(.separator())

        if !navStack.isEmpty {
            let back = NSMenuItem(title: "⬅ Back", action: #selector(goBack), keyEquivalent: "")
            back.target = self
            menu.addItem(back)
        }

        let dir = currentURL ?? rootURL!
        let keys: [URLResourceKey] = [.nameKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        let directories = entries.filter { isDirectory($0) }
        let files = entries.filter { !isDirectory($0) }

        // Folders first, each group sorted by the configured mode.
        let ordered = sort(directories, mode: config.sortMode, reversed: config.reversed)
            + sort(files, mode: config.sortMode, reversed: config.reversed)

        if ordered.isEmpty {
            menu.addItem(withTitle: "No content", action: nil, keyEquivalent: "")
        }
        for url in ordered {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: isDirectory(url) ? #selector(navigateInto(_:)) : #selector(openEntry(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealCurrent), keyEquivalent: "")
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
    }

    /// Hides entries whose name doesn't match; non-entry rows (search field,
    /// Back, separators, Reveal) are left alone.
    private func applyFilter(_ text: String) {
        guard let menu = statusItem.menu else { return }
        let query = text.lowercased()
        for item in menu.items where item.representedObject is URL {
            item.isHidden = !(query.isEmpty || item.title.lowercased().contains(query))
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func sort(_ urls: [URL], mode: SortMode, reversed: Bool) -> [URL] {
        func key(_ url: URL) -> (name: String, modified: Date, created: Date) {
            let values = try? url.resourceValues(forKeys: [.nameKey, .contentModificationDateKey, .creationDateKey])
            return (
                values?.name ?? url.lastPathComponent,
                values?.contentModificationDate ?? .distantPast,
                values?.creationDate ?? .distantPast
            )
        }
        let sorted = urls.sorted { a, b in
            switch mode {
            case .name: return key(a).name.localizedStandardCompare(key(b).name) == .orderedAscending
            case .modified: return key(a).modified < key(b).modified
            case .created: return key(a).created < key(b).created
            }
        }
        return reversed ? sorted.reversed() : sorted
    }

    @objc private func navigateInto(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        navStack.append(currentURL ?? rootURL!)
        currentURL = url
        needsReload = true
        startWatching(url)
    }

    @objc private func goBack() {
        guard let previous = navStack.popLast() else { return }
        currentURL = previous
        needsReload = true
        startWatching(previous)
    }

    @objc private func openEntry(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealCurrent() {
        guard let url = currentURL ?? rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
