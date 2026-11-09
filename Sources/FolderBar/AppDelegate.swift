import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var folderItems: [FolderStatusItem] = []
    private var controlItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        folderItems = BookmarkStore.shared.load().map(makeFolderItem)
        setUpControlItem()
    }

    private func makeFolderItem(config: FolderConfig) -> FolderStatusItem {
        let item = FolderStatusItem(config: config)
        item.onChange = { [weak self] in self?.persist() }
        item.onRemove = { [weak self] in
            guard let self else { return }
            folderItems.removeAll { $0 === item }
            persist()
        }
        return item
    }

    private func setUpControlItem() {
        controlItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controlItem.button?.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "FolderBar")

        let menu = NSMenu()

        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(
            string: "FolderBar",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Add Folder…", action: #selector(addFolder), keyEquivalent: "")
        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About FolderBar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp // AppDelegate doesn't implement terminate(_:); the auto target=self
                                 // sweep below disabled it since the target couldn't respond to the action.
        menu.addItem(quitItem)
        for item in menu.items { item.target = item.target ?? self }
        controlItem.menu = menu
    }

    @objc private func checkForUpdates() {
        UpdateChecker.checkForUpdates()
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = BookmarkStore.shared.makeBookmark(for: url) else { return }

        let config = FolderConfig(bookmarkData: bookmark, displayName: url.lastPathComponent)
        folderItems.append(makeFolderItem(config: config))
        persist()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        LoginItem.setEnabled(enable)
        sender.state = enable ? .on : .off
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let font = NSFont.systemFont(ofSize: 11)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Edi Bianco\n",
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        credits.append(NSAttributedString(
            string: "Source: GitHub",
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .link: URL(string: "https://github.com/EdiBianco/folderbar-mac")!,
            ]
        ))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func persist() {
        BookmarkStore.shared.save(folderItems.map { $0.config })
    }
}
