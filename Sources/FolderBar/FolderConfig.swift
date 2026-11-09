import Foundation

enum SortMode: String, Codable, CaseIterable {
    case name, modified, created
}

struct FolderConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var bookmarkData: Data
    var displayName: String
    var symbolName: String = "folder"
    /// PNG template-image data for a user-uploaded menu-bar icon. When set,
    /// this takes priority over `symbolName`.
    var customIconData: Data?
    var sortMode: SortMode = .name
    var reversed: Bool = false
}
