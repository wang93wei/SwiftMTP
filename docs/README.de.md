# SwiftMTP

<div align="center">

<img src="../SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**Natives macOS Android MTP-Dateiübertragungstool**

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)

</div>

---

**🌍 Sprachen:** [English](README.md) | [简体中文](docs/README.zh-CN.md) | [日本語](docs/README.ja.md) | [한국어](docs/README.ko.md) | [Русский](docs/README.ru.md) | [Français](docs/README.fr.md) | [Deutsch](docs/README.de.md)

---

## ✨ Funktionen

| Funktion | Beschreibung |
|----------|-------------|
| 🔌 **Automatische Geräteerkennung** | Erkennt automatisch verbundene Android-Geräte |
| 📁 **Dateibrowser** | Flüssige Navigation im Dateisystem des Geräts |
| ⬇️ **Dateidownload** | Unterstützt Einzel- und Batch-Dateidownloads |
| ⬆️ **Dateiupload** | Unterstützt Button-Auswahl und Drag-and-Drop für Dateiuploads |
| 💾 **Unterstützung großer Dateien** | Unterstützt Übertragung von Dateien >4 GB |
| 📦 **Batch-Operationen** | Batch-Auswahl und -verarbeitung von Dateien |
| 🎨 **Moderne Benutzeroberfläche** | Schöne SwiftUI-Oberfläche |
| 📊 **Speicherinformationen** | Zeigt die Speichernutzung des Geräts an |
| 🌍 **Mehrsprachig** | Unterstützt vereinfachtes Chinesisch, Englisch, Japanisch, Koreanisch, Russisch, Französisch, Deutsch, folgt der Systemsprache |

## 📸 App-Screenshots

| Hauptoberfläche | Dateiübertragung |
|:---:|:---:|
| ![Hauptoberfläche](cap_2025-12-24%2005.29.36.png) | ![Dateiübertragung](cap_2026-02-21%2023.30.24.png) |

## 🚀 Schnellstart

### Anforderungen

| Abhängigkeit | Version |
|--------------|---------|
| macOS | 26.0+ (oder höher) |
| Xcode | 26.0+ |
| Homebrew | Neueste Version |

### Abhängigkeiten installieren

```bash
brew install go
```

> 📝 **Hinweis**: libusb-1.0 ist jetzt in der Anwendung enthalten, keine manuelle Installation erforderlich.

### Kompilieren und Ausführen

```bash
# Repository klonen
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# Go-Brücke kompilieren
./Scripts/build_kalam.sh

# In Xcode öffnen und ausführen
open SwiftMTP.xcodeproj
```

> 📝 **Hinweis**: Die Projektkonfigurationsdateien wurden in die Versionskontrolle übernommen. Nach dem Klonen können Sie das Projekt einfach in Xcode öffnen und ohne zusätzliche Konfiguration mit dem Erstellen beginnen.

> 💡 **Tipp**: Nachdem Sie Ihr Android-Gerät verbunden haben, wählen Sie auf dem Gerät den **Dateiübertragungsmodus (MTP)**, um zu beginnen.

### Installationspaket erstellen

```bash
# Vereinfachtes Paketieren (kein Entwicklerzertifikat erforderlich)
./Scripts/create_dmg_simple.sh

# Vollständiges Paketieren (erfordert Entwicklerzertifikat)
./Scripts/create_dmg.sh
```

Die DMG-Datei wird im Verzeichnis `build/` erstellt.

## 📖 Benutzerhandbuch

### Gerät verbinden

1. Verbinden Sie Ihr Android-Gerät über USB mit dem Mac
2. Wählen Sie auf dem Gerät den **Dateiübertragungsmodus (MTP)**
3. SwiftMTP erkennt und zeigt das Gerät automatisch an

### Dateioperationen

| Vorgang | Methode |
|---------|---------|
| Dateien durchsuchen | Doppelklick auf Ordner zum Öffnen, Brotkrümel-Navigation zum Zurückkehren |
| Datei herunterladen | Rechtsklick auf Datei → **Herunterladen** |
| Batch-Download | Mehrfachauswahl → Rechtsklick → **Ausgewählte Dateien herunterladen** |
| Datei hochladen | Klicken Sie auf die Schaltfläche **Datei hochladen** in der Symbolleiste oder ziehen Sie Dateien in das Fenster |
| Drag-and-Drop-Upload | Ziehen Sie Dateien in das Dateibrowser-Fenster, um sie hochzuladen |

### Spracheinstellungen

1. Öffnen Sie das Fenster **Einstellungen** (⌘ + ,)
2. Wählen Sie die Sprache im Tab **Allgemein**
3. Verfügbare Sprachen:
   - **Systemstandard** - Folgt der macOS-Sprache
   - **English** - Englische Benutzeroberfläche
   - **中文** - Vereinfachte chinesische Benutzeroberfläche
   - **日本語** - Japanische Benutzeroberfläche
   - **한국어** - Koreanische Benutzeroberfläche
   - **Русский** - Russische Benutzeroberfläche
   - **Français** - Französische Benutzeroberfläche
   - **Deutsch** - Deutsche Benutzeroberfläche
4. Die App-Benutzeroberfläche aktualisiert die Sprache sofort
5. **Menüleiste und Dateiauswahl** erfordern einen Neustart der App, um wirksam zu werden, das System fordert einen sofortigen Neustart

## 🏗️ Projektarchitektur

```
SwiftMTP/
├── Native/                         # Go-Brücke (Kalam Kernel)
│   ├── kalam_*.go                 # Aufgeteilte Brückenmodule (CGO)
│   ├── *_test.go                  # Go-Unit-Tests pro Modul
│   ├── libkalam.h                 # C-Header (Swift-Brücke)
│   ├── go.mod / go.sum            # Go-Modul-Abhängigkeiten
│   └── vendor/                    # Go-Abhängigkeiten (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # Go-Dynamic-Library kompilieren
│   ├── create_dmg.sh              # DMG-Packaging-Skript
│   ├── create_dmg_simple.sh       # Vereinfachtes Packaging
│   ├── generate_icons.sh          # Symbol-Generierungs-Skript
│   ├── run_tests.sh               # Test-Ausführungs-Skript
│   └── SwiftMTP/                  # Ressourcen-Skripte
│       └── App/Assets.xcassets/   # App-Symbol-Ressourcen
├── SwiftMTP/                      # Swift-Anwendung
│   ├── App/                       # App-Einstieg
│   │   ├── SwiftMTPApp.swift      # App-Einstiegspunkt
│   │   ├── Info.plist             # App-Konfiguration
│   │   ├── Assets.xcassets/       # Ressourcen-Bundle (Symbole)
│   │   └── Resources/             # App-Ressourcen
│   │       └── SwiftMTP_Logo.svg  # App-Logo
│   ├── Models/                    # Datenmodelle
│   │   ├── Device.swift           # Gerät-Modell
│   │   ├── FileItem.swift         # Datei-Modell
│   │   ├── TransferTask.swift     # Übertragungsaufgaben-Modell
│   │   ├── AppLanguage.swift      # Sprach-Modell
│   │   ├── AppError.swift         # Fehlertypdefinitionen
│   │   └── UpdateInfo.swift       # Update-Informationen Modell
│   ├── Services/                  # Service-Schicht
│   │   ├── MTP/                   # MTP-Services
│   │   │   ├── DeviceManager.swift    # Geräteverwaltung
│   │   │   ├── FileSystemManager.swift# Dateisystem
│   │   │   ├── FileTransferManager.swift # Übertragungsverwaltung
│   │   │   └── FileTransferManager+DirectoryUpload.swift # Verzeichnis-Upload-Erweiterung
│   │   ├── Protocols/             # Protokolldefinitionen
│   │   │   ├── DeviceManaging.swift
│   │   │   ├── FileSystemManaging.swift
│   │   │   ├── FileTransferManaging.swift
│   │   │   └── LanguageManaging.swift
│   │   ├── LanguageManager.swift  # Sprach-Manager
│   │   ├── LocalizationManager.swift # Lokalisierungs-Manager
│   │   └── UpdateChecker.swift    # Update-Prüfer
│   ├── Config/                    # Konfigurationsverwaltung
│   │   └── AppConfiguration.swift # Anwendungskonfigurationskonstanten
│   ├── Views/                     # SwiftUI-Ansichten
│   │   ├── MainWindowView.swift   # Hauptfenster
│   │   ├── DeviceListView.swift   # Geräteliste
│   │   ├── FileBrowserView.swift  # Dateibrowser
│   │   ├── FileBrowserView+Actions.swift # Dateibrowser-Aktionen
│   │   ├── FileBrowserView+ToolbarDrop.swift # Dateibrowser-Toolbar & Drag-and-drop
│   │   ├── TableDoubleClickModifier.swift # Tabellen-Doppelklick-Bridge
│   │   ├── FileTransferView.swift # Übertragungsansicht
│   │   ├── SettingsView.swift     # Einstellungsfenster
│   │   └── Components/            # Wiederverwendbare Komponenten
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # Ressourcendateien
│   │   ├── libkalam.dylib         # Go-Dynamic-Library (CGO-Bridge)
│   │   ├── Base.lproj/            # Basissprachpaket (Englisch)
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # Englisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # Chinesisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # Japanisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ko.lproj/              # Koreanisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ru.lproj/              # Russisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── fr.lproj/              # Französisches Sprachpaket
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── de.lproj/              # Deutsches Sprachpaket
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Go-Dynamic-Library
│   ├── libkalam.h                 # C-Header-Datei
│   └── SwiftMTP-Bridging-Header.h # Swift-C-Brücken-Header
├── docs/                          # Projektdokumentation
│   ├── sequence-diagrams.md       // Sequenzdiagramm-Dokumentation
│   ├── TESTING.md                 // Test-Dokumentation
│   └── WIKI.md                    // Projekt-Wiki
├── build/                         // Build-Ausgabeverzeichnis
├── .github/workflows/             // GitHub Actions
│   └── test.yml                   // CI-Test-Konfiguration
└── SwiftMTP.xcodeproj/            // Xcode-Projekt
```

### Technologiestack

- **Sprachen**: Swift 6+, Go 1.23+
- **UI-Framework**: SwiftUI
- **MTP-Bibliothek**: go-mtpx (basierend auf libusb-1.0)
- **Architektur-Muster**: MVVM
- **Brücken-Methode**: CGO
- **Internationalisierung**: Swift-Lokalisierungs-Framework (NSLocalizedString)

## ⚠️ Bekannte Einschränkungen

1. Sandbox muss deaktiviert sein, um auf USB-Geräte zuzugreifen
2. Übertragungsgeschwindigkeit ist durch MTP-Protokoll begrenzt
3. Derzeit wird nur der Upload einzelner Dateien unterstützt (Ordner-Upload wird nicht unterstützt)
4. Die Liquid Glass UI-Implementierung ist unvollständig und enthält Fehler, die behoben werden müssen
5. Wir begrüßen mehr Mitwirkende, die helfen, die Codebasis zu verbessern

## 🔧 Fehlerbehebung

### Gerät wird nicht erkannt

```
✓ Stellen Sie sicher, dass das Gerät im MTP-Modus ist
✓ Versuchen Sie, das USB-Kabel abzuziehen und wieder anzuschließen
✓ Starten Sie die App neu
✓ Überprüfen Sie, ob das USB-Kabel die Datenübertragung unterstützt
```

### Kompilierungsfehler

```bash
# Go-Brücke neu kompilieren
./Scripts/build_kalam.sh

# Bereinigen und neu kompilieren
xcodebuild clean
xcodebuild
```

## 🙏 Danksagungen

Dieses Projekt basiert auf dem Backend von [OpenMTP](https://github.com/ganeshrvel/openmtp). Besonderer Dank geht an das OpenMTP-Team für ihre hervorragende Arbeit an der MTP-Implementierung für macOS.

## 🤝 Beitrag

Issues und Pull Requests sind willkommen!

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die Datei [LICENSE](../LICENSE) für Details.

---

<div align="center">

**Wenn dieses Projekt Ihnen hilft, geben Sie bitte ⭐ Star zur Unterstützung!**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>
