//
//  FileItem.swift
//  SwiftMTP
//
//  Data model representing a file or folder on the MTP device
//

import Foundation

struct FileItem: Identifiable, Hashable, Comparable, Sendable {
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
    
    nonisolated init(id: UUID = UUID(), objectId: UInt32, parentId: UInt32, storageId: UInt32,
         name: String, path: String, size: UInt64, modifiedDate: Date?,
         isDirectory: Bool, fileType: String = "", children: [FileItem]? = nil) {
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
    }
    
    // Lazy-computed formatted values for better performance
    var formattedSize: String {
        if isDirectory {
            return "--"
        } else {
            return FileItem.formatFileSize(size)
        }
    }
    
    var formattedDate: String {
        if let date = modifiedDate {
            return FileItem.formatDate(date)
        } else {
            return "--"
        }
    }
    
    var sortableDate: Date {
        if let date = modifiedDate {
            return date
        } else {
            return Date(timeIntervalSince1970: 0)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Format file size without using localized formatters
    private static func formatFileSize(_ size: UInt64) -> String {
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

        return String(integerPart) + "." + String(decimalPart) + " " + unit
    }

    /// Format date with localized support
    private static func formatDate(_ date: Date) -> String {
        // Date boundary validation - only check minimum date, allow reasonable future dates
        let minimumValidDate = Date(timeIntervalSince1970: 0)
        let farFutureThreshold = Date(timeIntervalSince1970: 2147483647) // Year 2038 limit

        guard date >= minimumValidDate && date <= farFutureThreshold else {
            return "--"
        }

        // Use Calendar to avoid MainActor isolation
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute else {
            return "--"
        }

        // Format as YYYY-MM-DD HH:MM
        return String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
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
