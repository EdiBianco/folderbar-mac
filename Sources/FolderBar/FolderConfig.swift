import Foundation

enum SortMode: String, Codable, CaseIterable {
    case name, modified, created
}

struct FolderConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var bookmarkData: Data
    var displayName: String
    var symbolName: String = "folder"
    var sortMode: SortMode = .name
    var reversed: Bool = false
}
