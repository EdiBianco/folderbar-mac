import AppKit

/// One menu-bar item backed by one watched folder. Left-click shows a
/// translucent, tinted glass panel (NSPopover + NSVisualEffectView — a plain
/// NSMenu has no way to carry a custom tint) listing the current directory;
/// right-click shows a plain native context menu to change or remove the
/// folder. A kqueue watch on the current directory's FD invalidates the
/// cached listing only when that directory actually changes.
final class FolderStatusItem: NSObject {
    private(set) var config: FolderConfig
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let glassView = GlassFolderView(frame: NSRect(x: 0, y: 0, width: GlassFolderView.width, height: 1))

    private var rootURL: URL?
    private var currentURL: URL?
    private var navStack: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var needsReload = true

    /// Set by AppDelegate: persist after a source-folder change, and remove
    /// this item from its tracked list (plus re-persist) after Remove.
    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?

    init(config: FolderConfig) {
        self.config = config
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: config.symbolName, accessibilityDescription: config.displayName)
        statusItem.button?.toolTip = config.displayName
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        let controller = NSViewController()
        controller.view = glassView
        popover.contentViewController = controller
        glassView.onSearch = { [weak self] text in self?.glassView.filter(text) }

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

    // MARK: Click routing

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if needsReload {
            needsReload = false
            rebuildRows()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// NSStatusItem shows `.menu` instead of dispatching the button's action
    /// whenever `.menu` is non-nil, so this is set only for the duration of
    /// the programmatic click that displays it — the standard idiom for
    /// giving left- and right-click different presentations on one item.
    private func showContextMenu() {
        let menu = NSMenu()
        let change = NSMenuItem(title: "Change Source Folder…", action: #selector(changeSourceFolder), keyEquivalent: "")
        change.target = self
        menu.addItem(change)
        let remove = NSMenuItem(title: "Remove", action: #selector(removeFolder), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Content

    private func rebuildRows() {
        guard let dir = currentURL ?? rootURL else {
            glassView.reload(showsBack: false, entries: [], onBack: {}, onSelect: { _, _ in }, onReveal: {})
            popover.contentSize = glassView.frame.size
            return
        }

        let keys: [URLResourceKey] = [.nameKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey, .isApplicationKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        // .app bundles are directories on disk, but drilling "into" one to
        // browse its Contents/ isn't what anyone wants from a quick-launch
        // list — treat them as openable files, not navigable folders.
        let directories = entries.filter { isNavigableFolder($0) }
        let files = entries.filter { !isNavigableFolder($0) }
        let ordered = sort(directories, mode: config.sortMode, reversed: config.reversed)
            + sort(files, mode: config.sortMode, reversed: config.reversed)

        let rowData = ordered.map { url in
            (title: url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: resolvedTarget(url).path), isDirectory: isNavigableFolder(url), url: url)
        }

        glassView.reload(
            showsBack: !navStack.isEmpty,
            entries: rowData,
            onBack: { [weak self] in self?.goBack() },
            onSelect: { [weak self] url, isDir in
                if isDir { self?.navigateInto(url) } else { self?.openEntry(url) }
            },
            onReveal: { [weak self] in self?.revealCurrent() }
        )
        // NSPopover doesn't observe its content view's frame after first
        // display — without this, a smaller next directory leaves the view
        // anchored at the bottom of the still-larger old window, i.e. a
        // blank gap up top (exactly the broken layout seen after navigating).
        popover.contentSize = glassView.frame.size
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func isApplication(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isApplicationKey]))?.isApplication ?? false
    }

    private func isNavigableFolder(_ url: URL) -> Bool {
        let target = resolvedTarget(url)
        return isDirectory(target) && !isApplication(target)
    }

    // Finder alias files (not plain symlinks) are regular files on disk —
    // .isDirectoryKey on the alias itself is always false, so without
    // resolving them they show up as generic "files" with a generic icon
    // instead of their target's folder/app icon.
    private func resolvedTarget(_ url: URL) -> URL {
        (try? URL(resolvingAliasFileAt: url)) ?? url
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

    private func navigateInto(_ url: URL) {
        navStack.append(currentURL ?? rootURL!)
        currentURL = url
        startWatching(url)
        rebuildRows()
    }

    private func goBack() {
        guard let previous = navStack.popLast() else { return }
        currentURL = previous
        startWatching(previous)
        rebuildRows()
    }

    private func openEntry(_ url: URL) {
        NSWorkspace.shared.open(url)
        popover.performClose(nil)
    }

    private func revealCurrent() {
        guard let url = currentURL ?? rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        popover.performClose(nil)
    }

    // MARK: Context menu actions

    @objc private func changeSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = BookmarkStore.shared.makeBookmark(for: url) else { return }

        rootURL?.stopAccessingSecurityScopedResource()
        config.bookmarkData = bookmark
        config.displayName = url.lastPathComponent
        navStack.removeAll()
        needsReload = true
        statusItem.button?.toolTip = config.displayName
        openFolder()
        onChange?()
    }

    @objc private func removeFolder() {
        watcher?.cancel()
        rootURL?.stopAccessingSecurityScopedResource()
        NSStatusBar.system.removeStatusItem(statusItem)
        onRemove?()
    }
}
