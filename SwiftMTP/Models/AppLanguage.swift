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
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        // Use displayNameRaw for non-isolated access
        return displayNameRaw
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
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .russian:
            return "Русский"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
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
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .russian:
            return "ru"
        case .french:
            return "fr"
        case .german:
            return "de"
        }
    }
}