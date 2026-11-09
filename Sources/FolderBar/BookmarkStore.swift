import Foundation

/// Persists the user's chosen folders as security-scoped bookmarks so the
/// sandboxed app can re-access them across launches without re-prompting.
final class BookmarkStore {
    static let shared = BookmarkStore()

    private let configURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("folders.json")
    }

    func load() -> [FolderConfig] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        return (try? JSONDecoder().decode([FolderConfig].self, from: data)) ?? []
    }

    func save(_ configs: [FolderConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope,
                               includingResourceValuesForKeys: nil,
                               relativeTo: nil)
    }

    /// Resolves a stored bookmark back to a URL, refreshing it if the
    /// underlying path moved. Caller must balance with `stopAccessing`.
    func resolve(_ bookmarkData: Data) -> (url: URL, refreshed: Data?)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        let refreshed = isStale ? makeBookmark(for: url) : nil
        return (url, refreshed)
    }
}
