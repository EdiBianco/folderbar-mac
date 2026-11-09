import AppKit

/// Live-filter field hosted as a custom NSMenuItem view, so it stays
/// editable while the status-bar menu is open.
final class SearchMenuItemView: NSView, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    var onChange: ((String) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        autoresizingMask = [.width]
        searchField.frame = NSRect(x: 10, y: 3, width: bounds.width - 20, height: 22)
        searchField.autoresizingMask = [.width]
        searchField.placeholderString = "Filter…"
        searchField.delegate = self
        addSubview(searchField)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func controlTextDidChange(_ obj: Notification) {
        onChange?(searchField.stringValue)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(searchField)
    }
}
