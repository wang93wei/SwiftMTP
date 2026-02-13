//
//  UpdateChecking.swift
//  SwiftMTP
//
//  Protocol for update checking operations
//

import Foundation
import Combine

/// Protocol defining update checking operations
/// Provides abstraction for testing and dependency injection
@MainActor
protocol UpdateChecking: ObservableObject {
    // MARK: - Published Properties
    
    /// Whether an update check is in progress
    var isChecking: Bool { get set }
    
    /// The latest update information if available
    var latestUpdate: UpdateInfo? { get set }
    
    /// Error message from the last check
    var lastError: String? { get set }
    
    /// Whether automatic update checks are enabled
    var autoCheckEnabled: Bool { get set }
    
    /// Last check timestamp
    var lastCheckDate: Date? { get set }
    
    // MARK: - Public Methods
    
    /// Check for updates from GitHub Releases
    /// - Parameter includePrereleases: Whether to include prerelease versions
    /// - Returns: Update check result
    func checkForUpdates(includePrereleases: Bool) async -> UpdateCheckResult
    
    /// Start automatic update checking
    /// Uses the configured check interval
    func startAutoCheck()
    
    /// Stop automatic update checking
    func stopAutoCheck()
    
    /// Open the download page for the latest update
    func openDownloadPage()
    
    /// Reset the last check date
    func resetLastCheckDate()
}

// MARK: - Default Implementations

extension UpdateChecking {
    /// Check for updates (excluding prereleases by default)
    /// - Returns: Update check result
    func checkForUpdates() async -> UpdateCheckResult {
        return await checkForUpdates(includePrereleases: false)
    }
}