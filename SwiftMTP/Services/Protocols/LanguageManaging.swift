//
//  LanguageManaging.swift
//  SwiftMTP
//
//  Protocol for language management operations
//

import Foundation
import Combine

/// Protocol defining language management operations
/// Provides abstraction for testing and dependency injection
@MainActor
protocol LanguageManaging: ObservableObject {
    // MARK: - Published Properties
    
    /// Current application language
    var currentLanguage: AppLanguage { get set }
    
    // MARK: - Public Methods
    
    /// Get localized string for a key
    /// - Parameter key: Localization key
    /// - Returns: Localized string
    func localizedString(for key: String) -> String
    
    /// Clean up all Combine subscriptions
    func cleanupSubscriptions()
}