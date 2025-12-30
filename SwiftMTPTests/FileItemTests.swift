//
//  FileItemTests.swift
//  SwiftMTPTests
//
//  Unit tests for FileItem model
//

import XCTest
@testable import SwiftMTP

final class FileItemTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testFileItemInitialization() {
        let fileItem = FileItem(
            objectId: 1,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "txt"
        )
        
        XCTAssertEqual(fileItem.objectId, 1)
        XCTAssertEqual(fileItem.parentId, 0xFFFFFFFF)
        XCTAssertEqual(fileItem.storageId, 1)
        XCTAssertEqual(fileItem.name, "test.txt")
        XCTAssertEqual(fileItem.path, "/test.txt")
        XCTAssertEqual(fileItem.size, 1024)
        XCTAssertFalse(fileItem.isDirectory)
        XCTAssertEqual(fileItem.fileType, "txt")
        XCTAssertNotNil(fileItem.id)
    }
    
    func testFolderInitialization() {
        let folder = FileItem(
            objectId: 2,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "MyFolder",
            path: "/MyFolder",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: ""
        )
        
        XCTAssertEqual(folder.objectId, 2)
        XCTAssertEqual(folder.name, "MyFolder")
        XCTAssertEqual(folder.size, 0)
        XCTAssertTrue(folder.isDirectory)
        XCTAssertNil(folder.modifiedDate)
    }
    
    func testFileItemWithChildren() {
        let child1 = FileItem(
            objectId: 3,
            parentId: 2,
            storageId: 1,
            name: "child1.txt",
            path: "/MyFolder/child1.txt",
            size: 512,
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "txt"
        )
        
        let child2 = FileItem(
            objectId: 4,
            parentId: 2,
            storageId: 1,
            name: "child2.txt",
            path: "/MyFolder/child2.txt",
            size: 1024,
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "txt"
        )
        
        let folder = FileItem(
            objectId: 2,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "MyFolder",
            path: "/MyFolder",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "",
            children: [child1, child2]
        )
        
        XCTAssertNotNil(folder.children)
        XCTAssertEqual(folder.children?.count, 2)
    }
    
    // MARK: - File Extension Tests
    
    func testFileExtension() {
        // Test file with extension
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "document.pdf",
            path: "/document.pdf",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "pdf"
        )
        XCTAssertEqual(file1.fileExtension, "pdf")
        
        // Test file with multiple dots
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "archive.tar.gz",
            path: "/archive.tar.gz",
            size: 2048,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "gz"
        )
        XCTAssertEqual(file2.fileExtension, "gz")
        
        // Test file without extension
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "README",
            path: "/README",
            size: 512,
            modifiedDate: nil,
            isDirectory: false,
            fileType: ""
        )
        XCTAssertEqual(file3.fileExtension, "")
        
        // Test folder (should return empty)
        let folder = FileItem(
            objectId: 4,
            parentId: 0,
            storageId: 1,
            name: "MyFolder",
            path: "/MyFolder",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: ""
        )
        XCTAssertEqual(folder.fileExtension, "")
        
        // Test file with only dot
        let file4 = FileItem(
            objectId: 5,
            parentId: 0,
            storageId: 1,
            name: ".hidden",
            path: "/.hidden",
            size: 256,
            modifiedDate: nil,
            isDirectory: false,
            fileType: ""
        )
        XCTAssertEqual(file4.fileExtension, "")
    }
    
    // MARK: - Formatted Size Tests
    
    func testFormattedSize() {
        // Test bytes
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "small.txt",
            path: "/small.txt",
            size: 512,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        // 512 bytes may be displayed as "512 B" or "0 KB" depending on formatter
        XCTAssertFalse(file1.formattedSize.isEmpty)
        
        // Test kilobytes
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "medium.txt",
            path: "/medium.txt",
            size: 1024 * 500,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertTrue(file2.formattedSize.contains("KB") || file2.formattedSize.contains("MB"))
        
        // Test megabytes
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "large.txt",
            path: "/large.txt",
            size: 1024 * 1024 * 500,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertTrue(file3.formattedSize.contains("MB") || file3.formattedSize.contains("GB"))
        
        // Test gigabytes
        let file4 = FileItem(
            objectId: 4,
            parentId: 0,
            storageId: 1,
            name: "huge.txt",
            path: "/huge.txt",
            size: 5_000_000_000,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertTrue(file4.formattedSize.contains("GB"))
        
        // Test folder
        let folder = FileItem(
            objectId: 5,
            parentId: 0,
            storageId: 1,
            name: "Folder",
            path: "/Folder",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: ""
        )
        XCTAssertEqual(folder.formattedSize, "--")
        
        // Test zero size file
        let zeroFile = FileItem(
            objectId: 6,
            parentId: 0,
            storageId: 1,
            name: "empty.txt",
            path: "/empty.txt",
            size: 0,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertFalse(zeroFile.formattedSize.isEmpty)
    }
    
    func testFormattedSizeBoundaryConditions() {
        // Test very large file (close to UInt64 max)
        let hugeFile = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "huge.bin",
            path: "/huge.bin",
            size: UInt64.max / 2,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "bin"
        )
        XCTAssertFalse(hugeFile.formattedSize.isEmpty)
        
        // Test exact boundaries
        let kbFile = FileItem(objectId: 2, parentId: 0, storageId: 1, name: "1kb.txt", path: "/1kb.txt", size: 1024, modifiedDate: nil, isDirectory: false, fileType: "txt")
        let mbFile = FileItem(objectId: 3, parentId: 0, storageId: 1, name: "1mb.txt", path: "/1mb.txt", size: 1024 * 1024, modifiedDate: nil, isDirectory: false, fileType: "txt")
        let gbFile = FileItem(objectId: 4, parentId: 0, storageId: 1, name: "1gb.txt", path: "/1gb.txt", size: 1024 * 1024 * 1024, modifiedDate: nil, isDirectory: false, fileType: "txt")
        
        XCTAssertFalse(kbFile.formattedSize.isEmpty)
        XCTAssertFalse(mbFile.formattedSize.isEmpty)
        XCTAssertFalse(gbFile.formattedSize.isEmpty)
    }
    
    // MARK: - Formatted Date Tests
    
    func testFormattedDate() {
        // Test with valid date
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: date,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertNotEqual(file1.formattedDate, "--")
        XCTAssertTrue(file1.formattedDate.contains("2021") || file1.formattedDate.contains("01"))
        
        // Test with nil date
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test2.txt",
            path: "/test2.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file2.formattedDate, "--")
        
        // Test with current date
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "test3.txt",
            path: "/test3.txt",
            size: 1024,
            modifiedDate: Date(),
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertNotEqual(file3.formattedDate, "--")
    }
    
    func testFormattedDateBoundaryConditions() {
        // Test with date before epoch (invalid)
        let invalidDate1 = Date(timeIntervalSince1970: -1)
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: invalidDate1,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file1.formattedDate, "--")
        
        // Test with date far in future (invalid)
        let invalidDate2 = Date(timeIntervalSince1970: 10000000000)
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: invalidDate2,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file2.formattedDate, "--")
        
        // Test with epoch (valid boundary)
        let epochDate = Date(timeIntervalSince1970: 0)
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: epochDate,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertNotEqual(file3.formattedDate, "--")
        
        // Test with date just before tomorrow (valid)
        let tomorrowMinusOneSecond = Date().addingTimeInterval(86400 - 1)
        let file4 = FileItem(
            objectId: 4,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: tomorrowMinusOneSecond,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertNotEqual(file4.formattedDate, "--")
    }
    
    // MARK: - Sortable Date Tests
    
    func testSortableDate() {
        // Test with valid date
        let date1 = Date(timeIntervalSince1970: 1609459200)
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: date1,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file1.sortableDate, date1)
        
        // Test with nil date (should return epoch)
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file2.sortableDate, Date(timeIntervalSince1970: 0))
    }
    
    // MARK: - Comparable Tests
    
    func testComparableSorting() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "a.txt",
            path: "/a.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "b.txt",
            path: "/b.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "c.txt",
            path: "/c.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        var files = [file3, file1, file2]
        files.sort()
        
        XCTAssertEqual(files[0].name, "a.txt")
        XCTAssertEqual(files[1].name, "b.txt")
        XCTAssertEqual(files[2].name, "c.txt")
    }
    
    func testComparableCaseInsensitive() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "A.txt",
            path: "/A.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "b.txt",
            path: "/b.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "C.txt",
            path: "/C.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        var files = [file2, file3, file1]
        files.sort()
        
        XCTAssertEqual(files[0].name, "A.txt")
        XCTAssertEqual(files[1].name, "b.txt")
        XCTAssertEqual(files[2].name, "C.txt")
    }
    
    func testComparableWithNumbers() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "file1.txt",
            path: "/file1.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "file10.txt",
            path: "/file10.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "file2.txt",
            path: "/file2.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        var files = [file2, file3, file1]
        files.sort()
        
        XCTAssertEqual(files[0].name, "file1.txt")
        XCTAssertEqual(files[1].name, "file2.txt")
        XCTAssertEqual(files[2].name, "file10.txt")
    }
    
    // MARK: - Hashable and Equatable Tests
    
    func testHashable() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        XCTAssertNotEqual(file1.hashValue, file2.hashValue)
    }
    
    func testEquality() {
        let fileId = UUID()
        let file1 = FileItem(
            id: fileId,
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            id: fileId,
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file3 = FileItem(
            id: fileId,
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        XCTAssertEqual(file1, file2)
        XCTAssertNotEqual(file1, file3)
    }
    
    func testFileItemInSet() {
        let fileId = UUID()
        let file1 = FileItem(
            id: fileId,
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        let file2 = FileItem(
            id: fileId,
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test.txt",
            path: "/test.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        var fileSet: Set<FileItem> = []
        fileSet.insert(file1)
        fileSet.insert(file2)
        
        XCTAssertEqual(fileSet.count, 1)
    }
    
    // MARK: - Special Characters and Unicode Tests
    
    func testSpecialCharactersInName() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "test file with spaces.txt",
            path: "/test file with spaces.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file1.name, "test file with spaces.txt")
        
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "test-file_with_special.chars",
            path: "/test-file_with_special.chars",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: ""
        )
        XCTAssertEqual(file2.name, "test-file_with_special.chars")
    }
    
    func testUnicodeInName() {
        let file1 = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "测试文件.txt",
            path: "/测试文件.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file1.name, "测试文件.txt")
        
        let file2 = FileItem(
            objectId: 2,
            parentId: 0,
            storageId: 1,
            name: "ファイル.txt",
            path: "/ファイル.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file2.name, "ファイル.txt")
        
        let file3 = FileItem(
            objectId: 3,
            parentId: 0,
            storageId: 1,
            name: "파일.txt",
            path: "/파일.txt",
            size: 1024,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        XCTAssertEqual(file3.name, "파일.txt")
    }
    
    // MARK: - Large Values Tests
    
    func testLargeObjectId() {
        let file = FileItem(
            objectId: UInt32.max,
            parentId: UInt32.max,
            storageId: UInt32.max,
            name: "test.txt",
            path: "/test.txt",
            size: UInt64.max,
            modifiedDate: nil,
            isDirectory: false,
            fileType: "txt"
        )
        
        XCTAssertEqual(file.objectId, UInt32.max)
        XCTAssertEqual(file.parentId, UInt32.max)
        XCTAssertEqual(file.storageId, UInt32.max)
        XCTAssertEqual(file.size, UInt64.max)
    }
    
    func testLargeFileSize() {
        let file = FileItem(
            objectId: 1,
            parentId: 0,
            storageId: 1,
            name: "huge.bin",
            path: "/huge.bin",
            size: 10_000_000_000, // 10 GB
            modifiedDate: nil,
            isDirectory: false,
            fileType: "bin"
        )
        
        XCTAssertEqual(file.size, 10_000_000_000)
        XCTAssertTrue(file.formattedSize.contains("GB"))
    }
}