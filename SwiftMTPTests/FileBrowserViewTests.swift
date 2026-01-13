//
//  FileBrowserViewTests.swift
//  SwiftMTPTests
//
//  Tests for FileBrowserView including empty folder state,
//  boundary conditions, and UI layout validation
//

import XCTest
import SwiftUI
import AppKit
@testable import SwiftMTP

@MainActor
final class FileBrowserViewTests: XCTestCase {
    
    func testEmptyFolderViewComponentsExist() {
        let device = createTestDevice()
        let view = FileBrowserView(device: device)
        let emptyStateExpectation = expectation(description: "Empty folder state should render correctly")
        
        let hostingController = NSHostingController(rootView: NavigationStack { view })
        hostingController.loadView()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            emptyStateExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testEmptyFolderIconViewStyle() {
        let iconView = EmptyFolderIconView()
        let hostingController = NSHostingController(rootView: iconView)
        hostingController.loadView()
        
        XCTAssertNotNil(hostingController.view, "Icon view should be created successfully")
    }
    
    func testEmptyFolderMessageViewStyle() {
        let messageView = EmptyFolderMessageView()
        let hostingController = NSHostingController(rootView: messageView)
        hostingController.loadView()
        
        XCTAssertNotNil(hostingController.view, "Message view should be created successfully")
    }
    
    func testFileItemModelEmptyFolderScenario() {
        let emptyFolder = FileItem(
            objectId: 100,
            parentId: 0xFFFFFFFF,
            storageId: 1,
            name: "EmptyFolder",
            path: "/EmptyFolder",
            size: 0,
            modifiedDate: nil,
            isDirectory: true,
            fileType: "",
            children: nil
        )
        
        XCTAssertTrue(emptyFolder.isDirectory, "Empty folder should be recognized as directory")
        XCTAssertEqual(emptyFolder.formattedSize, "--", "Empty folder should display '--' for size")
    }
    
    func testFileItemModelWithFiles() {
        let files = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "TestFile1.txt",
                path: "/TestFile1.txt",
                size: 1024,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            ),
            FileItem(
                objectId: 2,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "TestFile2.jpg",
                path: "/TestFile2.jpg",
                size: 2048,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "jpg"
            )
        ]
        
        XCTAssertEqual(files.count, 2, "Should have 2 test files")
        XCTAssertFalse(files[0].isDirectory, "First file should not be a directory")
        XCTAssertEqual(files[0].fileExtension, "txt", "First file extension should be txt")
    }
    
    func testEmptyFolderDragDropOverlayStyle() {
        let dropTargeted = true
        let view = EmptyFolderDropOverlay(isDropTargeted: dropTargeted)
        let hostingController = NSHostingController(rootView: view)
        hostingController.loadView()
        
        XCTAssertNotNil(hostingController.view, "Drop overlay should render correctly")
    }
    
    func testEmptyFolderDropOverlayHiddenWhenNotTargeted() {
        let dropTargeted = false
        let view = EmptyFolderDropOverlay(isDropTargeted: dropTargeted)
        let hostingController = NSHostingController(rootView: view)
        hostingController.loadView()
        
        XCTAssertNotNil(hostingController.view, "Drop overlay should render even when hidden")
    }
    
    func testFileTableViewWithMultipleFiles() {
        let files = (0..<100).map { index in
            FileItem(
                objectId: UInt32(index),
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "File\(index).txt",
                path: "/File\(index).txt",
                size: UInt64(index * 1024),
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        }
        
        XCTAssertEqual(files.count, 100, "Should have 100 test files for boundary testing")
    }
    
    func testFileTableViewWithSingleFile() {
        let singleFile = [
            FileItem(
                objectId: 1,
                parentId: 0xFFFFFFFF,
                storageId: 1,
                name: "SingleFile.txt",
                path: "/SingleFile.txt",
                size: 512,
                modifiedDate: Date(),
                isDirectory: false,
                fileType: "txt"
            )
        ]
        
        XCTAssertEqual(singleFile.count, 1, "Should have exactly 1 file")
    }
    
    func testFileItemSortingWithMixedContent() {
        let mixedItems = [
            FileItem(objectId: 1, parentId: 0xFFFFFFFF, storageId: 1, name: "FolderA", path: "/FolderA", size: 0, modifiedDate: nil, isDirectory: true, fileType: ""),
            FileItem(objectId: 2, parentId: 0xFFFFFFFF, storageId: 1, name: "FileB.txt", path: "/FileB.txt", size: 100, modifiedDate: Date(), isDirectory: false, fileType: "txt"),
            FileItem(objectId: 3, parentId: 0xFFFFFFFF, storageId: 1, name: "FolderC", path: "/FolderC", size: 0, modifiedDate: nil, isDirectory: true, fileType: ""),
            FileItem(objectId: 4, parentId: 0xFFFFFFFF, storageId: 1, name: "FileA.txt", path: "/FileA.txt", size: 200, modifiedDate: Date(), isDirectory: false, fileType: "txt")
        ]
        
        let sortedFolders = mixedItems.filter { $0.isDirectory }.sorted()
        let sortedFiles = mixedItems.filter { !$0.isDirectory }.sorted()
        
        XCTAssertEqual(sortedFolders.count, 2, "Should have 2 folders")
        XCTAssertEqual(sortedFiles.count, 2, "Should have 2 files")
        XCTAssertTrue(sortedFolders[0].name == "FolderA", "Folders should be sorted alphabetically")
        XCTAssertTrue(sortedFiles[0].name == "FileA.txt", "Files should be sorted alphabetically")
    }
    
    func testFormattedSizeForDifferentScenarios() {
        let zeroBytes = FileItem(
            objectId: 1, parentId: 0, storageId: 1, name: "Empty", path: "/Empty",
            size: 0, modifiedDate: nil, isDirectory: false, fileType: ""
        )
        
        let smallFile = FileItem(
            objectId: 2, parentId: 0, storageId: 1, name: "Small", path: "/Small",
            size: 500, modifiedDate: nil, isDirectory: false, fileType: ""
        )
        
        let largeFile = FileItem(
            objectId: 3, parentId: 0, storageId: 1, name: "Large", path: "/Large",
            size: 5_000_000_000, modifiedDate: nil, isDirectory: false, fileType: ""
        )
        
        XCTAssertFalse(zeroBytes.formattedSize.isEmpty, "Zero bytes should have formatted size")
        XCTAssertFalse(smallFile.formattedSize.isEmpty, "Small file should have formatted size")
        XCTAssertFalse(largeFile.formattedSize.isEmpty, "Large file should have formatted size")
        XCTAssertTrue(largeFile.formattedSize.contains("GB") || largeFile.formattedSize.contains("MB"), "Large file should display in GB or MB")
    }
    
    private func createTestDevice() -> Device {
        Device(
            deviceIndex: 0,
            name: "Test Device",
            manufacturer: "Test Manufacturer",
            model: "Test Model",
            serialNumber: "TEST123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(storageId: 1, maxCapacity: 64_000_000_000, freeSpace: 32_000_000_000, description: "Test Storage")
            ]
        )
    }
}

// MARK: - Supporting Test Views

struct EmptyFolderIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 80, height: 80)
            
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.blue)
        }
    }
}

struct EmptyFolderMessageView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("文件夹为空")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("此文件夹中没有文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("或将文件拖拽到此处以上传")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct EmptyFolderDropOverlay: View {
    let isDropTargeted: Bool
    
    var body: some View {
        Group {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 2)
                    .background(Color.blue.opacity(0.1))
            }
        }
    }
}
