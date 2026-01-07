# SwiftMTP

<div align="center">

<img src="../SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**ネイティブ macOS Android MTP ファイル転送ツール**

[![Swift Version](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)

</div>

---

**🌍 言語:** [English](../README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

---

## ✨ 機能

| 機能 | 説明 |
|------|------|
| 🔌 **自動デバイス検出** | 接続された Android デバイスを自動検出 |
| 📁 **ファイルブラウジング** | デバイスのファイルシステムをスムーズに閲覧 |
| ⬇️ **ファイルダウンロード** | 単一およびバッチファイルダウンロードをサポート |
| ⬆️ **ファイルアップロード** | ボタン選択とドラッグ＆ドロップによるファイルアップロードをサポート |
| 💾 **大ファイル対応** | 4GB 以上のファイル転送をサポート |
| 📦 **バッチ操作** | ファイルの一括選択と処理 |
| 🎨 **モダンな UI** | 美しい SwiftUI インターフェース |
| 📊 **ストレージ情報** | デバイスのストレージ使用状況を表示 |
| 🌍 **多言語対応** | 簡体字中国語、英語、日本語、韓国語をサポート、システム言語に従う |

## 📸 アプリスクリーンショット
![SwiftMTP Logo](../SwiftMTP/Resources/cap_2025-12-24%2005.29.36.png)

## 🚀 クイックスタート

### 要件

| 依存関係 | バージョン |
|------------|---------|
| macOS | 26.0+ (以降) |
| Xcode | 26.0+ |
| Homebrew | 最新版 |

### 依存関係のインストール

```bash
brew install libusb-1.0 go
```

### ビルドと実行

```bash
# リポジトリをクローン
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# Go ブリッジレイヤーをビルド
./Scripts/build_kalam.sh

# Xcode で開いて実行
open SwiftMTP.xcodeproj
```

> 📝 **注**: プロジェクト設定ファイルはバージョン管理にコミットされています。クローン後、Xcode でプロジェクトを開くだけで追加設定なしでビルドを開始できます。

> 💡 **ヒント**: Android デバイスを接続した後、デバイスで **ファイル転送 (MTP)** モードを選択して使用を開始してください。

### インストールパッケージの作成

```bash
# 簡易パッケージング（開発者証明書不要）
./Scripts/create_dmg_simple.sh

# 完全パッケージング（開発者証明書が必要）
./Scripts/create_dmg.sh
```

DMG ファイルは `build/` ディレクトリに生成されます。

## 📖 ユーザーガイド

### デバイスの接続

1. USB 経由で Android デバイスを Mac に接続
2. デバイスで **ファイル転送 (MTP)** モードを選択
3. SwiftMTP が自動的にデバイスを検出して表示

### ファイル操作

| 操作 | 方法 |
|-----------|--------|
| ファイル閲覧 | フォルダをダブルクリックして移動、パンくずナビゲーションで戻る |
| ファイルダウンロード | ファイルを右クリック → **ダウンロード** |
| バッチダウンロード | ファイルを複数選択 → 右クリック → **選択ファイルをダウンロード** |
| ファイルアップロード | ツールバーの **ファイルアップロード** ボタンをクリック、またはファイルをウィンドウにドラッグ＆ドロップ |
| ドラッグ＆ドロップアップロード | ファイルをファイルブラウザウィンドウにドラッグしてアップロード |

### 言語設定

1. **設定** ウィンドウを開く（⌘ + ,）
2. **一般** タブで言語を選択
3. 利用可能な言語：
   - **システムデフォルト** - macOS システム言語に従う
   - **English** - 英語インターフェース
   - **中文** - 簡体字中国語インターフェース
   - **日本語** - 日本語インターフェース
   - **한국어** - 韓国語インターフェース
4. アプリ内のインターフェースは即座に言語が更新されます
5. **メニューバーとファイル選択**はアプリの再起動が必要で、システムが即時再起動を促します

## 🏗️ プロジェクトアーキテクチャ

```
SwiftMTP/
├── Native/                         # Go ブリッジレイヤー (Kalam Kernel)
│   ├── kalam_bridge.go            # メインブリッジ実装 (CGO)
│   ├── kalam_bridge_test.go       # Go ユニットテスト
│   ├── libkalam.h                 # C ヘッダ (Swift ブリッジ)
│   ├── go.mod / go.sum            # Go モジュール依存関係
│   └── vendor/                    # Go 依存関係 (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # Go 動的ライブラリをビルド
│   ├── create_dmg.sh              # DMG パッケージングスクリプト
│   ├── create_dmg_simple.sh       # 簡易パッケージング
│   ├── generate_icons.sh          # アイコン生成スクリプト
│   ├── run_tests.sh               # テスト実行スクリプト
│   └── SwiftMTP/                  # リソーススクリプト
│       └── App/Assets.xcassets/   # アプリアイコンリソース
├── SwiftMTP/                      # Swift アプリケーション
│   ├── App/                       # アプリエントリ
│   │   ├── SwiftMTPApp.swift      # アプリエントリポイント
│   │   ├── Info.plist             # アプリ設定
│   │   ├── Assets.xcassets/       # アセットバンドル（アイコン）
│   │   └── Resources/             # アプリリソース
│   │       └── SwiftMTP_Logo.svg  # アプリロゴ
│   ├── Models/                    # データモデル
│   │   ├── Device.swift           # デバイスモデル
│   │   ├── FileItem.swift         # ファイルモデル
│   │   ├── TransferTask.swift     # 転送タスクモデル
│   │   └── AppLanguage.swift      # 言語モデル
│   ├── Services/                  # サービスレイヤー
│   │   ├── MTP/                   # MTP サービス
│   │   │   ├── DeviceManager.swift    # デバイス管理
│   │   │   ├── FileSystemManager.swift# ファイルシステム
│   │   │   └── FileTransferManager.swift # 転送管理
│   │   ├── LanguageManager.swift  # 言語マネージャー
│   │   └── LocalizationManager.swift # ローカライゼーションマネージャー
│   ├── Views/                     # SwiftUI ビュー
│   │   ├── MainWindowView.swift   # メインウィンドウ
│   │   ├── DeviceListView.swift   # デバイスリスト
│   │   ├── FileBrowserView.swift  # ファイルブラウザ
│   │   ├── FileTransferView.swift # 転送ビュー
│   │   ├── SettingsView.swift     # 設定ウィンドウ
│   │   └── Components/            # 再利用可能なコンポーネント
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # リソースファイル
│   │   ├── Kalam.bundle/          # Go 動的ライブラリバンドル
│   │   │   └── Contents/MacOS/Kalam
│   │   ├── Base.lproj/            # ベース言語パック（英語）
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # 英語言語パック
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # 簡体字中国語言語パック
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # 日本語言語パック
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── ko.lproj/              # 韓国語言語パック
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Go 動的ライブラリ
│   ├── libkalam.h                 # C ヘッダーファイル
│   └── SwiftMTP-Bridging-Header.h # Swift-C ブリッジヘッダー
├── SwiftMTPTests/                 # Swift ユニットテスト
│   ├── AppLanguageTests.swift
│   ├── DeviceTests.swift
│   ├── FileBrowserViewTests.swift
│   ├── FileItemTests.swift
│   ├── FileSystemManagerTests.swift
│   ├── FileTransferManagerTests.swift
│   ├── LanguageManagerTests.swift
│   ├── SwiftMTPTests.swift
│   └── TransferTaskTests.swift
├── docs/                          # プロジェクトドキュメント
│   ├── sequence-diagrams.md       # シーケンス図ドキュメント
│   ├── TESTING.md                 # テストドキュメント
│   └── WIKI.md                    # プロジェクト Wiki
├── build/                         # ビルド出力ディレクトリ
├── .github/workflows/             # GitHub Actions
│   └── test.yml                   # CI テスト設定
└── SwiftMTP.xcodeproj/            # Xcode プロジェクト
```

### 技術スタック

- **言語**: Swift 5.9+, Go 1.22+
- **UI フレームワーク**: SwiftUI
- **MTP ライブラリ**: go-mtpx (libusb-1.0 ベース)
- **アーキテクチャパターン**: MVVM
- **ブリッジ方法**: CGO
- **国際化**: Swift ローカライゼーションフレームワーク (NSLocalizedString)

## ⚠️ 既知の制限事項

1. USB デバイスにアクセスするにはサンドボックスを無効にする必要があります
2. 転送速度は MTP プロトコルの制限を受けます
3. 現在、単一ファイルのアップロードのみをサポートしています（フォルダーアップロードは未サポート）

## 🔧 トラブルシューティング

### デバイスが検出されない

```
✓ デバイスが MTP モードになっていることを確認
✓ USB ケーブルを抜き差ししてみる
✓ アプリを再起動
✓ USB ケーブルがデータ転送をサポートしているか確認
```

### ビルドエラー

```bash
# libusb-1.0 のインストールを確認
brew list libusb-1.0

# Go ブリッジレイヤーを再ビルド
./Scripts/build_kalam.sh

# クリーンして再ビルド
xcodebuild clean
xcodebuild
```

## 🤝 貢献

Issue と Pull Request を歓迎します！

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下でライセンスされています - 詳細は [LICENSE](../LICENSE) ファイルを参照してください。

---

<div align="center">

**このプロジェクトが役に立った場合は、⭐ Star で応援してください！**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>