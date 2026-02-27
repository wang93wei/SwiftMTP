//
//  SwiftMTPApp.swift
//  SwiftMTP
//
//  Created by SwiftMTP on 2025-12-21.
//

import SwiftUI

@main
struct SwiftMTPApp: App {
    @StateObject private var languageManager = LanguageManager.shared
    
    init() {
        setupLanguage()
        setupCleanupHandler()
    }
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(languageManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        
                .commands {
            // 替换默认的应用菜单
            CommandGroup(replacing: .appInfo) {
                Button(L10n.Settings.about) {
                    // 显示标准的 macOS About 面板
                    NSApp.orderFrontStandardAboutPanel()
                }
            }

            // 添加语言菜单
            CommandMenu(L10n.Common.language) {
                Button(L10n.Common.languageChinese) {
                    languageManager.currentLanguage = .chinese
                }
                Button(L10n.Common.languageEnglish) {
                    languageManager.currentLanguage = .english
                }
                Button(L10n.Common.languageJapanese) {
                    languageManager.currentLanguage = .japanese
                }
                Button(L10n.Common.languageKorean) {
                    languageManager.currentLanguage = .korean
                }
                Button(L10n.Common.languageRussian) {
                    languageManager.currentLanguage = .russian
                }
                Button(L10n.Common.languageFrench) {
                    languageManager.currentLanguage = .french
                }
                Button(L10n.Common.languageGerman) {
                    languageManager.currentLanguage = .german
                }
                Button(L10n.Common.systemDefault) {
                    languageManager.currentLanguage = .system
                }
            }

            // 添加检查更新菜单到 Help 菜单
            CommandGroup(replacing: .help) {
                Button(L10n.Common.swiftMtpHelp) {
                    if let url = URL(string: AppConfiguration.githubWikiURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                CheckForUpdatesMenuItem()
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(languageManager)
        }
        #endif
    }
    
    private func setupLanguage() {
        logLanguageSetup("Language setup initialized")
        
        // 设置 AppleLanguages 以确保文件选择器使用正确的语言
        setAppleLanguages()
    }
    
    private func setupCleanupHandler() {
        #if DEBUG
        print("[SwiftMTPApp] Setting up cleanup handler")
        #endif
        
        // 监听应用退出通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            #if DEBUG
            print("[SwiftMTPApp] Application will terminate, cleaning up resources")
            #endif
            
            // Stop periodic/in-flight scan tasks before native bridge teardown.
            MainActor.assumeIsolated {
                DeviceManager.shared.prepareForTermination()
            }
            
            // 清理设备连接池
            Kalam_CleanupDevicePool()
            
            // 清理泄漏的字符串
            Kalam_CleanupLeakedStrings()
        }
    }
    
    private func setAppleLanguages() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        let languages: [String]?
        
        if let savedLanguage = savedLanguage, let validLanguage = AppLanguage(rawValue: savedLanguage) {
            languages = validLanguage.appleLanguages
            if languages == nil {
                logLanguageSetup("Using system default language")
            }
        } else {
            languages = nil
            logLanguageSetup("No saved language, using system default")
        }
        
        if let languages = languages {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
            logLanguageSetup("AppleLanguages set to: \(languages)")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            logLanguageSetup("AppleLanguages cleared, using system default")
        }
    }
    
    private func logLanguageSetup(_ message: String) {
        #if DEBUG
        print("[SwiftMTPApp] \(message)")
        #endif
    }
}

// MARK: - Check for Updates Menu Item

struct CheckForUpdatesMenuItem: View {
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        Button(L10n.Settings.checkForUpdates) {
            Task {
                await performCheck()
            }
        }
        .disabled(updateChecker.isChecking)
    }

    private func performCheck() async {
        let result = await updateChecker.checkForUpdatesWithResult()

        // Use NSAlert for menu bar commands - SwiftUI alert doesn't work well in menus
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = result.title
            alert.informativeText = result.message
            alert.alertStyle = result.isUpdateAvailable ? .warning : .informational

            if result.isUpdateAvailable, let url = result.updateURL {
                alert.addButton(withTitle: L10n.Settings.downloadUpdate)
                alert.addButton(withTitle: L10n.Common.cancel)

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            } else {
                alert.addButton(withTitle: L10n.Common.ok)
                alert.runModal()
            }
        }
    }
}
