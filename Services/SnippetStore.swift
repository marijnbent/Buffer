import Foundation
import Combine

enum SnippetStoreError: LocalizedError {
    case emptyTrigger
    case emptyContent
    case duplicateTrigger
    
    var errorDescription: String? {
        switch self {
        case .emptyTrigger:
            return "Enter a trigger."
        case .emptyContent:
            return "Enter text to insert."
        case .duplicateTrigger:
            return "That trigger already exists."
        }
    }
}

final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()
    
    @Published private(set) var snippets: [Snippet] = []
    
    private let defaults = UserDefaults.standard
    private let snippetsKey = "savedSnippets"
    private let persistenceQueue = DispatchQueue(label: "nl.bentjes.buffer.snippets.persistence", qos: .utility)
    
    private init() {
        load()
    }
    
    func saveSnippet(id: UUID? = nil, title: String, trigger: String, content: String) throws {
        let normalizedTrigger = Snippet.normalizeTrigger(trigger)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedTrigger.isEmpty else { throw SnippetStoreError.emptyTrigger }
        guard !trimmedContent.isEmpty else { throw SnippetStoreError.emptyContent }
        guard !snippets.contains(where: { $0.trigger == normalizedTrigger && $0.id != id }) else {
            throw SnippetStoreError.duplicateTrigger
        }
        
        let snippet = Snippet(id: id ?? UUID(), title: title, trigger: normalizedTrigger, content: trimmedContent)
        
        if let existingIndex = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[existingIndex] = snippet
        } else {
            snippets.append(snippet)
        }
        
        sortSnippets()
        
        persist()
    }
    
    func deleteSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }
    
    func matches(for query: String) -> [Snippet] {
        let normalizedQuery = Snippet.normalizeTrigger(query)
        guard !normalizedQuery.isEmpty else { return [] }
        
        return snippets
            .filter { snippet in
                snippet.trigger.hasPrefix(normalizedQuery) ||
                snippet.title.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.trigger.hasPrefix(normalizedQuery)
                let rhsPrefix = rhs.trigger.hasPrefix(normalizedQuery)
                
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix && !rhsPrefix
                }
                
                if lhs.trigger.count != rhs.trigger.count {
                    return lhs.trigger.count < rhs.trigger.count
                }
                
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }
    
    private func load() {
        guard let data = defaults.data(forKey: snippetsKey) else { return }
        
        do {
            snippets = try JSONDecoder().decode([Snippet].self, from: data)
            sortSnippets()
        } catch {
            print("[Buffer] Failed to load snippets: \(error)")
        }
    }
    
    private func persist() {
        let snapshot = snippets
        
        persistenceQueue.async { [defaults, snippetsKey] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                defaults.set(data, forKey: snippetsKey)
            } catch {
                print("[Buffer] Failed to save snippets: \(error)")
            }
        }
    }
    
    private func sortSnippets() {
        snippets.sort { lhs, rhs in
            if lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedSame {
                return lhs.trigger < rhs.trigger
            }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}
