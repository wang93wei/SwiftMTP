//
//  FileItem.swift
//  SwiftMTP
//
//  Data model representing a file or folder on the MTP device
//

import Foundation

struct FileItem: Identifiable, Hashable, Comparable {
    let id: UUID
    let objectId: UInt32
    let parentId: UInt32
    let storageId: UInt32
    let name: String
    let path: String
    let size: UInt64
    let modifiedDate: Date?
    let isDirectory: Bool
    let fileType: String
    var children: [FileItem]?
    
    // Pre-computed formatted values to avoid MainActor isolation issues
    let formattedSize: String
    let formattedDate: String
    let sortableDate: Date
    
    init(id: UUID = UUID(), objectId: UInt32, parentId: UInt32, storageId: UInt32,
         name: String, path: String, size: UInt64, modifiedDate: Date?,
         isDirectory: Bool, fileType: String = "", children: [FileItem]? = nil) {
        // Debug: Print each step to identify the crash point
        print("[FileItem.init] Starting init for: \(name)")
        print("[FileItem.init] Parameters - objectId=\(objectId), parentId=\(parentId), storageId=\(storageId), size=\(size), isDirectory=\(isDirectory), fileType=\(fileType)")

        // Validate name
        let safeName = name.isEmpty ? "Unknown" : name
        self.name = safeName

        self.id = id
        self.objectId = objectId
        self.parentId = parentId
        self.storageId = storageId
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
        self.isDirectory = isDirectory
        self.fileType = fileType
        self.children = children

        print("[FileItem.init] Basic properties set")

        // Pre-compute sortableDate
        if let date = modifiedDate {
            self.sortableDate = date
            print("[FileItem.init] sortableDate set to modifiedDate: \(date)")
        } else {
            self.sortableDate = Date(timeIntervalSince1970: 0)
            print("[FileItem.init] sortableDate set to epoch (no modifiedDate)")
        }

        print("[FileItem.init] sortableDate computed: \(sortableDate)")

        // Pre-compute formattedSize using a simple formatter
        if isDirectory {
            self.formattedSize = "--"
            print("[FileItem.init] formattedSize set to '--' (directory)")
        } else {
            self.formattedSize = FileItem.formatFileSize(size)
            print("[FileItem.init] formattedSize computed: \(formattedSize)")
        }

        // Pre-compute formattedDate - use modifiedDate if available, otherwise use nil
        if let date = modifiedDate {
            self.formattedDate = FileItem.formatDate(date)
            print("[FileItem.init] formattedDate computed from modifiedDate: \(formattedDate)")
        } else {
            self.formattedDate = "--"
            print("[FileItem.init] formattedDate set to '--' (no modifiedDate)")
        }

        print("[FileItem.init] Init completed for: \(name)")
    }
    
    // MARK: - Private Helper Methods
    
    /// Format file size without using localized formatters
    private static func formatFileSize(_ size: UInt64) -> String {
        print("[FileItem.formatFileSize] Formatting size: \(size)")

        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(size)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        // Build string without using format specifiers
        let unit = units[unitIndex]
        let integerPart = Int(size)
        let decimalPart = Int((size - Double(integerPart)) * 10)

        let result = String(integerPart) + "." + String(decimalPart) + " " + unit
        print("[FileItem.formatFileSize] Result: \(result)")
        return result
    }

    /// Format date with localized support
    private static func formatDate(_ date: Date) -> String {
        print("[FileItem.formatDate] Formatting date: \(date)")

        // Date boundary validation - only check minimum date, allow reasonable future dates
        let minimumValidDate = Date(timeIntervalSince1970: 0)
        let farFutureThreshold = Date(timeIntervalSince1970: 2147483647) // Year 2038 limit

        guard date >= minimumValidDate && date <= farFutureThreshold else {
            print("[FileItem.formatDate] Date out of valid range, returning '--'")
            return "--"
        }

        // Use DateFormatter with localization support
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current

        let result = formatter.string(from: date)
        print("[FileItem.formatDate] Result: \(result)")
        return result
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(objectId)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id && lhs.objectId == rhs.objectId
    }
    
    // Comparable conformance (default sorting by name)
    // Use simple string comparison instead of localizedStandardCompare to avoid MainActor issues
    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.name < rhs.name
    }
    
    var fileExtension: String {
        guard !isDirectory else { return "" }
        return (name as NSString).pathExtension
    }
    
    // Note: formattedSize, formattedDate, and sortableDate are now computed in init()
}
