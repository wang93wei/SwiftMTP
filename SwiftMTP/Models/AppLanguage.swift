//
//  AppLanguage.swift
//  SwiftMTP
//
//  Application language configuration
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh"
    
    var id: String { rawValue }
    
    var displayName: String {
        // 使用本地化字符串，如果不可用则使用硬编码的回退值
        switch self {
        case .system:
            return L10n.Common.systemDefault
        case .english:
            return L10n.Common.languageEnglish
        case .chinese:
            return L10n.Common.languageChinese
        }
    }
    
    // 提供不依赖 L10n 的显示名称，用于初始化时避免循环依赖
    var displayNameRaw: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
    
    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }
}