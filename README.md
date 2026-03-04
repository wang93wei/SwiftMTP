# SwiftMTP

<div align="center">

<img src="SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**Native macOS Android MTP File Transfer Tool**

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

**🌍 Languages:** [English](README.md) | [简体中文](docs/README.zh-CN.md) | [日本語](docs/README.ja.md) | [한국어](docs/README.ko.md) | [Русский](docs/README.ru.md) | [Français](docs/README.fr.md) | [Deutsch](docs/README.de.md)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔌 **Auto Device Detection** | Automatically detect connected Android devices |
| 📁 **File Browsing** | Smoothly browse device file system |
| ⬇️ **File Download** | Support single and batch file downloads |
| ⬆️ **File Upload** | Support button selection and drag-and-drop file uploads |
| 💾 **Large File Support** | Support >4GB file transfers |
| 📦 **Batch Operations** | Batch select and process files |
| 🎨 **Modern UI** | Beautiful SwiftUI interface |
| 📊 **Storage Info** | Display device storage usage |
| 🌍 **Multi-language Support** | Support English, Simplified Chinese, Japanese, Korean, Russian, French, German, follows system language |

## 📸 App Screenshots

| Main Interface | File Transfer |
|:---:|:---:|
| ![Main Interface](docs/cap_2025-12-24%2005.29.36.png) | ![File Transfer](docs/cap_2026-02-21%2023.30.24.png) |

## 🚀 Quick Start

### Requirements

| Dependency | Version |
|------------|---------|
| macOS | 26.0+ (or higher) |
| Xcode | 26.0+ |
| Homebrew | Latest version |

### Install Dependencies

```bash
brew install go
```

> 📝 **Note**: libusb-1.0 is now bundled with the application, so no manual installation is required.

### Build and Run

```bash
# Clone the repository
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# Build Go bridge layer
./Scripts/build_kalam.sh

# Open in Xcode and run
open SwiftMTP.xcodeproj
```

> 📝 **Note**: Project configuration files have been committed to version control. After cloning, simply open the project in Xcode and start building without any additional configuration.

> 💡 **Tip**: After connecting your Android device, select **File Transfer (MTP)** mode on the device to start using.

### Create Installation Package

```bash
# Simplified packaging (no developer certificate required)
./Scripts/create_dmg_simple.sh

# Full packaging (requires developer certificate)
./Scripts/create_dmg.sh
```

The DMG file will be generated in the `build/` directory.

## 📖 User Guide

### Connecting a Device

1. Connect your Android device to Mac via USB
2. Select **File Transfer (MTP)** mode on the device
3. SwiftMTP will automatically detect and display the device

### File Operations

| Operation | Method |
|-----------|--------|
| Browse files | Double-click folders to enter, use breadcrumb navigation to go back |
| Download file | Right-click file → **Download** |
| Batch download | Multi-select files → Right-click → **Download Selected Files** |
| Upload file | Click **Upload File** button in toolbar or drag-drop files to window |
| Drag-and-drop upload | Drag files to file browser window to upload |

### Language Settings

1. Open **Settings** window (⌘ + ,)
2. Select language in **General** tab
3. Available languages:
   - **System Default** - Follow macOS system language
   - **English** - English interface
   - **Simplified Chinese** - Simplified Chinese interface
   - **Japanese** - Japanese interface
   - **Korean** - Korean interface
   - **Russian** - Russian interface
   - **French** - French interface
   - **German** - German interface
4. In-app interface will update language immediately
5. **Menu bar and file pickers** require app restart to take effect, system will prompt for immediate restart

## 🏗️ Project Architecture

```
SwiftMTP/
├── Native/                         # Go bridge layer (Kalam Kernel)
│   ├── kalam_*.go                 # Split bridge modules (CGO)
│   ├── *_test.go                  # Go unit tests by module
│   ├── libkalam.h                 # C header (Swift bridging)
│   ├── go.mod / go.sum            # Go module dependencies
│   └── vendor/                    # Go dependencies (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # Build Go dynamic library
│   ├── create_dmg.sh              # DMG packaging script
│   ├── create_dmg_simple.sh       # Simplified packaging
│   ├── generate_icons.sh          # Icon generation script
│   ├── run_tests.sh               # Test running script
│   └── SwiftMTP/                  # Resource scripts
│       └── App/Assets.xcassets/   # App icon resources
├── SwiftMTP/                      # Swift application
│   ├── App/                       # App entry
│   │   ├── SwiftMTPApp.swift      # App entry point
│   │   ├── Info.plist             # App configuration
│   │   ├── Assets.xcassets/       # Asset bundle (icons)
│   │   └── Resources/             # App resources
│   │       └── SwiftMTP_Logo.svg  # App Logo
│   ├── Models/                    # Data models
│   │   ├── Device.swift           # Device model
│   │   ├── FileItem.swift         # File model
│   │   ├── TransferTask.swift     # Transfer task model
│   │   ├── AppLanguage.swift      # Language model
│   │   ├── AppError.swift         # Error type definitions
│   │   └── UpdateInfo.swift       # Update information model
│   ├── Services/                  # Service layer
│   │   ├── MTP/                   # MTP services
│   │   │   ├── DeviceManager.swift    # Device management
│   │   │   ├── FileSystemManager.swift# File system
│   │   │   ├── FileTransferManager.swift # Transfer management
│   │   │   └── FileTransferManager+DirectoryUpload.swift # Directory upload extension
│   │   ├── Protocols/             # Protocol definitions
│   │   │   ├── DeviceManaging.swift
│   │   │   ├── FileSystemManaging.swift
│   │   │   ├── FileTransferManaging.swift
│   │   │   └── LanguageManaging.swift
│   │   ├── LanguageManager.swift  # Language manager
│   │   ├── LocalizationManager.swift # Localization manager
│   │   └── UpdateChecker.swift    # Update checker
│   ├── Config/                    # Configuration
│   │   └── AppConfiguration.swift # App configuration constants
│   ├── Views/                     # SwiftUI views
│   │   ├── MainWindowView.swift   # Main window
│   │   ├── DeviceListView.swift   # Device list
│   │   ├── FileBrowserView.swift  # File browser
│   │   ├── FileBrowserView+Actions.swift # File browser actions
│   │   ├── FileBrowserView+ToolbarDrop.swift # File browser toolbar & drag-drop
│   │   ├── TableDoubleClickModifier.swift # Table double-click bridge
│   │   ├── FileTransferView.swift # Transfer view
│   │   ├── SettingsView.swift     # Settings window
│   │   └── Components/            # Reusable components
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # Resource files
│   │   ├── libkalam.dylib         # Go dynamic library (CGO bridge)
│   │   ├── Base.lproj/            # Base language pack (English)
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # English language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # Simplified Chinese language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # Japanese language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ko.lproj/              # Korean language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ru.lproj/              # Russian language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── fr.lproj/              # French language pack
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── de.lproj/              # German language pack
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Go dynamic library
│   ├── libkalam.h                 # C header file
│   └── SwiftMTP-Bridging-Header.h # Swift-C bridging header
├── docs/                          # Project documentation
│   ├── sequence-diagrams.md       # Sequence diagram documentation
│   ├── TESTING.md                 # Testing documentation
│   └── WIKI.md                    # Project Wiki
├── build/                         # Build output directory
├── .github/workflows/             # GitHub Actions
│   └── test.yml                   # CI test configuration
└── SwiftMTP.xcodeproj/            # Xcode project
```

### Tech Stack

- **Languages**: Swift 6+, Go 1.23+
- **UI Framework**: SwiftUI
- **MTP Library**: go-mtpx (based on libusb-1.0)
- **Architecture Pattern**: MVVM
- **Bridging Method**: CGO
- **Internationalization**: Swift localization framework (NSLocalizedString)

## ⚠️ Known Limitations

1. Sandbox must be disabled to access USB devices
2. Transfer speed is limited by MTP protocol
3. Liquid Glass UI implementation is incomplete and contains bugs that need fixing
4. We welcome more contributors to help improve the codebase

## 🔧 Troubleshooting

### Device Not Detected

```
✓ Ensure device is in MTP mode
✓ Try unplugging and reconnecting USB cable
✓ Restart the app
✓ Check if USB cable supports data transfer
```

### Build Errors

```bash
# Rebuild Go bridge layer
./Scripts/build_kalam.sh

# Clean and rebuild
xcodebuild clean
xcodebuild
```

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📄 License

This project is licensed under MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**If this project helps you, please ⭐ Star to support!**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>
