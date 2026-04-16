import AppKit
import Combine
import SwiftUI

enum ClippieSettingsTab: String, CaseIterable {
    case general
    case about

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    var label: String {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let mainViewModel = ClippieSettingsMainViewModel()
    private var tabSubscription: AnyCancellable?

    init() {
        let rootView = ClippieSettingsRootView(mainViewModel: mainViewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clippie"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = nil

        super.init(window: window)

        window.delegate = self

        let toolbar = NSToolbar(identifier: "ClippieSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = mainViewModel.selectedTab.toolbarIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        tabSubscription = mainViewModel.$selectedTab.sink { [weak toolbar] tab in
            toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        updateActivationPolicy(forSettingsWindowIsOpen: true)
        let shouldCenterWindow = window?.isVisible != true
        showWindow(nil)
        if shouldCenterWindow {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        updateActivationPolicy(forSettingsWindowIsOpen: false)
    }

    private func updateActivationPolicy(forSettingsWindowIsOpen isOpen: Bool) {
        let policy: NSApplication.ActivationPolicy = isOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else {
            return
        }

        NSApp.setActivationPolicy(policy)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = ClippieSettingsTab(rawValue: sender.itemIdentifier.rawValue) else {
            return
        }

        mainViewModel.selectedTab = tab
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ClippieSettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ClippieSettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ClippieSettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = ClippieSettingsTab(rawValue: itemIdentifier.rawValue) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}

@MainActor
private final class ClippieSettingsMainViewModel: ObservableObject {
    @Published var selectedTab: ClippieSettingsTab = .general
}

private struct ClippieSettingsRootView: View {
    @ObservedObject var mainViewModel: ClippieSettingsMainViewModel

    var body: some View {
        Group {
            switch mainViewModel.selectedTab {
            case .general:
                SettingsView()
            case .about:
                ClippieAboutSettingsView()
            }
        }
        .frame(minWidth: 520, minHeight: 700)
    }
}

private struct ClippieAboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Clippie")
                        .font(.title2.weight(.semibold))

                    Text("A clipboard manager with snippets and quick history for macOS.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
