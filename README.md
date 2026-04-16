<p align="center">
  <img src="Assets/Buffer-Logo.png" alt="clippie logo" width="128" height="128">
</p>

<h1 align="center">clippie</h1>

<p align="center">
  <strong>A lightweight, beautiful clipboard manager for macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/latest">
    <img src="https://img.shields.io/badge/Download-v1.0-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
  <img src="https://img.shields.io/badge/macOS-13.0+-black?style=for-the-badge&logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift 5.9">
  <a href="https://deepwiki.com/samirpatil2000/Buffer"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

---

### ✨ Why clippie?
- **Ultra-lightweight** — Only ~2 MB download/install, minimal RAM/CPU usage
- **100% Private & Local** — Everything stays on your Mac, no cloud, no tracking
- **Text + Images + OCR** — Copies anything; extracts searchable text from images/screenshots/memes using on-device Vision
- **Great for developers** — Handles large text snippets, JSON payloads, logs, and other verbose content with ease
- **Instant Access** — Global hotkey ⌥/ opens history in a flash
- **Native macOS Feel** — Clean SwiftUI + AppKit menu-bar app
- **Open Source** — MIT license, actively maintained

---


### 📥 Download

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v1.6/Buffer_Release.dmg">
    <img src="https://img.shields.io/badge/⬇️_Download_Buffer.dmg-v1.6-2ea44f?style=for-the-badge" alt="Download Buffer.dmg">
  </a>
</p>

1. Download the `.dmg` from the latest release
2. Drag **clippie.app** to your **Applications** folder
3. Launch it (lives in menu bar)
4. **Note (not yet notarized)**: Right-click → Open → confirm in security dialog

---

## 🚀 Getting Started

1. **Download** the `.dmg` file from above
2. **Drag** clippie to your Applications folder
3. **Launch** clippie — it will appear in your menu bar
4. **Copy** anything — clippie automatically saves it
5. Press **⌥/** to access your clipboard history anytime!

---

## 🖥️ Screenshots

<p align="center">
  <img width="919" height="864" alt="image" src="https://github.com/user-attachments/assets/ebd0d454-8362-45e4-af22-27f054ba43c6" />
</p>


<p align="center">
  <em>Beautiful split-pane interface with search and preview</em>
</p>

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥/` | Open clipboard history |
| `↑` / `↓` | Navigate items |
| `↵` Enter | Paste selected item |
| `⎋` Esc | Close history window |

---

## 🛠️ Building from Source

```bash
# Clone the repository
git clone https://github.com/samirpatil2000/Buffer.git
cd clippie

# Compile the app with Swift Package Manager
swift build

# Build a signed release app bundle
./scripts/build-release.sh

# Or build, verify, install to /Applications, and open it
./scripts/release-local.sh
```

The canonical build artifact is `build/Release/Clippie.app`.

### Requirements
- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9

---

## 📁 Project Structure

```
clippie/
├── ClippieApp.swift         # App entry point
├── AppDelegate.swift        # App lifecycle & hotkey setup
├── Models/
│   └── ClipboardItem.swift  # Clipboard item data model
├── Services/
│   ├── ClipboardStore.swift    # Persistent storage
│   ├── ClipboardWatcher.swift  # Monitors clipboard changes
│   ├── HotkeyManager.swift     # Global keyboard shortcuts
│   └── PasteController.swift   # Paste functionality
└── Views/
    ├── HistoryWindow.swift      # Main history window
    ├── ClipboardListView.swift  # List of clipboard items
    ├── ClipboardItemRow.swift   # Individual item row
    ├── SearchField.swift        # Search component
    └── StatusBarController.swift # Menu bar controller
```

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

---

## 📄 License

MIT License — feel free to use this project however you like.

---

<p align="center">
  Made with ❤️ for macOS
</p>
