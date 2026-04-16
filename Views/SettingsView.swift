import SwiftUI
import ApplicationServices

/// Settings view for configuring clippie preferences
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
        Form {
            keyboardSection
            systemSection
            snippetsSection
        }
        .formStyle(.grouped)
        .alert("Reduce History Retention?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    settings.historyLimit = tier
                    settings.save()
                }
            }
        } message: {
            Text("This will permanently delete clipboard history older than \(pendingTier?.label ?? "the selected period"). This action cannot be undone.")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var keyboardSection: some View {
        Section {
            LabeledContent("Shortcut") {
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Text(settings.hotkeyModifiers.displayString)
                        Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording
                                  ? Color.accentColor.opacity(0.1)
                                  : Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording
                                    ? Color.accentColor.opacity(0.7)
                                    : Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: isRecording)

                    Button(isRecording ? "Cancel" : "Change") {
                        isRecording.toggle()
                    }
                    .buttonStyle(.bordered)

                    if isRecording {
                        Text("Press shortcut...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Use Change to record a new keyboard shortcut.")
        }
    }
    
    private var systemSection: some View {
        Group {
            Section {
                accessibilityPermissionRow
            } header: {
                Text("Permissions")
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        SettingsManager.shared.toggleLaunchAtLogin(newValue)
                        DispatchQueue.main.async {
                            settings.launchAtLogin = SettingsManager.shared.launchAtLogin
                        }
                    }

                Picker("Keep history", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .onChange(of: settings.historyLimit) { newValue in
                    if newValue.rawValue < SettingsManager.shared.historyLimit.rawValue {
                        pendingTier = newValue
                        settings.historyLimit = SettingsManager.shared.historyLimit
                        showingTrimAlert = true
                    } else {
                        settings.historyLimit = newValue
                        settings.save()
                    }
                }
            } header: {
                Text("System")
            } footer: {
                Text("Choose how long clipboard history should be kept.")
            }
        }
    }

    private var accessibilityPermissionRow: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if !accessibilityPermission.isTrusted {
                    Button("Request") {
                        accessibilityPermission.requestAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Refresh") {
                        accessibilityPermission.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Open Settings") {
                    accessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                    Text(accessibilityPermission.isTrusted ? "Granted" : "Not granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Circle()
                    .fill(accessibilityPermission.isTrusted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private var snippetsSection: some View {
        Section {
            HStack {
                Spacer()
                Button {
                    editingSnippet = SnippetDraft()
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if snippetStore.snippets.isEmpty {
                Text("No snippets yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snippetStore.snippets) { snippet in
                    snippetRow(snippet)
                }
            }
        } header: {
            Text("Snippets")
        } footer: {
            Text("Type : in any text field to search and insert snippets.")
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(":\(snippet.trigger)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(snippet.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Edit") {
                    editingSnippet = SnippetDraft(snippet: snippet)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    snippetStore.deleteSnippet(id: snippet.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
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
            return "Granted. clippie can monitor and control text input where needed."
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
