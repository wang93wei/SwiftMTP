//
//  UpdateChecker.swift
//  SwiftMTP
//
//  Manages update checking from GitHub Releases
//

import Foundation
import Combine
import AppKit

@MainActor
final class UpdateChecker: ObservableObject, UpdateChecking {
    // MARK: - Singleton

    static let shared = UpdateChecker()

    // MARK: - Published Properties

    /// Whether an update check is in progress
    @Published var isChecking: Bool = false

    /// The latest update information if available
    @Published var latestUpdate: UpdateInfo? = nil

    /// Error message from the last check
    @Published var lastError: String? = nil

    /// Whether automatic update checks are enabled
    @Published var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: AppConfiguration.autoCheckUpdatesKey)
            if autoCheckEnabled {
                startAutoCheck()
            } else {
                stopAutoCheck()
            }
        }
    }

    /// Last check timestamp
    @Published var lastCheckDate: Date? {
        didSet {
            if let date = lastCheckDate {
                UserDefaults.standard.set(date, forKey: AppConfiguration.lastUpdateCheckKey)
            }
        }
    }

    // MARK: - Private Properties

    /// GitHub API URL for releases
    private let releasesURL: URL

    /// URL session for network requests
    private let urlSession: URLSession

    /// Auto check task
    private var autoCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        // Initialize from UserDefaults
        self.autoCheckEnabled = UserDefaults.standard.bool(forKey: AppConfiguration.autoCheckUpdatesKey)
        self.lastCheckDate = UserDefaults.standard.object(forKey: AppConfiguration.lastUpdateCheckKey) as? Date

        // Configure URL
        let repoOwner = AppConfiguration.githubRepoOwner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? AppConfiguration.githubRepoOwner
        let repoName = AppConfiguration.githubRepoName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? AppConfiguration.githubRepoName
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases"
        guard let url = URL(string: urlString) else {
            fatalError("Invalid GitHub API URL configuration")
        }
        self.releasesURL = url

        // Configure URL session with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfiguration.updateCheckTimeout
        config.timeoutIntervalForResource = AppConfiguration.updateCheckTimeout
        self.urlSession = URLSession(configuration: config)

        // Start auto check if enabled
        if autoCheckEnabled {
            startAutoCheck()
        }
    }

    deinit {
        autoCheckTask?.cancel()
    }

    // MARK: - Public Methods

    /// Check for updates from GitHub Releases
    /// - Parameter includePrereleases: Whether to include prerelease versions
    /// - Returns: Update check result
    func checkForUpdates(includePrereleases: Bool = false) async -> UpdateCheckResult {
        print("[UpdateChecker] Starting update check (current version: \(currentAppVersion), includePrereleases: \(includePrereleases))")

        // Set Checking state
        isChecking = true
        lastError = nil
        defer {
            isChecking = false
            print("[UpdateChecker] Update check completed")
        }

        do {
            // Check for cancellation
            try Task.checkCancellation()

            // Fetch releases from GitHub
            let releases = try await fetchReleases()

            // Check for cancellation
            try Task.checkCancellation()

            // Filter and find the latest applicable release
            guard let latestRelease = findLatestRelease(
                from: releases,
                includePrereleases: includePrereleases
            ) else {
                return .noUpdate(currentVersion: currentAppVersion)
            }

            // Convert to UpdateInfo
            guard let updateInfo = latestRelease.toUpdateInfo() else {
                return .error(.invalidResponse)
            }

            // Update last check date
            lastCheckDate = Date()

            // Compare versions
            print("[UpdateChecker] Comparing versions: GitHub='\(updateInfo.version)' vs Current='\(currentAppVersion)'")
            if updateInfo.isNewerThan(currentAppVersion) {
                print("[UpdateChecker] Update available: \(updateInfo.version) > \(currentAppVersion)")
                latestUpdate = updateInfo
                return .updateAvailable(updateInfo)
            } else {
                print("[UpdateChecker] No update needed: \(updateInfo.version) <= \(currentAppVersion)")
                latestUpdate = nil
                return .noUpdate(currentVersion: currentAppVersion)
            }

        } catch is CancellationError {
            return .error(.checkCancelled)
        } catch let error as UpdateError {
            lastError = error.localizedDescription
            return .error(error)
        } catch {
            let updateError = UpdateError.networkError(underlying: error)
            lastError = updateError.localizedDescription
            return .error(updateError)
        }
    }

    /// Start automatic update checking
    func startAutoCheck() {
        guard autoCheckTask == nil else { return }

        // Check if we should skip (checked recently)
        if let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < AppConfiguration.autoCheckInterval {
            return
        }

        autoCheckTask = Task {
            // Wait a bit after app launch before first check
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000) // 10 seconds

            while !Task.isCancelled {
                _ = await checkForUpdates()

                // Wait for the next interval
                try? await Task.sleep(nanoseconds: UInt64(AppConfiguration.autoCheckInterval) * 1_000_000_000)
            }
        }
    }

    /// Stop automatic update checking
    func stopAutoCheck() {
        autoCheckTask?.cancel()
        autoCheckTask = nil
    }

    /// Open the download page for the latest update
    func openDownloadPage() {
        guard let update = latestUpdate else { return }

        NSWorkspace.shared.open(update.downloadURL)
    }

    /// Reset the last check date
    func resetLastCheckDate() {
        lastCheckDate = nil
        UserDefaults.standard.removeObject(forKey: AppConfiguration.lastUpdateCheckKey)
    }

    /// Check for updates and return a result handler for SwiftUI alerts
    /// - Returns: Tuple containing alert title, message, and whether an update is available
    func checkForUpdatesWithResult(includePrereleases: Bool = false) async -> (title: String, message: String, isUpdateAvailable: Bool, updateURL: URL?) {
        let currentVersion = currentAppVersion
        let result = await checkForUpdates(includePrereleases: includePrereleases)

        switch result {
        case .updateAvailable(let updateInfo):
            let title = L10n.Settings.updateAvailableTitle
            let message = String(format: L10n.Settings.updateAvailableMessage, updateInfo.version, currentVersion)
            return (title, message, true, updateInfo.downloadURL)
        case .noUpdate:
            let title = L10n.Settings.noUpdateAvailableTitle
            let message = String(format: L10n.Settings.noUpdateMessage, currentVersion)
            return (title, message, false, nil)
        case .error(let error):
            let title = L10n.Common.error
            let message = error.localizedDescription
            return (title, message, false, nil)
        }
    }

    // MARK: - Private Methods

    /// Fetch releases from GitHub API
    /// - Returns: Array of GitHub releases
    private func fetchReleases() async throws -> [GitHubRelease] {
        print("[UpdateChecker] Fetching releases from: \(releasesURL)")

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftMTP-App/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        print("[UpdateChecker] HTTP Status: \(httpResponse.statusCode)")

        // Handle rate limiting
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let delay = retryAfter.flatMap { TimeInterval($0) } ?? 60
            throw UpdateError.rateLimited(retryAfter: delay)
        }

        // Handle other errors
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message from GitHub API
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                print("[UpdateChecker] GitHub API error: \(message)")
            }
            throw UpdateError.invalidResponse
        }

        // Verify we got an array (not an error object)
        guard let json = try? JSONSerialization.jsonObject(with: data),
              json is [Any] else {
            print("[UpdateChecker] Unexpected response format")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[UpdateChecker] Response: \(jsonString.prefix(500))")
            }
            throw UpdateError.invalidResponse
        }

        // Parse JSON
        do {
            let decoder = JSONDecoder()
            // Note: Don't use keyDecodingStrategy since we have manual CodingKeys
            let releases = try decoder.decode([GitHubRelease].self, from: data)
            print("[UpdateChecker] Successfully fetched \(releases.count) releases")
            for (index, release) in releases.prefix(5).enumerated() {
                print("[UpdateChecker] Release #\(index + 1): tag_name='\(release.tagName)', name='\(release.name)', prerelease=\(release.prerelease)")
            }
            if releases.count > 5 {
                print("[UpdateChecker] ... and \(releases.count - 5) more releases")
            }
            return releases
        } catch {
            // Debug: print raw response to diagnose issues
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[UpdateChecker] Failed to parse JSON: \(jsonString.prefix(500))...")
            }
            throw UpdateError.parsingError(underlying: error)
        }
    }

    /// Find the latest applicable release
    /// - Parameters:
    ///   - releases: Array of GitHub releases
    ///   - includePrereleases: Whether to include prerelease versions
    /// - Returns: The latest applicable release
    private func findLatestRelease(
        from releases: [GitHubRelease],
        includePrereleases: Bool
    ) -> GitHubRelease? {
        let filteredReleases = releases.filter { release in
            // Skip drafts
            // Note: GitHub API doesn't include draft field in the basic response,
            // but we can filter prereleases
            if !includePrereleases && release.prerelease {
                return false
            }
            return true
        }

        if let latest = filteredReleases.first {
            print("[UpdateChecker] Latest applicable release: \(latest.tagName) (prerelease: \(latest.prerelease))")
        } else {
            print("[UpdateChecker] No applicable release found (includePrereleases: \(includePrereleases))")
        }

        return filteredReleases.first
    }

    /// Current app version from Info.plist
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}