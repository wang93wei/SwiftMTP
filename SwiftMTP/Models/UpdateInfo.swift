//
//  UpdateInfo.swift
//  SwiftMTP
//
//  Model for update information from GitHub Releases
//

import Foundation

/// Represents update information from GitHub Releases
struct UpdateInfo: Codable, Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let releaseNotes: String
    let publishedAt: Date
    let isPrerelease: Bool
    
    /// Checks if this update is newer than the current app version
    /// - Parameter currentVersion: The current app version string
    /// - Returns: True if this update is newer
    func isNewerThan(_ currentVersion: String) -> Bool {
        return version.compare(currentVersion, options: .numeric) == .orderedDescending
    }
}

/// GitHub Release API response structure
struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let name: String
    let body: String?
    let publishedAt: String
    let prerelease: Bool
    let assets: [GitHubAsset]
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case prerelease
        case assets
        case htmlUrl = "html_url"
    }
    
    /// Converts GitHub release to UpdateInfo
    /// - Returns: UpdateInfo if conversion succeeds
    func toUpdateInfo() -> UpdateInfo? {
        // Remove 'v' prefix if present
        let cleanVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        
        // Find the first .dmg asset or fallback to html_url
        let downloadURL: URL
        if let dmgAsset = assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            downloadURL = dmgAsset.browserDownloadUrl
        } else if let url = URL(string: htmlUrl) {
            downloadURL = url
        } else {
            return nil
        }
        
        // Parse date
        let dateFormatter = ISO8601DateFormatter()
        guard let publishedDate = dateFormatter.date(from: publishedAt) else {
            return nil
        }
        
        return UpdateInfo(
            version: cleanVersion,
            downloadURL: downloadURL,
            releaseNotes: body ?? "",
            publishedAt: publishedDate,
            isPrerelease: prerelease
        )
    }
}

/// GitHub Release asset structure
struct GitHubAsset: Codable, Sendable {
    let name: String
    let browserDownloadUrl: URL
    let size: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

/// Update check result
enum UpdateCheckResult: Sendable {
    case updateAvailable(UpdateInfo)
    case noUpdate(currentVersion: String)
    case error(UpdateError)
}