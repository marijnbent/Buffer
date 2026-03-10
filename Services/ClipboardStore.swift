import Foundation
import AppKit
import Combine

/// Manages persistent storage of clipboard history
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    
    private let maxItems = 100
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.buffer.save", qos: .utility)
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Buffer", isDirectory: true)
    }
    
    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }
    
    private var imagesDirectory: URL {
        storageDirectory.appendingPathComponent("images", isDirectory: true)
    }
    
    private var textsDirectory: URL {
        storageDirectory.appendingPathComponent("texts", isDirectory: true)
    }
    
    init() {
        ensureDirectoriesExist()
        loadHistory()
    }
    
    // MARK: - Public API
    
    func add(_ item: ClipboardItem) {
        // Must be called on main thread for SwiftUI updates
        if Thread.isMainThread {
            performAdd(item)
        } else {
            DispatchQueue.main.sync {
                performAdd(item)
            }
        }
    }
    
    private func performAdd(_ item: ClipboardItem) {
        print("[Buffer] Store: Adding item, current count: \(items.count)")
        
        // Insert at beginning (newest first)
        items.insert(item, at: 0)
        
        // Evict oldest unbookmarked item if over limit
        if items.count > maxItems {
            if let indexToRemove = items.lastIndex(where: { !$0.isBookmarked }) {
                let removed = items.remove(at: indexToRemove)
                deleteAssociatedFiles(for: removed)
            } else {
                // If all are bookmarked (rare), just remove the oldest one
                let removed = items.removeLast()
                deleteAssociatedFiles(for: removed)
            }
        }
        
        print("[Buffer] Store: New count: \(items.count)")
        
        // Save to disk in background
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }
    }
    
    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteAssociatedFiles(for: item)
        
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }
    }
    
    /// Toggle bookmark state for an item
    func toggleBookmark(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        // Items must be mutated
        items[index].isBookmarked.toggle()
        
        // Save updated state to disk
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }
    }
    
    /// Save extracted OCR text for an image item
    func setOCRText(_ text: String, for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].ocrText = text
        
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }
    }
    
    /// Move an item to the top of the list (most recent position)
    func moveToTop(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        // Already at top, no need to move
        if index == 0 { return }
        
        // Remove from current position and insert at top
        let removed = items.remove(at: index)
        items.insert(removed, at: 0)
        
        // Save updated order to disk
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }
    }
    
    func clear() {
        // Delete all associated files
        for item in items {
            deleteAssociatedFiles(for: item)
        }
        items.removeAll()
        
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk([])
        }
    }
    
    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let filename = item.imageFilename else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }
    
    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let url = imagesDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: url)
            return filename
        } catch {
            print("[Buffer] Failed to save image: \(error)")
            return nil
        }
    }
    
    /// Save large text to a file and return the filename
    func saveText(_ text: String) -> String? {
        let filename = UUID().uuidString + ".txt"
        let url = textsDirectory.appendingPathComponent(filename)
        
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return filename
        } catch {
            print("[Buffer] Failed to save text file: \(error)")
            return nil
        }
    }
    
    /// Load full text content from file (lazy loading for large text)
    func fullText(for item: ClipboardItem) -> String? {
        guard let filename = item.textFilename else { return item.textContent }
        let url = textsDirectory.appendingPathComponent(filename)
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[Buffer] Failed to load text file: \(error)")
            return item.textContent // Fallback to inline preview
        }
    }
    
    // MARK: - Private
    
    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: textsDirectory, withIntermediateDirectories: true)
    }
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { 
            print("[Buffer] No history file found")
            return 
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let loadedItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
            self.items = loadedItems
            print("[Buffer] Loaded \(loadedItems.count) items from history")
        } catch {
            print("[Buffer] Failed to load history: \(error)")
        }
    }
    
    private func saveHistoryToDisk(_ itemsToSave: [ClipboardItem]) {
        do {
            let data = try JSONEncoder().encode(itemsToSave)
            try data.write(to: historyFileURL)
        } catch {
            print("[Buffer] Failed to save history: \(error)")
        }
    }
    
    private func deleteImageFile(for item: ClipboardItem) {
        guard item.type == .image, let filename = item.imageFilename else { return }
        let url = imagesDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }
    
    private func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        let url = textsDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }
    
    /// Delete all associated files (images and text files) for an item
    private func deleteAssociatedFiles(for item: ClipboardItem) {
        deleteImageFile(for: item)
        deleteTextFile(for: item)
    }
}
