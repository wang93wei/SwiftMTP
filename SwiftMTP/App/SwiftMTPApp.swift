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
    }
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(languageManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            // 替换默认的应用菜单
            CommandGroup(replacing: .appInfo) {
                Button(L10n.Settings.about) {
                    openSettingsWindow()
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
    
    private func setAppleLanguages() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        var languages: [String]?
        
        if let savedLanguage = savedLanguage, let validLanguage = AppLanguage(rawValue: savedLanguage) {
            switch validLanguage {
            case .chinese:
                languages = ["zh-Hans", "zh-CN", "zh"]
            case .english:
                languages = ["en", "en-US"]
            case .japanese:
                languages = ["ja", "ja-JP"]
            case .korean:
                languages = ["ko", "ko-KR"]
            case .russian:
                languages = ["ru", "ru-RU"]
            case .french:
                languages = ["fr", "fr-FR"]
            case .german:
                languages = ["de", "de-DE"]
            case .system:
                // 系统默认：清除 AppleLanguages
                logLanguageSetup("Using system default language")
                languages = nil
            }
        } else {
            // 默认使用系统语言，清除 AppleLanguages
            logLanguageSetup("No saved language, using system default")
            languages = nil
        }
        
        if let languages = languages {
            // 设置 AppleLanguages
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
            logLanguageSetup("AppleLanguages set to: \(languages)")
        } else {
            // 清除 AppleLanguages，使用系统默认
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            logLanguageSetup("AppleLanguages cleared, using system default")
        }
    }
    
    private func logLanguageSetup(_ message: String) {
        #if DEBUG
        print("[SwiftMTPApp] \(message)")
        #endif
    }
    
    private func openSettingsWindow() {
        // SwiftUI 会自动处理 Settings scene 的打开
        // 使用标准的 macOS action 打开设置窗口
        // 注意：由于 SwiftMTPApp 是 struct，无法使用 @objc 方法
        // 使用字符串选择器作为回退方案
        let selector = Selector(("showPreferencesWindow:"))
        let result = NSApp.sendAction(selector, to: nil, from: nil)
        if !result {
            print("[SwiftMTPApp] Failed to open settings window")
        }
    }
}
