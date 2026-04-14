import Cocoa
import SwiftUI

/// Custom panel that closes when clicking outside
class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?
    
    override var canBecomeKey: Bool { true }
    
    override func resignKey() {
        super.resignKey()
        onClickOutside?()
    }
}

private struct ChunkedTextState {
    var visibleText: String = ""
    var totalBytes: Int = 0
    var loadedCharCount: Int = 0
    var reachedEOF: Bool = true
    var isLoadingMore: Bool = false
    static let chunkSize = 2_000
    static let initialChars = 2_000
    var hasMore: Bool { !reachedEOF && loadedCharCount >= Self.initialChars }
}

/// Manages the floating history window
class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    private var targetApplicationForPaste: NSRunningApplication?
    
    init(store: ClipboardStore) {
        self.store = store
        
        // Keep the split pane roomy, but pull the overall window in a bit.
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: panel)
        
        panel.onClickOutside = { [weak self] in
            self?.close()
        }
        
        setupPanel(panel)
        setupContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPanel(_ panel: NSPanel) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 16
        panel.contentView?.layer?.masksToBounds = true
        
        panel.center()
        
        // Notify content view when window becomes key so it can reset state
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .bufferWindowDidOpen, object: nil)
        }
    }
    
    private func setupContent() {
        let contentView = HistoryContentView(
            store: store,
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard(item)
            },
            onPaste: { [weak self] item in
                self?.pasteItem(item)
            },
            onCopyText: { [weak self] text in
                self?.copyTextToClipboard(text)
            },
            onPasteText: { [weak self] text in
                self?.pasteText(text)
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        
        window?.contentView = NSHostingView(rootView: contentView)
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.copyToClipboard(item, store: store)
    }
    
    private func copyTextToClipboard(_ text: String) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.copyTextToClipboard(text)
    }
    
    private func pasteItem(_ item: ClipboardItem) {
        let targetApplication = targetApplicationForPaste
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(item, store: store, targetApplication: targetApplication)
    }
    
    private func pasteText(_ text: String) {
        let targetApplication = targetApplicationForPaste
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(text: text, targetApplication: targetApplication)
    }
    
    override func showWindow(_ sender: Any?) {
        captureCurrentTargetApplication()
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }

    private func captureCurrentTargetApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            targetApplicationForPaste = nil
            return
        }

        if frontmostApplication.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            targetApplicationForPaste = nil
            return
        }

        targetApplicationForPaste = frontmostApplication
    }
}

extension Notification.Name {
    static let bufferIgnoreNextChange = Notification.Name("bufferIgnoreNextChange")
    static let bufferHotkeyChanged = Notification.Name("bufferHotkeyChanged")
    static let bufferWindowDidOpen = Notification.Name("bufferWindowDidOpen")
    static let bufferHistoryLimitChanged = Notification.Name("bufferHistoryLimitChanged")
}

private enum HistorySelectionID: Hashable {
    case clipboard(UUID)
    case snippet(UUID)
}

private enum HistorySearchResult: Identifiable {
    case clipboard(ClipboardItem)
    case snippet(Snippet)
    
    var id: String {
        switch self {
        case .clipboard(let item):
            return "clipboard-\(item.id.uuidString)"
        case .snippet(let snippet):
            return "snippet-\(snippet.id.uuidString)"
        }
    }
    
    var selectionID: HistorySelectionID {
        switch self {
        case .clipboard(let item):
            return .clipboard(item.id)
        case .snippet(let snippet):
            return .snippet(snippet.id)
        }
    }
}

private enum DetailPaneMode: Equatable {
    case preview
    case quickActions
}

private enum QuickActionRoute: Equatable {
    case home
    case saveSnippet
    case addToSnippet
    case confirmDelete
}

private struct SnippetRow: View {
    let snippet: Snippet
    let isSelected: Bool

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var backgroundCornerRadius: CGFloat {
        isSelected ? 0 : 5
    }

    var body: some View {
        HStack(spacing: 8) {
            // Pill-style trigger badge — makes the monospaced shorthand visually distinct
            Text(":\(snippet.trigger)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                if !snippet.title.isEmpty {
                    Text(snippet.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Text(snippet.content)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Main content view - Split pane with list and detail
struct HistoryContentView: View {
    private static let initialVisibleClipboardItemLimit = 50

    @ObservedObject var store: ClipboardStore
    @StateObject private var snippetStore = SnippetStore.shared
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onCopyText: (String) -> Void
    let onPasteText: (String) -> Void
    let onDismiss: () -> Void
    
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var previewImage: NSImage?
    @State private var chunkedText = ChunkedTextState()
    @State private var scrollTrigger = false  // Triggers scroll on keyboard navigation
    @State private var itemSize: Int?         // Holds computed size of item
    @State private var detailPaneMode: DetailPaneMode = .preview
    @State private var quickActionRoute: QuickActionRoute = .home
    @State private var snippetDraftTitle = ""
    @State private var snippetDraftTrigger = ""
    @State private var snippetDraftContent = ""
    @State private var snippetTargetSearch = ""
    @State private var selectedSnippetTargetID: UUID?
    @State private var quickActionMessage: String?
    @State private var quickActionError: String?
    
    
    // OCR state
    @State private var isExtractingText = false
    
    // Track selection by ID so it survives list insertions
    @State private var selectedID: HistorySelectionID?
    
    private var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return Array(store.items.prefix(Self.initialVisibleClipboardItemLimit))
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(store.items.prefix(Self.initialVisibleClipboardItemLimit)) }

        return store.items.filter { item in
            itemMatchesSearch(item, query: query)
        }
    }
    
    private var isSnippetSearch: Bool {
        searchText.hasPrefix(":")
    }
    
    private var filteredSnippets: [Snippet] {
        guard isSnippetSearch else { return [] }
        
        let query = String(searchText.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return snippetStore.snippets
        }
        return snippetStore.matches(for: query)
    }
    
    private var filteredResults: [HistorySearchResult] {
        if isSnippetSearch {
            return filteredSnippets.map { .snippet($0) }
        }
        return filteredItems.map { .clipboard($0) }
    }
    
    private var selectedResult: HistorySearchResult? {
        if let id = selectedID, let result = filteredResults.first(where: { $0.selectionID == id }) {
            return result
        }
        return filteredResults[safe: selectedIndex]
    }
    
    private var selectedItem: ClipboardItem? {
        if case .clipboard(let item)? = selectedResult {
            return item
        }
        return nil
    }
    
    private var selectedSnippet: Snippet? {
        if case .snippet(let snippet)? = selectedResult {
            return snippet
        }
        return nil
    }
    
    private var resultCountLabel: String {
        let count = filteredResults.count
        if isSnippetSearch {
            return "\(count) snippet" + (count == 1 ? "" : "s")
        }
        return "\(count) item" + (count == 1 ? "" : "s")
    }

    private var selectedItemActionText: String? {
        guard let item = selectedItem else { return nil }
        return actionText(for: item)
    }

    private var selectedItemActionWarning: String? {
        guard let item = selectedItem else { return nil }
        return actionWarning(for: item)
    }

    private var filteredSnippetTargets: [Snippet] {
        let query = snippetTargetSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snippetStore.snippets }

        return snippetStore.snippets.filter { snippet in
            snippet.displayTitle.localizedCaseInsensitiveContains(query) ||
            snippet.trigger.localizedCaseInsensitiveContains(query) ||
            snippet.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedSnippetTarget: Snippet? {
        guard let selectedSnippetTargetID else { return filteredSnippetTargets.first }
        return filteredSnippetTargets.first(where: { $0.id == selectedSnippetTargetID }) ?? filteredSnippetTargets.first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            Divider()
            
            // Split pane: List + Detail
            HSplitView {
                // Left: List
                listPane
                    .frame(minWidth: 300, maxWidth: 340)
                
                // Right: Detail
                detailPane
                    .frame(minWidth: 260)
            }
        }
        .frame(minWidth: 580, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: searchText) { _ in
            resetQuickActionState()
            selectedIndex = 0
            selectedID = filteredResults[safe: 0]?.selectionID
        }
        .onChange(of: selectedIndex) { newIndex in
            selectedID = filteredResults[safe: newIndex]?.selectionID
        }
        .onChange(of: selectedID) { _ in
            resetQuickActionState()
        }
        .onChange(of: snippetTargetSearch) { _ in
            selectedSnippetTargetID = filteredSnippetTargets.first?.id
        }
        .onChange(of: store.items) { _ in
            syncSelection()
        }
        .onChange(of: snippetStore.snippets) { _ in
            if isSnippetSearch {
                syncSelection()
            }

            if let currentTarget = selectedSnippetTarget,
               selectedSnippetTargetID != currentTarget.id {
                selectedSnippetTargetID = currentTarget.id
            } else if filteredSnippetTargets.isEmpty {
                selectedSnippetTargetID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
            resetQuickActionState()
            searchText = ""
            selectedIndex = 0
            selectedID = store.items.first.map { HistorySelectionID.clipboard($0.id) }
            // Delay needed for NSHostingView to have settled as key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .task(id: selectedItem?.id) {
            // Clear preview
            resetQuickActionState()
            previewImage = nil
            chunkedText = ChunkedTextState()
            isExtractingText = false
            itemSize = nil
            
            // Load new preview async
            if let item = selectedItem {
                itemSize = store.itemSize(for: item)
                
                if item.type == .image {
                    previewImage = await loadPreviewImage(for: item)
                } else if item.type == .text {
                    if item.isFileBacked {
                        await loadInitialChunk(for: item)
                    } else {
                        chunkedText.visibleText = item.textContent ?? ""
                        chunkedText.reachedEOF = true
                    }
                }
            }
        }
        .background(GlobalKeyMonitor(
            onUp: {
                scrollTrigger = true
                navigateUp()
            },
            onDown: {
                scrollTrigger = true
                navigateDown()
            },
            onEnter: {
                if let result = selectedResult {
                    activateResult(result)
                }
            },
            onEscape: onDismiss,
            onDelete: {
                if let item = selectedItem {
                    deleteSelectedItem(item)
                }
            },
            onCopy: {
                if let item = selectedItem {
                    onCopyToClipboard(item)
                } else if let snippet = selectedSnippet {
                    onCopyText(snippet.content)
                }
            }
        ))
    }
    
    private func loadPreviewImage(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = store.image(for: item)
                continuation.resume(returning: img)
            }
        }
    }
    
    private func loadInitialChunk(for item: ClipboardItem) async {
        chunkedText.isLoadingMore = true // Initial load spinner
        let chunkSource = store.textChunkSource(for: item)
        
        let chunkResult = await Task.detached(priority: .userInitiated) {
            ClipboardStore.readTextChunk(from: chunkSource, charCount: ChunkedTextState.initialChars)
        }.value
        
        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }
    
    private func loadNextChunk(for item: ClipboardItem) async {
        guard !chunkedText.isLoadingMore && chunkedText.hasMore else { return }
        
        chunkedText.isLoadingMore = true
        let nextCharCount = chunkedText.loadedCharCount + ChunkedTextState.chunkSize
        let chunkSource = store.textChunkSource(for: item)
        
        let chunkResult = await Task.detached(priority: .userInitiated) {
            ClipboardStore.readTextChunk(from: chunkSource, charCount: nextCharCount)
        }.value
        
        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }
    
    private func formattedByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formattedSize(bytes: Int) -> String {
        return formattedByteCount(bytes)
    }
    
    private func relativeCopiedText(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        
        if seconds < 60 {
            return "Copied just now"
        }
        
        if seconds < 3_600 {
            let minutes = seconds / 60
            return "Copied \(minutes) min ago"
        }
        
        if seconds < 86_400 {
            let hours = seconds / 3_600
            return "Copied \(hours)h ago"
        }
        
        let days = seconds / 86_400
        return "Copied \(days)d ago"
    }
    
    private func fullCopiedText(for date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .accessibilityLabel("Search clipboard")

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Use windowBackgroundColor so the bar blends with the panel rather than
        // appearing heavier than the content area
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var listPane: some View {
        Group {
            if filteredResults.isEmpty {
                // Empty state with icon for visual weight
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(emptyStateText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, result in
                                resultRow(for: result, isSelected: index == selectedIndex)
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        resultContextMenu(for: result, index: index)
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            selectResult(at: index)
                                        }
                                    }
                                    .simultaneousGesture(
                                        TapGesture(count: 1)
                                            .onEnded { _ in
                                                selectResult(at: index)
                                                activateResult(result)
                                            }
                                    )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: selectedIndex) { newValue in
                        if scrollTrigger {
                            if let result = filteredResults[safe: newValue] {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    proxy.scrollTo(result.id)
                                }
                            }
                            scrollTrigger = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                        if let firstID = filteredResults.first?.id {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
            }
        }
        // Slightly tinted list background distinguishes pane from detail
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
    
    private var detailPane: some View {
        Group {
            if let item = selectedItem {
                VStack(spacing: 0) {
                    detailPaneHeader(for: item)
                    Divider()

                    if detailPaneMode == .quickActions {
                        quickActionsPane(for: item)
                    } else {
                        previewPane(for: item)
                    }
                }
            } else if let snippet = selectedSnippet {
                ScrollView {
                    snippetContent(snippet)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                // Empty detail state — give it some visual presence
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundColor(.secondary.opacity(0.25))
                    Text("Select an item to preview")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailPaneHeader(for item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detailPaneMode == .quickActions ? "Quick Actions" : "Preview")
                    .font(.system(size: 12, weight: .semibold))
                Text(detailPaneMode == .quickActions ? quickActionSubtitle(for: item) : fullCopiedText(for: item.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if detailPaneMode == .quickActions {
                Button("Back") {
                    detailPaneMode = .preview
                    quickActionRoute = .home
                    quickActionMessage = nil
                    quickActionError = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    openQuickActions(for: item)
                } label: {
                    Label("Quick Actions", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func previewPane(for item: ClipboardItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                itemContent(item)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            HStack {
                if !item.isFileBacked, let text = item.textContent, !text.isEmpty {
                    let words = text.split(whereSeparator: \.isWhitespace).count
                    Text("\(words) words · \(text.count) chars")
                } else if let size = itemSize, size > 0 {
                    Text(formattedByteCount(size))
                }
                Spacer()
                Text(fullCopiedText(for: item.timestamp))
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary.opacity(0.7))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func quickActionsPane(for item: ClipboardItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let quickActionMessage {
                    quickActionStatus(text: quickActionMessage, systemImage: "checkmark.circle.fill", tint: .green)
                }

                if let quickActionError {
                    quickActionStatus(text: quickActionError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }

                switch quickActionRoute {
                case .home:
                    quickActionsHomePane(for: item)
                case .saveSnippet:
                    quickActionSaveSnippetPane(for: item)
                case .addToSnippet:
                    quickActionAddToSnippetPane(for: item)
                case .confirmDelete:
                    quickActionDeletePane(for: item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func quickActionsHomePane(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            quickActionButton(
                title: "Save as Snippet",
                subtitle: selectedItemActionText == nil
                    ? "Needs text content first"
                    : "Create a new reusable snippet from this item",
                systemImage: "square.and.arrow.down"
            ) {
                openQuickActions(for: item, route: .saveSnippet)
            }
            .disabled(selectedItemActionText == nil)

            quickActionButton(
                title: "Add to Snippet",
                subtitle: snippetStore.snippets.isEmpty
                    ? "Create a snippet first"
                    : "Append this value to one of your saved snippets",
                systemImage: "text.insert"
            ) {
                openQuickActions(for: item, route: .addToSnippet)
            }
            .disabled(selectedItemActionText == nil || snippetStore.snippets.isEmpty)

            if item.type == .image {
                quickActionButton(
                    title: item.ocrText == nil ? "Run OCR" : "Refresh OCR",
                    subtitle: item.ocrText == nil
                        ? "Extract text so the image can be reused"
                        : "Extract the text again from this image",
                    systemImage: isExtractingText ? "ellipsis.circle" : "text.viewfinder"
                ) {
                    runOCR(for: item)
                }
                .disabled(isExtractingText)
            }

            quickActionButton(
                title: "Delete from History",
                subtitle: "Remove this clipboard item and its stored files",
                systemImage: "trash",
                isDestructive: true
            ) {
                quickActionMessage = nil
                quickActionError = nil
                quickActionRoute = .confirmDelete
            }

            if let warning = selectedItemActionWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func quickActionSaveSnippetPane(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as Snippet")
                .font(.system(size: 16, weight: .semibold))

            if selectedItemActionText == nil {
                Text(selectedItemActionWarning ?? "This item does not have text available for snippets.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Snippet label", text: $snippetDraftTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("shortcut", text: $snippetDraftTrigger)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextEditor(text: $snippetDraftContent)
                        .font(.system(size: 12))
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            HStack {
                Button("Back") {
                    quickActionRoute = .home
                    quickActionError = nil
                    quickActionMessage = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save Snippet") {
                    saveSnippetFromQuickActions()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItemActionText == nil)
            }
        }
    }

    private func quickActionAddToSnippetPane(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to Snippet")
                .font(.system(size: 16, weight: .semibold))

            if snippetStore.snippets.isEmpty {
                Text("Create a snippet first, then you can append clipboard values to it here.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if selectedItemActionText == nil {
                Text(selectedItemActionWarning ?? "This item does not have text available for snippets.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                TextField("Search snippets", text: $snippetTargetSearch)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(filteredSnippetTargets.prefix(8))) { snippet in
                        Button {
                            selectedSnippetTargetID = snippet.id
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.displayTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(":\(snippet.trigger)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                if selectedSnippetTarget?.id == snippet.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                (selectedSnippetTarget?.id == snippet.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if filteredSnippetTargets.isEmpty {
                    Text("No snippets match that search.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if let snippet = selectedSnippetTarget {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected snippet")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(snippet.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(snippet.content)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            HStack {
                Button("Back") {
                    quickActionRoute = .home
                    quickActionError = nil
                    quickActionMessage = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add to Snippet") {
                    appendToSelectedSnippet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItemActionText == nil || selectedSnippetTarget == nil)
            }
        }
    }

    private func quickActionDeletePane(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete from History")
                .font(.system(size: 16, weight: .semibold))

            Text("This removes the selected clipboard item from history.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack {
                Button("Back") {
                    quickActionRoute = .home
                    quickActionError = nil
                    quickActionMessage = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Delete", role: .destructive) {
                    deleteSelectedItem(item)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func quickActionStatus(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func quickActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundColor(isDestructive ? .red : .accentColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDestructive ? .red : .primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var emptyStateText: String {
        if searchText.isEmpty {
            return "No clipboard history"
        }
        return isSnippetSearch ? "No snippets" : "No matches"
    }
    
    @ViewBuilder
    private func resultRow(for result: HistorySearchResult, isSelected: Bool) -> some View {
        switch result {
        case .clipboard(let item):
            ClipboardItemRow(
                item: item,
                store: store,
                isSelected: isSelected
            )
        case .snippet(let snippet):
            SnippetRow(snippet: snippet, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private func resultContextMenu(for result: HistorySearchResult, index: Int) -> some View {
        switch result {
        case .clipboard(let item):
            Button("Quick Actions") {
                selectResult(at: index)
                openQuickActions(for: item)
            }

            Button("Save as Snippet") {
                selectResult(at: index)
                openQuickActions(for: item, route: .saveSnippet)
            }

            Button("Add to Snippet") {
                selectResult(at: index)
                openQuickActions(for: item, route: .addToSnippet)
            }

            if item.type == .image {
                Button(item.ocrText == nil ? "Run OCR" : "Refresh OCR") {
                    selectResult(at: index)
                    runOCR(for: item)
                }
            }

            Divider()

            Button("Delete from History", role: .destructive) {
                selectResult(at: index)
                deleteSelectedItem(item)
            }
        case .snippet:
            EmptyView()
        }
    }
    
    private func copySelectedResult(_ result: HistorySearchResult) {
        switch result {
        case .clipboard(let item):
            onCopyToClipboard(item)
        case .snippet(let snippet):
            onCopyText(snippet.content)
        }
    }
    
    private func activateResult(_ result: HistorySearchResult) {
        switch result {
        case .clipboard(let item):
            onPaste(item)
        case .snippet(let snippet):
            onPasteText(snippet.content)
        }
    }

    private func quickActionSubtitle(for item: ClipboardItem) -> String {
        switch item.type {
        case .text:
            return "Snippet and history actions for this text item"
        case .image:
            if item.ocrText == nil {
                return "Run OCR, then reuse or remove this image"
            }
            return "OCR, snippet, and history actions for this image"
        }
    }

    private func resetQuickActionState() {
        detailPaneMode = .preview
        quickActionRoute = .home
        snippetDraftTitle = ""
        snippetDraftTrigger = ""
        snippetDraftContent = ""
        snippetTargetSearch = ""
        selectedSnippetTargetID = nil
        quickActionMessage = nil
        quickActionError = nil
    }

    private func suggestedTrigger(from text: String) -> String {
        let pieces = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return Array(pieces.prefix(3)).joined(separator: "-")
    }

    private func actionText(for item: ClipboardItem) -> String? {
        switch item.type {
        case .text:
            let text = store.fullText(for: item) ?? item.textContent ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .image:
            let trimmed = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    private func actionWarning(for item: ClipboardItem) -> String? {
        if item.type == .image && actionText(for: item) == nil {
            return "Run OCR first to use this image in a snippet."
        }

        if item.isTruncated {
            return "Only the stored preview is available for snippet actions."
        }

        return nil
    }

    private func itemMatchesSearch(_ item: ClipboardItem, query: String) -> Bool {
        switch item.type {
        case .text:
            let text = store.fullText(for: item) ?? item.textContent ?? ""
            if text.localizedCaseInsensitiveContains(query) {
                return true
            }
        case .image:
            if let ocrText = item.ocrText,
               ocrText.localizedCaseInsensitiveContains(query) {
                return true
            }
        }

        if let sourceApp = item.sourceApp,
           sourceApp.localizedCaseInsensitiveContains(query) {
            return true
        }

        return item.previewText.localizedCaseInsensitiveContains(query)
    }

    private func prepareSnippetDraft(for item: ClipboardItem) {
        let sourceText = actionText(for: item) ?? ""
        snippetDraftTitle = item.sourceApp ?? ""
        snippetDraftTrigger = suggestedTrigger(from: sourceText)
        snippetDraftContent = sourceText
    }

    private func openQuickActions(for item: ClipboardItem, route: QuickActionRoute = .home) {
        detailPaneMode = .quickActions
        quickActionRoute = route
        quickActionMessage = nil
        quickActionError = nil

        switch route {
        case .home:
            break
        case .saveSnippet:
            prepareSnippetDraft(for: item)
        case .addToSnippet:
            snippetTargetSearch = ""
            selectedSnippetTargetID = snippetStore.snippets.first?.id
        case .confirmDelete:
            break
        }
    }

    private func saveSnippetFromQuickActions() {
        let content = snippetDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try snippetStore.saveSnippet(
                title: snippetDraftTitle,
                trigger: snippetDraftTrigger,
                content: content
            )
            let normalizedTrigger = Snippet.normalizeTrigger(snippetDraftTrigger)
            quickActionRoute = .home
            quickActionError = nil
            quickActionMessage = "Saved snippet :\(normalizedTrigger)"
            snippetDraftTitle = ""
            snippetDraftTrigger = ""
            snippetDraftContent = ""
        } catch {
            quickActionError = error.localizedDescription
            quickActionMessage = nil
        }
    }

    private func appendToSelectedSnippet() {
        guard let snippet = selectedSnippetTarget else {
            quickActionError = "Choose a snippet first."
            quickActionMessage = nil
            return
        }

        guard let text = selectedItemActionText else {
            quickActionError = "This item does not have text available."
            quickActionMessage = nil
            return
        }

        let mergedContent = snippet.content.isEmpty ? text : "\(snippet.content)\n\(text)"

        do {
            try snippetStore.saveSnippet(
                id: snippet.id,
                title: snippet.title,
                trigger: snippet.trigger,
                content: mergedContent
            )
            quickActionRoute = .home
            quickActionError = nil
            quickActionMessage = "Added to :\(snippet.trigger)"
        } catch {
            quickActionError = error.localizedDescription
            quickActionMessage = nil
        }
    }

    private func runOCR(for item: ClipboardItem) {
        guard item.type == .image else { return }
        guard let image = store.image(for: item) else {
            quickActionError = "Couldn't load this image."
            quickActionMessage = nil
            return
        }

        detailPaneMode = .quickActions
        quickActionRoute = .home
        quickActionMessage = nil
        quickActionError = nil
        isExtractingText = true

        Task {
            let result = await OCRService.shared.recognizeText(from: image)

            await MainActor.run {
                let text = result?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedText = (text?.isEmpty == false) ? text! : "No text found in this image."
                store.setOCRText(resolvedText, for: item)
                isExtractingText = false
                quickActionMessage = resolvedText == "No text found in this image."
                    ? resolvedText
                    : "OCR text is ready."
            }
        }
    }

    private func deleteSelectedItem(_ item: ClipboardItem) {
        quickActionMessage = nil
        quickActionError = nil
        store.delete(item)
    }

    private func selectResult(at index: Int) {
        selectedIndex = index
        selectedID = filteredResults[safe: index]?.selectionID
    }
    
    private func syncSelection() {
        guard !filteredResults.isEmpty else {
            selectedIndex = 0
            selectedID = nil
            return
        }
        
        guard let selectedID else {
            self.selectedID = filteredResults.first?.selectionID
            selectedIndex = 0
            return
        }
        
        if let newIndex = filteredResults.firstIndex(where: { $0.selectionID == selectedID }) {
            if selectedIndex != newIndex {
                selectedIndex = newIndex
            }
        } else {
            self.selectedID = filteredResults.first?.selectionID
            selectedIndex = 0
        }
    }
    
    @ViewBuilder
    private func itemContent(_ item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            if item.isTruncated {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.textContent ?? "")
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Label("Content was too large to store (\(formattedSize(bytes: item.originalSizeBytes ?? 0))). Showing first 500 characters.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else if item.isFileBacked {
                textContent(item)
            } else {
                Text(item.textContent ?? "")
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            VStack(spacing: 12) {
                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    // Loading placeholder
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                }
                
                // OCR result
                if isExtractingText {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 12)
                } else if let ocrText = item.ocrText {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 0.5)
                        
                        HStack(alignment: .top) {
                            Text(ocrText)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ocrText, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Copy extracted text")
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
    }
    
    private func snippetContent(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !snippet.title.isEmpty {
                Text(snippet.title)
                    .font(.system(size: 16, weight: .semibold))
            }
            
            Text(":\(snippet.trigger)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
            
            Text(snippet.content)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    @ViewBuilder
    private func textContent(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chunkedText.visibleText)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
            if chunkedText.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else if chunkedText.hasMore {
                // This hint fires .onAppear only when it scrolls into view (LazyVStack)
                // That's what triggers the next chunk load
                Text("— \(formattedByteCount(chunkedText.totalBytes)) total · scroll to load more —")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .onAppear {
                        Task { await loadNextChunk(for: item) }
                    }
            }
        }
    }
    
    private func navigateUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    private func navigateDown() {
        if selectedIndex < filteredResults.count - 1 {
            selectedIndex += 1
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Monitors global key events for the window
struct GlobalKeyMonitor: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Add local monitor to window
            guard let window = view.window else { return }
            
            // We use a property on the window or controller to store the monitor
            // But for simplicity in SwiftUI, we'll use a weak ref approach here
            // or just rely on the view traversing up. 
            // Actually, best way is to add monitor to the window.
            
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 126: // Up
                    onUp()
                    return nil // Consume event
                case 125: // Down
                    onDown()
                    return nil // Consume event
                case 36: // Enter
                    onEnter()
                    return nil
                case 53: // Escape
                    onEscape()
                    return nil
                case 51: // Delete
                    // Check if search field is first responder - if so, don't consume delete unless empty?
                    // For now, let's assume Cmd+Delete or just Delete on list.
                    // If we consume Delete always, we can't delete text in search.
                    // So let's only consume if we are NOT editing text OR if modifier is used.
                    // But simpler: Only trigger if search text is empty? 
                    // Let's rely on Command+Delete for item deletion to be safe/standard
                    if event.modifierFlags.contains(.command) {
                        onDelete()
                        return nil
                    }
                    return event
                case 8: // C (for Copy)
                    if event.modifierFlags.contains(.command) {
                        // If text is selected in a text view, let the system handle native copy
                        if let responder = view.window?.firstResponder, responder is NSTextView {
                            return event
                        }
                        onCopy()
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
            
            // Store monitor to remove later? 
            // In a real app we need to clean up. For this snippet, 
            // the monitor lasts as long as the window is open.
            // Since the window is closed/released, the monitor should be cleaned up 
            // if we attached it to the window properly or if we remove it on dismantle.
            // However, NSEvent.addLocalMonitorForEvents returns an object that must be removed.
            
            context.coordinator.monitor = monitor
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var monitor: Any?
        
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
