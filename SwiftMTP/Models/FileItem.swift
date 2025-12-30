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
        
        // MARK: - 日期边界值验证
        
        // 1. 检查日期是否在合理范围内（1970年1月1日之后）
        let minimumValidDate = Date(timeIntervalSince1970: 0)
        guard date >= minimumValidDate else { return "--" }
        
        // 2. 检查日期是否在未来（超过1天）
        let futureThreshold = Date().addingTimeInterval(86400)
        guard date <= futureThreshold else { return "--" }
        
        // MARK: - 格式化日期
        
        let formatter = DateFormatter()
        
        // 根据当前语言设置 locale
        var locale: Locale
        if let localeIdentifier = LanguageManager.shared.currentLanguage.localeIdentifier {
            locale = Locale(identifier: localeIdentifier)
        } else {
            // 系统默认模式：使用公开 API 获取系统语言
            let systemLanguages = Locale.preferredLanguages
            if let firstLang = systemLanguages.first {
                locale = Locale(identifier: firstLang)
            } else {
                locale = Locale.current
            }
        }
        
        formatter.locale = locale
        
        // 使用固定宽度的格式确保对齐
        // 中文：2024年12月26日 14:30
        // 英文：Dec 26, 2024, 2:30 PM
        // 安全检查：locale.language 可能为 nil
        if let languageCode = locale.language.languageCode?.identifier, languageCode == "zh" {
            // 中文格式：使用两位数月份确保对齐
            formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        } else {
            // 英文格式：使用固定格式确保对齐
            formatter.dateFormat = "MMM dd, yyyy, h:mm a"
        }
        
        return formatter.string(from: date)
    }
    
    // Sortable date - returns a very old date for nil values so they sort last
    var sortableDate: Date {
        return modifiedDate ?? Date(timeIntervalSince1970: 0)
    }
}
