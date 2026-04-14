import Cocoa

/// Handles pasting content into the frontmost application
class PasteController {
    private static let pasteDelay: TimeInterval = 0.12

    static func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Copy item content back to system clipboard
    static func copyToClipboard(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            // Use full text from file if file-backed, otherwise use inline content
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
    }
    
    /// Paste item into the frontmost application
    static func paste(
        _ item: ClipboardItem,
        store: ClipboardStore,
        targetApplication: NSRunningApplication? = nil
    ) {
        // First copy to clipboard
        copyToClipboard(item, store: store)

        prepareAndSimulatePaste(into: targetApplication)
    }
    
    static func paste(text: String, targetApplication: NSRunningApplication? = nil) {
        copyTextToClipboard(text)

        prepareAndSimulatePaste(into: targetApplication)
    }

    private static func prepareAndSimulatePaste(into targetApplication: NSRunningApplication?) {
        if let targetApplication,
           !targetApplication.isTerminated,
           targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
        }

        // Give the pasteboard and target app a brief moment to settle before posting Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            simulatePaste()
        }
    }
    
    /// Simulate Command + V keystroke
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        
        // Add Command modifier
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        // Post the events
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
