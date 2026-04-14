import Cocoa
import SwiftUI
import ApplicationServices

@MainActor
final class SnippetExpansionController {
    private let generatedEventMarker: Int64 = 0x425546464552
    private let store: SnippetStore
    private let suggestionWindowController = SnippetSuggestionWindowController()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeQuery: String?
    private var matches: [Snippet] = []
    private var selectedIndex = 0
    private var activationObserver: NSObjectProtocol?
    
    init(store: SnippetStore) {
        self.store = store
    }
    
    func start() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<SnippetExpansionController>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("[Buffer] Failed to create snippet event tap")
            return
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
        
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelSession()
            }
        }
    }
    
    func stop() {
        cancelSession()
        
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        if event.getIntegerValueField(.eventSourceUserData) == generatedEventMarker {
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        
        if shouldConsumeControlKey(nsEvent) {
            return nil
        }
        
        processTextKey(nsEvent)
        return Unmanaged.passUnretained(event)
    }
    
    private func shouldConsumeControlKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            guard isSessionActive else { return false }
            cancelSession()
            return true
        case 125: // Down
            guard suggestionWindowController.isVisible, !matches.isEmpty else { return false }
            selectedIndex = min(selectedIndex + 1, matches.count - 1)
            refreshSuggestions()
            return true
        case 126: // Up
            guard suggestionWindowController.isVisible, !matches.isEmpty else { return false }
            selectedIndex = max(selectedIndex - 1, 0)
            refreshSuggestions()
            return true
        case 36, 48: // Return, Tab
            guard suggestionWindowController.isVisible, let snippet = selectedSnippet else { return false }
            expand(snippet)
            return true
        case 51: // Backspace
            guard let activeQuery else { return false }
            if activeQuery.isEmpty {
                cancelSession()
            } else {
                self.activeQuery = String(activeQuery.dropLast())
                refreshSuggestionsAsync()
            }
            return false
        default:
            return false
        }
    }
    
    private func processTextKey(_ event: NSEvent) {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        let characters = event.characters ?? ""
        
        if characters == ":" && disallowedModifiers.isEmpty {
            activeQuery = ""
            matches = []
            selectedIndex = 0
            suggestionWindowController.hide()
            return
        }
        
        guard let activeQuery else { return }
        
        if !disallowedModifiers.isEmpty {
            cancelSession()
            return
        }
        
        let normalizedCharacters = Snippet.normalizeTrigger(characters)
        if normalizedCharacters.count == 1, let scalar = normalizedCharacters.first {
            self.activeQuery = activeQuery + String(scalar)
            refreshSuggestionsAsync()
            return
        }
        
        cancelSession()
    }
    
    private func refreshSuggestionsAsync() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshSuggestions()
        }
    }
    
    private func refreshSuggestions() {
        guard let activeQuery else {
            suggestionWindowController.hide()
            return
        }
        
        matches = Array(store.matches(for: activeQuery).prefix(5))
        if selectedIndex >= matches.count {
            selectedIndex = max(0, matches.count - 1)
        }
        
        guard !activeQuery.isEmpty, !matches.isEmpty else {
            suggestionWindowController.hide()
            return
        }
        
        let anchorRect = caretRect() ?? fallbackAnchorRect()
        suggestionWindowController.show(snippets: matches, selectedIndex: selectedIndex, anchorRect: anchorRect)
    }
    
    private func cancelSession() {
        activeQuery = nil
        matches = []
        selectedIndex = 0
        suggestionWindowController.hide()
    }
    
    private var isSessionActive: Bool {
        activeQuery != nil
    }
    
    private var selectedSnippet: Snippet? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex]
    }
    
    private func expand(_ snippet: Snippet) {
        let deleteCount = (activeQuery?.count ?? 0) + 1
        cancelSession()
        deleteTypedTrigger(characterCount: deleteCount)
        insertText(snippet.content)
    }
    
    private func deleteTypedTrigger(characterCount: Int) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        for _ in 0..<characterCount {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
            keyDown?.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
            keyUp?.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
    
    private func insertText(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let utf16 = Array(text.utf16)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown?.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
    
    private func caretRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }
        
        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedRangeRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
              let selectedRangeRef,
              CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() else {
            return nil
        }
        
        let rangeValue = selectedRangeRef as! AXValue
        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectedRange) else {
            return nil
        }
        
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success,
        let boundsRef,
        CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }
        
        let boundsValue = boundsRef as! AXValue
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &bounds) else {
            return nil
        }
        
        return bounds
    }
    
    private func fallbackAnchorRect() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        return CGRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1)
    }
}

@MainActor
private final class SnippetSuggestionWindowController: NSWindowController {
    private let hostingView = NSHostingView(rootView: SnippetSuggestionListView(snippets: [], selectedIndex: 0))
    
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.contentView = hostingView
        
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    func show(snippets: [Snippet], selectedIndex: Int, anchorRect: CGRect) {
        hostingView.rootView = SnippetSuggestionListView(snippets: snippets, selectedIndex: selectedIndex)
        
        let width: CGFloat = 300
        let rowHeight: CGFloat = 44
        let padding: CGFloat = 14
        let height = CGFloat(snippets.count) * rowHeight + padding
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        
        window?.setContentSize(contentRect.size)
        
        let preferredOrigin = preferredOrigin(for: anchorRect, popupSize: contentRect.size)
        window?.setFrameOrigin(preferredOrigin)
        window?.orderFrontRegardless()
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    private func preferredOrigin(for anchorRect: CGRect, popupSize: CGSize) -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        
        var x = anchorRect.minX
        var y = anchorRect.minY - popupSize.height - 8
        
        if y < visibleFrame.minY + 8 {
            y = anchorRect.maxY + 8
        }
        
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - popupSize.width - 8)
        y = min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - popupSize.height - 8)
        
        return CGPoint(x: x, y: y)
    }
}

private struct SnippetSuggestionListView: View {
    let snippets: [Snippet]
    let selectedIndex: Int
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(snippet.content)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Text(":\(snippet.trigger)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(index == selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                )
            }
        }
        .padding(7)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
