//
//  LanguageManager.swift
//  SwiftMTP
//
//  Language management service for dynamic language switching
//

import Foundation
import Combine

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            saveLanguage()
            updateBundle()
            notifyLanguageChanged()
        }
    }
    
    private let languageKey = "appLanguage"
    private var bundle: Bundle = .main
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: languageKey)
        
        // 验证保存的语言值是否有效
        if let savedLanguage = savedLanguage, let validLanguage = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = validLanguage
            logLanguageChange("Loaded valid language: \(validLanguage.rawValue)")
        } else {
            self.currentLanguage = .system
            logLanguageChange("Using default language (system)")
        }
        
        updateBundle()
        logLanguageChange("LanguageManager initialization complete")
        
        // 验证语言包完整性
        validateLanguageBundle()
    }
    
    private func validateLanguageBundle() {
        #if DEBUG
        let testKeys = ["deviceList", "refresh", "cancel", "ok"]
        var missingKeys: [String] = []
        
        for key in testKeys {
            let value = localizedString(for: key)
            if value == key {
                missingKeys.append(key)
            }
        }
        
        if !missingKeys.isEmpty {
            print("[LanguageManager] Warning: Missing localization keys: \(missingKeys)")
        } else {
            print("[LanguageManager] Language bundle validation passed")
        }
        #endif
    }
    
    private func saveLanguage() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
        logLanguageChange("Saved language: \(currentLanguage.rawValue)")
    }
    
    private func updateBundle() {
        if let localeIdentifier = currentLanguage.localeIdentifier {
            logLanguageChange("Looking for locale: \(localeIdentifier)")
            let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj")
            logLanguageChange("Path for \(localeIdentifier): \(path ?? "nil")")
            
            guard let path = path,
                  let bundle = Bundle(path: path) else {
                logLanguageChange("Failed to find bundle for locale: \(localeIdentifier), falling back to main bundle")
                self.bundle = .main
                
                // 通知用户语言包加载失败
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .languageBundleLoadFailed,
                        object: nil,
                        userInfo: ["locale": localeIdentifier]
                    )
                }
                return
            }
            
            // 验证 bundle 是否有效
            let testString = bundle.localizedString(forKey: "deviceList", value: nil, table: nil)
            if testString == "deviceList" {
                logLanguageChange("Warning: Bundle at \(localeIdentifier) may be invalid (test key not found), falling back to main bundle")
                self.bundle = .main
                return
            }
            
            self.bundle = bundle
            logLanguageChange("Successfully updated bundle to: \(localeIdentifier), test string: \(testString)")
        } else {
            // 系统默认模式：显式检测系统语言并加载对应语言包
            logLanguageChange("System default mode - detecting system language")
            
            // 使用公开 API 获取系统语言
            var systemLanguages = Locale.preferredLanguages
            logLanguageChange("System languages from Locale.preferredLanguages: \(systemLanguages)")
            
            // 如果 Locale.preferredLanguages 为空，尝试从 UserDefaults 读取
            if systemLanguages.isEmpty {
                if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
                    systemLanguages = langs
                    logLanguageChange("System languages from UserDefaults.standard: \(systemLanguages)")
                }
            }
            
            logLanguageChange("Preferred languages for matching: \(systemLanguages)")
            
            // 尝试匹配支持的语言
            var matchedLocale: String? = nil
            
            for languageCode in systemLanguages {
                // 检查是否匹配中文（包括 zh-Hans-CN, zh-Hans, zh-Hant, zh-CN 等变体）
                if languageCode.hasPrefix("zh") {
                    matchedLocale = "zh-Hans"
                    logLanguageChange("Matched Chinese language: \(languageCode)")
                    break
                }
                // 检查是否匹配英文
                else if languageCode.hasPrefix("en") {
                    matchedLocale = "en"
                    logLanguageChange("Matched English language: \(languageCode)")
                    break
                }
            }
            
            if let locale = matchedLocale {
                let path = Bundle.main.path(forResource: locale, ofType: "lproj")
                logLanguageChange("Path for system locale \(locale): \(path ?? "nil")")
                
                if let path = path, let bundle = Bundle(path: path) {
                    // 验证 bundle 是否有效
                    let testString = bundle.localizedString(forKey: "deviceList", value: nil, table: nil)
                    if testString != "deviceList" {
                        self.bundle = bundle
                        logLanguageChange("Successfully loaded system language bundle: \(locale), test string: \(testString)")
                        return
                    }
                }
            }
            
            // 如果没有匹配的语言或加载失败，使用主包
            self.bundle = .main
            logLanguageChange("No matching system language bundle found, using main bundle")
        }
    }
    
    private func notifyLanguageChanged() {
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        logLanguageChange("Language changed notification sent")
    }
    
    func localizedString(for key: String) -> String {
        // 尝试从当前语言包获取
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        
        // 如果找不到（返回 key 本身），尝试从主包获取
        if localized == key {
            let fallback = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if fallback != key {
                logLanguageChange("Key '\(key)' not found in current bundle, using fallback: \(fallback)")
                return fallback
            }
            logLanguageChange("Key '\(key)' not found in any bundle, returning key")
        }
        
        return localized
    }
    
    private func logLanguageChange(_ message: String) {
        #if DEBUG
        print("[LanguageManager] \(message)")
        #endif
    }
    
    // MARK: - 公共方法
    
    /// 清理所有 Combine 订阅
    /// 在应用退出或重启时调用，防止内存泄漏
    func cleanupSubscriptions() {
        cancellables.removeAll()
        logLanguageChange("Cleaned up all subscriptions")
    }
}

extension Notification.Name {
    /// 语言更改通知
    static let languageDidChange = Notification.Name("languageDidChange")
    
    /// 语言包加载失败通知
    static let languageBundleLoadFailed = Notification.Name("languageBundleLoadFailed")
}