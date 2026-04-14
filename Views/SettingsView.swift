import SwiftUI
import ApplicationServices

/// Settings view for configuring Buffer preferences
struct SettingsView: View {
    @StateObject private var settings = SettingsViewModel()
    @StateObject private var snippetStore = SnippetStore.shared
    @StateObject private var accessibilityPermission = AccessibilityPermissionViewModel()
    @State private var isRecording = false
    @State private var recordedKeyCode: UInt16 = 0
    @State private var recordedModifiers = HotkeyModifiers()
    @State private var showingTrimAlert = false
    @State private var pendingTier: HistoryLimit?
    @State private var editingSnippet: SnippetDraft?
    @State private var snippetErrorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingsCard { keyboardSection }
            settingsCard { systemSection }
            settingsCard { snippetsSection }
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    settings.historyLimit = tier
                    settings.save()
                }
            }
        } message: {
            Text("This will permanently delete your oldest items to fit the new size. This action cannot be undone.")
        }
        .alert("Snippet", isPresented: Binding(
            get: { snippetErrorMessage != nil },
            set: { if !$0 { snippetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(snippetErrorMessage ?? "")
        }
        .sheet(item: $editingSnippet) { draft in
            SnippetEditorSheet(draft: draft) { updatedDraft in
                saveSnippetDraft(updatedDraft)
            }
        }
        .background(KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
            settings.save()
            isRecording = false
        })
        .onAppear {
            accessibilityPermission.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityPermission.refresh()
        }
        .frame(width: 460, height: 660)
    }
    
    private func presetButton(label: String, mods: HotkeyModifiers, keyCode: UInt16) -> some View {
        Button(action: {
            settings.hotkeyModifiers = mods
            settings.hotkeyKeyCode = keyCode
            settings.save()
        }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("cliphis Settings")
                    .font(.system(size: 17, weight: .semibold))
                Text("Shortcuts, history, and snippets")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Keyboard Shortcut")
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text(settings.hotkeyModifiers.displayString)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                    Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.16) : Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isRecording ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                Button(action: { isRecording.toggle() }) {
                    Text(isRecording ? "Cancel" : "Change")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            
            if isRecording {
                Text("Press your new shortcut...")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("System")
            
            accessibilityPermissionRow
            
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .onChange(of: settings.launchAtLogin) { newValue in
                        SettingsManager.shared.toggleLaunchAtLogin(newValue)
                        DispatchQueue.main.async {
                            settings.launchAtLogin = SettingsManager.shared.launchAtLogin
                        }
                    }
                    .toggleStyle(.switch)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("History Size")
                
                HStack(spacing: 12) {
                    ForEach(HistoryLimit.allCases, id: \.self) { tier in
                        Button(action: {
                            if tier.rawValue < settings.historyLimit.rawValue {
                                pendingTier = tier
                                showingTrimAlert = true
                            } else {
                                settings.historyLimit = tier
                                settings.save()
                            }
                        }) {
                            VStack(alignment: .center, spacing: 6) {
                                Image(systemName: settings.historyLimit == tier ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(settings.historyLimit == tier ? .accentColor : .secondary.opacity(0.3))
                                    .font(.system(size: 14))
                                
                                Text(tier.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(settings.historyLimit == tier ? .primary : .secondary)
                                
                                Text(tier.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(settings.historyLimit == tier
                                          ? Color.accentColor.opacity(0.1)
                                          : Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(settings.historyLimit == tier
                                            ? Color.accentColor.opacity(0.9)
                                            : Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var accessibilityPermissionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: accessibilityPermission.isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accessibilityPermission.isTrusted ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission")
                        .font(.system(size: 13, weight: .medium))
                    Text(accessibilityPermission.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button(accessibilityPermission.isTrusted ? "Refresh" : "Request Access") {
                    if accessibilityPermission.isTrusted {
                        accessibilityPermission.refresh()
                    } else {
                        accessibilityPermission.requestAccess()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open System Settings") {
                    accessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Snippets")
                Spacer()
                Button(action: {
                    editingSnippet = SnippetDraft()
                }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            
            Text("Search with `:` in the clipboard window to show snippets.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            if snippetStore.snippets.isEmpty {
                Text("No snippets yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 10) {
                        ForEach(snippetStore.snippets) { snippet in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snippet.displayTitle)
                                        .font(.system(size: 12, weight: .semibold))
                                    
                                    Text(":\(snippet.trigger)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Text(snippet.content)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button("Edit") {
                                    editingSnippet = SnippetDraft(snippet: snippet)
                                }
                                .buttonStyle(.borderless)
                                
                                Button(role: .destructive) {
                                    snippetStore.deleteSnippet(id: snippet.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(NSColor.windowBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 150, maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
    }
    
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
    
    private func saveSnippetDraft(_ draft: SnippetDraft) -> Bool {
        do {
            try snippetStore.saveSnippet(
                id: draft.snippetID,
                title: draft.title,
                trigger: draft.trigger,
                content: draft.content
            )
            return true
        } catch {
            snippetErrorMessage = error.localizedDescription
            return false
        }
    }
}

/// Records keyboard shortcuts when active
struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (UInt16, HotkeyModifiers) -> Void
    
    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = onRecord
        return view
    }
    
    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        nsView.updateWindowLevel()
        
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeKeyAndOrderFront(nil)
                nsView.window?.makeFirstResponder(nsView)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

class KeyRecorderView: NSView {
    var isRecording = false
    var onRecord: ((UInt16, HotkeyModifiers) -> Void)?
    private var previousWindowLevel: NSWindow.Level?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            // Use a tiny delay to allow the window to be properly added to the window list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.isRecording {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
    
    func updateWindowLevel() {
        guard let window else { return }
        
        if isRecording {
            if previousWindowLevel == nil {
                previousWindowLevel = window.level
            }
            window.level = .floating
        } else if let previousWindowLevel {
            window.level = previousWindowLevel
            self.previousWindowLevel = nil
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        
        // Ignore modifier-only presses
        if event.keyCode == 56 || event.keyCode == 59 || event.keyCode == 58 || event.keyCode == 55 {
            return
        }
        
        let mods = HotkeyModifiers(
            shift: event.modifierFlags.contains(.shift),
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
        
        // Require at least one modifier
        if mods.shift || mods.command || mods.option || mods.control {
            onRecord?(event.keyCode, mods)
        }
    }
}

/// ViewModel wrapper for SettingsManager to avoid crashes
class SettingsViewModel: ObservableObject {
    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published var launchAtLogin: Bool
    @Published var historyLimit: HistoryLimit
    
    init() {
        self.hotkeyModifiers = SettingsManager.shared.hotkeyModifiers
        self.hotkeyKeyCode = SettingsManager.shared.hotkeyKeyCode
        self.launchAtLogin = SettingsManager.shared.launchAtLogin
        self.historyLimit = SettingsManager.shared.historyLimit
    }
    
    func save() {
        SettingsManager.shared.hotkeyModifiers = hotkeyModifiers
        SettingsManager.shared.hotkeyKeyCode = hotkeyKeyCode
        SettingsManager.shared.historyLimit = historyLimit
        SettingsManager.shared.save()
        
        NotificationCenter.default.post(name: .bufferHotkeyChanged, object: nil)
        NotificationCenter.default.post(name: .bufferHistoryLimitChanged, object: nil)
    }
}

@MainActor
final class AccessibilityPermissionViewModel: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    
    var statusText: String {
        if isTrusted {
            return "Granted. cliphis can monitor and control text input where needed."
        }
        return "Not granted. Needed for Accessibility-based input features."
    }
    
    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }
    
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refresh()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.refresh()
        }
    }
    
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        
        NSWorkspace.shared.open(url)
    }
}

private struct SnippetDraft: Identifiable {
    let id = UUID()
    var snippetID: UUID?
    var title: String
    var trigger: String
    var content: String
    
    init(snippetID: UUID? = nil, title: String = "", trigger: String = "", content: String = "") {
        self.snippetID = snippetID
        self.title = title
        self.trigger = trigger
        self.content = content
    }
    
    init(snippet: Snippet? = nil) {
        self.snippetID = snippet?.id
        self.title = snippet?.title ?? ""
        self.trigger = snippet?.trigger ?? ""
        self.content = snippet?.content ?? ""
    }
}

private struct SnippetEditorSheet: View {
    let draft: SnippetDraft
    let onSave: (SnippetDraft) -> Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var trigger: String
    @State private var content: String
    
    init(draft: SnippetDraft, onSave: @escaping (SnippetDraft) -> Bool) {
        self.draft = draft
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _trigger = State(initialValue: draft.trigger)
        _content = State(initialValue: draft.content)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.snippetID == nil ? "Add Snippet" : "Edit Snippet")
                .font(.system(size: 15, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Label (optional)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Personal IBAN", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("iban", text: $trigger)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    let didSave = onSave(
                        SnippetDraft(
                            snippetID: draft.snippetID,
                            title: title,
                            trigger: trigger,
                            content: content
                        )
                    )
                    if didSave {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
