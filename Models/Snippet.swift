import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var trigger: String
    var content: String
    
    init(id: UUID = UUID(), title: String, trigger: String, content: String) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trigger = Self.normalizeTrigger(trigger)
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var displayTitle: String {
        title.isEmpty ? ":\(trigger)" : title
    }
    
    static func normalizeTrigger(_ trigger: String) -> String {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix(":") ? String(trimmed.dropFirst()) : trimmed
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let filtered = withoutPrefix.lowercased().unicodeScalars.filter { allowedCharacters.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
}
