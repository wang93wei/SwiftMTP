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
    
    init(id: UUID = UUID(), objectId: UInt32, parentId: UInt32, storageId: UInt32,
         name: String, path: String, size: UInt64, modifiedDate: Date?,
         isDirectory: Bool, fileType: String = "", children: [FileItem]? = nil) {
        self.id = id
        self.objectId = objectId
        self.parentId = parentId
        self.storageId = storageId
        self.name = name
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
        self.isDirectory = isDirectory
        self.fileType = fileType
        self.children = children
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
    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    
    var fileExtension: String {
        guard !isDirectory else { return "" }
        return (name as NSString).pathExtension
    }
    
    var formattedSize: String {
        guard !isDirectory else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var formattedDate: String {
        guard let date = modifiedDate else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Sortable date - returns a very old date for nil values so they sort last
    var sortableDate: Date {
        return modifiedDate ?? Date(timeIntervalSince1970: 0)
    }
}
