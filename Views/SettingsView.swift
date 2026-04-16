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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                settingsDivider

                settingsSection { keyboardSection }
                settingsDivider
                settingsSection { systemSection }
                settingsDivider
                settingsSection { snippetsSection }
                    .frame(maxHeight: .infinity, alignment: .top)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    // Thin hairline between sections — replaces card borders with breathing room
    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "scissors")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            Text("clippie")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text("Settings")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)

            Spacer()
        }
    }
    
    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Keyboard Shortcut")

            HStack(spacing: 10) {
                // Current shortcut key cap display
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

                Button(action: { isRecording.toggle() }) {
                    Text(isRecording ? "Cancel" : "Change")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                if isRecording {
                    Text("Press shortcut…")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .transition(.opacity)
                }

                Spacer()
            }
        }
    }
    
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("System")

            accessibilityPermissionRow

            // Hairline separator within section
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)

            // Launch at Login toggle row
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Launch at Login")
                        .font(.system(size: 13))
                    Text("Open clippie automatically when you log in")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
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

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)

            historySizeRow
        }
    }

    private var historySizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("History Retention")

            // Compact segmented-style row: each tier is an equal-width button
            HStack(spacing: 6) {
                ForEach(HistoryLimit.allCases, id: \.self) { tier in
                    let isSelected = settings.historyLimit == tier
                    Button(action: {
                        if tier.rawValue < settings.historyLimit.rawValue {
                            pendingTier = tier
                            showingTrimAlert = true
                        } else {
                            settings.historyLimit = tier
                            settings.save()
                        }
                    }) {
                        VStack(spacing: 3) {
                            Text(tier.label)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .accentColor : .primary)
                            Text(tier.subtitle)
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? .accentColor.opacity(0.7) : .secondary)
                        }
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected
                                      ? Color.accentColor.opacity(0.1)
                                      : Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isSelected
                                        ? Color.accentColor.opacity(0.55)
                                        : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                }
            }
        }
    }

    private var accessibilityPermissionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status dot — compact, not oversized
            Circle()
                .fill(accessibilityPermission.isTrusted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility")
                    .font(.system(size: 13))
                Text(accessibilityPermission.isTrusted
                     ? "Granted"
                     : "Not granted — required for text input features")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

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
    }
    
    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Snippets")
                    Text("Type : in any text field to search and insert snippets.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { editingSnippet = SnippetDraft() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if snippetStore.snippets.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 22, weight: .thin))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No snippets yet")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
            } else {
                // Flat list with hairline separators — no individual card borders
                VStack(spacing: 0) {
                    ForEach(Array(snippetStore.snippets.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 1)
                                .padding(.leading, 10)
                        }
                        snippetRow(snippet)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Trigger badge
            Text(":\(snippet.trigger)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
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
            .foregroundColor(.accentColor)
            .font(.system(size: 12))
            .controlSize(.small)

            Button(role: .destructive) {
                snippetStore.deleteSnippet(id: snippet.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
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
