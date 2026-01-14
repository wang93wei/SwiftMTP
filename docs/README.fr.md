# SwiftMTP

<div align="center">

<img src="../SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**Outil natif de transfert de fichiers MTP Android pour macOS**

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)

</div>

---

**🌍 Langues:** [English](../README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

---

## ✨ Fonctionnalités

| Fonctionnalité | Description |
|----------------|-------------|
| 🔌 **Détection automatique d'appareil** | Détecte automatiquement les appareils Android connectés |
| 📁 **Navigation de fichiers** | Navigation fluide dans le système de fichiers de l'appareil |
| ⬇️ **Téléchargement de fichiers** | Supporte le téléchargement de fichiers uniques et en lot |
| ⬆️ **Téléchargement de fichiers** | Supporte le téléchargement par sélection de bouton et par glisser-déposer |
| 💾 **Support des gros fichiers** | Supporte le transfert de fichiers >4 Go |
| 📦 **Opérations en lot** | Sélection et traitement en lot de fichiers |
| 🎨 **Interface moderne** | Belle interface SwiftUI |
| 📊 **Informations de stockage** | Affiche l'utilisation du stockage de l'appareil |
| 🌍 **Support multilingue** | Supporte le chinois simplifié, l'anglais, le japonais, le coréen, le russe, le français, l'allemand, suit la langue du système |

## 📸 Capture d'écran de l'application
![SwiftMTP Logo](../SwiftMTP/Resources/cap_2025-12-24%2005.29.36.png)

## 🚀 Démarrage rapide

### Prérequis

| Dépendance | Version |
|------------|---------|
| macOS | 26.0+ (ou supérieur) |
| Xcode | 26.0+ |
| Homebrew | Dernière version |

### Installation des dépendances

```bash
brew install libusb-1.0 go
```

### Compilation et exécution

```bash
# Cloner le dépôt
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# Compiler le pont Go
./Scripts/build_kalam.sh

# Ouvrir dans Xcode et exécuter
open SwiftMTP.xcodeproj
```

> 📝 **Remarque**: Les fichiers de configuration du projet ont été ajoutés au contrôle de version. Après le clonage, ouvrez simplement le projet dans Xcode et commencez à construire sans configuration supplémentaire.

> 💡 **Conseil**: Après avoir connecté votre appareil Android, sélectionnez le mode **Transfert de fichiers (MTP)** sur l'appareil pour commencer à l'utiliser.

### Création du paquet d'installation

```bash
# Empaquetage simplifié (pas de certificat de développeur requis)
./Scripts/create_dmg_simple.sh

# Empaquetage complet (nécessite un certificat de développeur)
./Scripts/create_dmg.sh
```

Le fichier DMG sera généré dans le répertoire `build/`.

## 📖 Guide de l'utilisateur

### Connexion d'un appareil

1. Connectez votre appareil Android au Mac via USB
2. Sélectionnez le mode **Transfert de fichiers (MTP)** sur l'appareil
3. SwiftMTP détectera automatiquement et affichera l'appareil

### Opérations sur les fichiers

| Opération | Méthode |
|-----------|---------|
| Naviguer dans les fichiers | Double-cliquez sur les dossiers pour entrer, utilisez la navigation par fil d'Ariane pour revenir |
| Télécharger un fichier | Clic droit sur le fichier → **Télécharger** |
| Téléchargement en lot | Sélection multiple → Clic droit → **Télécharger les fichiers sélectionnés** |
| Télécharger un fichier | Cliquez sur le bouton **Télécharger un fichier** dans la barre d'outils ou faites glisser les fichiers vers la fenêtre |
| Téléchargement par glisser-déposer | Faites glisser les fichiers vers la fenêtre du navigateur de fichiers pour les télécharger |

### Paramètres de langue

1. Ouvrez la fenêtre **Paramètres** (⌘ + ,)
2. Sélectionnez la langue dans l'onglet **Général**
3. Langues disponibles:
   - **Par défaut du système** - Suit la langue macOS
   - **English** - Interface en anglais
   - **中文** - Interface en chinois simplifié
   - **日本語** - Interface en japonais
   - **한국어** - Interface en coréen
   - **Русский** - Interface en russe
   - **Français** - Interface en français
   - **Deutsch** - Interface en allemand
4. L'interface de l'application mettra immédiatement à jour la langue
5. **La barre de menus et les sélecteurs de fichiers** nécessitent un redémarrage de l'application pour prendre effet, le système proposera un redémarrage immédiat

## 🏗️ Architecture du projet

```
SwiftMTP/
├── Native/                         # Pont Go (Kalam Kernel)
│   ├── kalam_bridge.go            # Implémentation principale du pont (CGO)
│   ├── libkalam.h                 # En-tête C (pont Swift)
│   ├── go.mod / go.sum            # Dépendances des modules Go
│   └── vendor/                    # Dépendances Go (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # Compilation de la bibliothèque dynamique Go
│   ├── create_dmg.sh              # Script d'empaquetage DMG
│   ├── create_dmg_simple.sh       # Empaquetage simplifié
│   ├── generate_icons.sh          # Script de génération d'icônes
│   ├── run_tests.sh               # Script d'exécution des tests
│   └── SwiftMTP/                  # Scripts de ressources
│       └── App/Assets.xcassets/   # Ressources d'icônes d'application
├── SwiftMTP/                      # Application Swift
│   ├── App/                       # Point d'entrée de l'application
│   │   ├── SwiftMTPApp.swift      # Point d'entrée de l'application
│   │   ├── Info.plist             # Configuration de l'application
│   │   ├── Assets.xcassets/       # Bundle de ressources (icônes)
│   │   └── Resources/             # Ressources de l'application
│   │       └── SwiftMTP_Logo.svg  # Logo de l'application
│   ├── Models/                    # Modèles de données
│   │   ├── Device.swift           # Modèle d'appareil
│   │   ├── FileItem.swift         # Modèle de fichier
│   │   ├── TransferTask.swift     # Modèle de tâche de transfert
│   │   └── AppLanguage.swift      # Modèle de langue
│   ├── Services/                  # Couche de services
│   │   ├── MTP/                   # Services MTP
│   │   │   ├── DeviceManager.swift    # Gestion des appareils
│   │   │   ├── FileSystemManager.swift# Système de fichiers
│   │   │   └── FileTransferManager.swift # Gestion des transferts
│   │   ├── LanguageManager.swift  # Gestionnaire de langue
│   │   └── LocalizationManager.swift # Gestionnaire de localisation
│   ├── Views/                     # Vues SwiftUI
│   │   ├── MainWindowView.swift   # Fenêtre principale
│   │   ├── DeviceListView.swift   # Liste des appareils
│   │   ├── FileBrowserView.swift  # Navigateur de fichiers
│   │   ├── FileTransferView.swift # Vue de transfert
│   │   ├── SettingsView.swift     # Fenêtre des paramètres
│   │   └── Components/            # Composants réutilisables
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # Fichiers de ressources
│   │   ├── Kalam.bundle/          # Bundle de bibliothèque dynamique Go
│   │   │   └── Contents/MacOS/Kalam
│   │   ├── Base.lproj/            # Pack de langue de base (anglais)
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # Pack de langue anglais
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # Pack de langue chinois simplifié
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # Pack de langue japonais
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ko.lproj/              # Pack de langue coréen
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ru.lproj/              # Pack de langue russe
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── fr.lproj/              # Pack de langue français
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── de.lproj/              # Pack de langue allemand
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Bibliothèque dynamique Go
│   ├── libkalam.h                 # Fichier d'en-tête C
│   └── SwiftMTP-Bridging-Header.h # En-tête de pont Swift-C
├── SwiftMTPTests/                 # Tests unitaires Swift
│   ├── AppLanguageTests.swift
│   ├── DeviceTests.swift
│   ├── FileBrowserViewTests.swift
│   ├── FileItemTests.swift
│   ├── FileSystemManagerTests.swift
│   ├── FileTransferManagerTests.swift
│   ├── LanguageManagerTests.swift
│   ├── SwiftMTPTests.swift
│   └── TransferTaskTests.swift
├── docs/                          # Documentation du projet
│   ├── sequence-diagrams.md       # Documentation des diagrammes de séquence
│   ├── TESTING.md                 # Documentation des tests
│   └── WIKI.md                    # Wiki du projet
├── build/                         # Répertoire de sortie de compilation
├── .github/workflows/             # GitHub Actions
│   └── test.yml                   # Configuration des tests CI
└── SwiftMTP.xcodeproj/            # Projet Xcode
```

### Stack technique

- **Langages**: Swift 6+, Go 1.22+
- **Framework UI**: SwiftUI
- **Bibliothèque MTP**: go-mtpx (basé sur libusb-1.0)
- **Modèle d'architecture**: MVVM
- **Méthode de pont**: CGO
- **Internationalisation**: Framework de localisation Swift (NSLocalizedString)

## ⚠️ Limitations connues

1. Le bac à sable doit être désactivé pour accéder aux appareils USB
2. La vitesse de transfert est limitée par le protocole MTP
3. Actuellement, seul le téléchargement de fichiers uniques est supporté (le téléchargement de dossiers n'est pas supporté)

## 🔧 Dépannage

### Appareil non détecté

```
✓ Assurez-vous que l'appareil est en mode MTP
✓ Essayez de débrancher et rebrancher le câble USB
✓ Redémarrez l'application
✓ Vérifiez que le câble USB supporte le transfert de données
```

### Erreurs de compilation

```bash
# Vérifier l'installation de libusb-1.0
brew list libusb-1.0

# Recompiler le pont Go
./Scripts/build_kalam.sh

# Nettoyer et recompiler
xcodebuild clean
xcodebuild
```

## 🤝 Contribution

Les problèmes et les Pull Requests sont les bienvenus!

## 📄 Licence

Ce projet est sous licence MIT License - voir le fichier [LICENSE](../LICENSE) pour les détails.

---

<div align="center">

**Si ce projet vous aide, s'il vous plaît ⭐ Star pour le soutien!**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>