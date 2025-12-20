//
//  FileBrowserView.swift
//  SwiftMTP
//
//  Main file browser view for exploring device files
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileBrowserView: View {
    let device: Device
    
    @State private var currentPath: [FileItem] = []
    @State private var currentFiles: [FileItem] = []
    @State private var selectedFiles: Set<FileItem.ID> = []
    @State private var isLoading = false
    @State private var pendingNavigation: FileItem?
    @State private var isDropTargeted = false

    @State private var showingDeleteAlert = false
    @State private var fileToDelete: FileItem?
    
    // Sorting state
    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        .init(\.name, order: .forward)
    ]
    
    // Create folder state
    @State private var showingCreateFolderDialog = false
    @State private var newFolderName = ""
    
    var body: some View {
        contentView
            .navigationTitle(device.displayName)
            .onAppear {
                loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshFileList"))) { _ in
                loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceDisconnected"))) { _ in
                // Reset view state when device disconnects
                currentPath.removeAll()
                currentFiles.removeAll()
                selectedFiles.removeAll()
                isLoading = false
            }
            .alert("删除文件", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let file = fileToDelete {
                        deleteFile(file)
                    }
                }
            } message: {
                if let file = fileToDelete {
                    Text("确定要删除 \"\(file.name)\" 吗？此操作无法撤销。")
                }
            }
            .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                navigateUp()
                            } label: {
                                Label("返回", systemImage: "chevron.left")
                                    .labelStyle(.iconOnly)
                            }
                            .help("返回上一级")
                            .disabled(currentPath.isEmpty)
                        }
                        
                        ToolbarItem {
                            Button("新建文件夹", systemImage: "folder.badge.plus") {
                                showingCreateFolderDialog = true
                            }
                            .help("创建新文件夹")
                        }
                        
                        ToolbarItem {
                            Button("上传文件", systemImage: "square.and.arrow.up") {
                                selectFilesToUpload()
                            }
                            .help("上传文件到当前目录")
                        }
                        
                        ToolbarItem {
                            Button {
                                deleteSelectedFiles()
                            } label: {
                                Label("删除", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(selectedFiles.isEmpty ? .secondary : .red)
                            }
                            .help("删除选中的文件")
                            .disabled(selectedFiles.isEmpty)
                        }
                    }
                    .toolbarLiquidGlass()            .sheet(isPresented: $showingCreateFolderDialog) {
                createFolderDialog
            }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            fileContentView
        }
    }
    
    @ViewBuilder
    private var fileContentView: some View {
        if isLoading {
            ProgressView("加载文件列表...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentFiles.isEmpty {
            ContentUnavailableView(
                "文件夹为空",
                systemImage: "folder",
                description: Text("此文件夹中没有文件")
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDroppedFiles(providers)
            }
        } else {
            fileTableView
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDroppedFiles(providers)
                }
        }
    }
    
    private var fileTableView: some View {
        Table(currentFiles, selection: $selectedFiles, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { file in
                nameCell(for: file)
            }
            .width(min: 200, ideal: 400)
            
            TableColumn("大小", value: \.size) { file in
                sizeCell(for: file)
            }
            .width(100)
            
            TableColumn("类型", value: \.fileType) { file in
                typeCell(for: file)
            }
            .width(120)
            
            TableColumn("修改日期", value: \.sortableDate) { file in
                dateCell(for: file)
            }
            .width(180)
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            applySorting()
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { items in
            fileContextMenu(for: items)
        }
        .overlay(
            TableDoubleClickModifier(
                onDoubleClick: handleDoubleClick
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: pendingNavigation) { oldValue, newValue in
            if let folder = newValue {
                print("onChange triggered, navigating to: \(folder.name)")
                navigateInto(folder)
                pendingNavigation = nil
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 2)
                    .background(.blue.opacity(0.1))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }
    
    private func nameCell(for file: FileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .tint(file.isDirectory ? .blue : .gray)
            Text(file.name)
        }
    }
    
    private func sizeCell(for file: FileItem) -> some View {
        Text(file.formattedSize)
    }
    
    private func typeCell(for file: FileItem) -> some View {
        Text(file.fileType)
    }
    
    private func dateCell(for file: FileItem) -> some View {
        Text(file.formattedDate)
    }
    
    private func handleDoubleClick() {
        print("Double click detected, selectedFiles: \(selectedFiles)")
        if let firstSelectedId = selectedFiles.first,
           let firstSelected = currentFiles.first(where: { $0.id == firstSelectedId }) {
            print("Found selected file: \(firstSelected.name), isDirectory: \(firstSelected.isDirectory)")
            if firstSelected.isDirectory {
                print("Setting pendingNavigation to: \(firstSelected.name)")
                pendingNavigation = firstSelected
            }
        } else {
            print("No selected file found")
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for items: Set<FileItem.ID>) -> some View {
        if items.count == 1, let fileId = items.first,
           let file = currentFiles.first(where: { $0.id == fileId }) {
            
            if !file.isDirectory {
                Button("下载", systemImage: "arrow.down.circle") {
                    downloadFile(file)
                }
            }
            
            Divider()
            
            Button("删除", systemImage: "trash", role: .destructive) {
                fileToDelete = file
                showingDeleteAlert = true
            }
        } else if items.count > 1 {
            Button("下载所选文件", systemImage: "arrow.down.circle") {
                downloadSelectedFiles()
            }
        }
    }
    
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    navigateToRoot()
                } label: {
                    Label("根目录", systemImage: "house.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                
                ForEach(Array(currentPath.enumerated()), id: \.element.id) { index, item in
                    Image(systemName: "chevron.right")
                        .tint(.secondary)
                        .font(.caption)
                    
                    Button {
                        navigateToPath(at: index)
                    } label: {
                        Text(item.name)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .liquidGlass(style: .thin, cornerRadius: 0, padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    private func loadFiles() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let files: [FileItem]
            
            if currentPath.isEmpty {
                files = FileSystemManager.shared.getRootFiles(for: device)
            } else if let parent = currentPath.last {
                files = FileSystemManager.shared.getChildrenFiles(for: device, parent: parent)
            } else {
                files = []
            }
            
            DispatchQueue.main.async {
                self.currentFiles = self.sortFiles(files)
                self.isLoading = false
            }
        }
    }
    
    private func sortFiles(_ files: [FileItem]) -> [FileItem] {
        // First separate folders and files
        let folders = files.filter { $0.isDirectory }
        let regularFiles = files.filter { !$0.isDirectory }
        
        // Sort each group using the sort order
        let sortedFolders = folders.sorted(using: sortOrder)
        let sortedFiles = regularFiles.sorted(using: sortOrder)
        
        // Folders always come first
        return sortedFolders + sortedFiles
    }
    
    private func applySorting() {
        currentFiles = sortFiles(currentFiles)
    }
    
    private func navigateInto(_ folder: FileItem) {
        currentPath.append(folder)
        loadFiles()
    }
    
    private func navigateUp() {
        guard !currentPath.isEmpty else { return }
        currentPath.removeLast()
        loadFiles()
    }
    
    private func navigateToRoot() {
        currentPath.removeAll()
        loadFiles()
    }
    
    private func navigateToPath(at index: Int) {
        currentPath = Array(currentPath.prefix(index + 1))
        loadFiles()
    }
    
    private func downloadFile(_ file: FileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: url)
            }
        }
    }
    
    private func downloadSelectedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择下载位置"
        
        panel.begin { response in
            if response == .OK, let directory = panel.url {
                let filesToDownload = currentFiles.filter { selectedFiles.contains($0.id) && !$0.isDirectory }
                for file in filesToDownload {
                    let destination = directory.appendingPathComponent(file.name)
                    FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                }
            }
        }
    }
    
    private func selectFilesToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        
        panel.begin { response in
            if response == .OK {
                // Determine parent ID: use current folder or root (0xFFFFFFFF)
                let parentId = currentPath.last?.objectId ?? 0xFFFFFFFF
                
                // Determine storage ID: use current path's storage or device's first storage
                let storageId: UInt32
                if let pathStorageId = currentPath.first?.storageId {
                    storageId = pathStorageId
                } else if let firstStorage = device.storageInfo.first {
                    storageId = firstStorage.storageId
                } else {
                    print("Error: No storage available for upload")
                    return
                }
                
                print("Uploading to parentId: \(parentId), storageId: \(storageId)")
                
                for url in panel.urls {
                    FileTransferManager.shared.uploadFile(to: device, sourceURL: url, parentId: parentId, storageId: storageId)
                }
            }
        }
    }
    
    private func deleteFile(_ file: FileItem) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Kalam_DeleteObject(file.objectId)
            let success = result > 0
            
            DispatchQueue.main.async {
                if success {
                    // Clear cache and reload
                    FileSystemManager.shared.clearCache(for: device)
                    loadFiles()
                } else {
                    // Show error alert
                    print("Failed to delete file: \(file.name)")
                    // TODO: Show error alert to user
                }
            }
        }
    }
    
    private func deleteSelectedFiles() {
        let filesToDelete = currentFiles.filter { selectedFiles.contains($0.id) }
        
        guard !filesToDelete.isEmpty else {
            return
        }
        
        // Prepare alert message
        let fileNames = filesToDelete.map { $0.name }.joined(separator: "、")
        let alertTitle = filesToDelete.count == 1 ? "删除文件" : "删除多个文件"
        let alertMessage = filesToDelete.count == 1 
            ? "确定要删除 \"\(filesToDelete.first!.name)\" 吗？此操作无法撤销。"
            : "确定要删除这 \(filesToDelete.count) 个文件吗？\n\n\(fileNames)\n\n此操作无法撤销。"
        
        // Create and show alert
        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = alertMessage
        alert.alertStyle = .critical
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "删除")
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertSecondButtonReturn {
                // User confirmed deletion
                performBatchDelete(files: filesToDelete)
            }
        }
    }
    
    private func performBatchDelete(files: [FileItem]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var deletedCount = 0
            var failedFiles: [String] = []
            
            for file in files {
                let result = Kalam_DeleteObject(file.objectId)
                if result > 0 {
                    deletedCount += 1
                } else {
                    failedFiles.append(file.name)
                }
            }
            
            DispatchQueue.main.async {
                // Clear cache and reload
                FileSystemManager.shared.clearCache(for: device)
                loadFiles()
                
                // Show result
                if failedFiles.isEmpty {
                    print("Successfully deleted \(deletedCount) files")
                } else {
                    print("Failed to delete some files: \(failedFiles.joined(separator: ", "))")
                }
                
                // Clear selection after deletion
                selectedFiles.removeAll()
            }
        }
    }
    
    // MARK: - Create Folder Dialog
    
    private var createFolderDialog: some View {
        VStack(spacing: 16) {
            Text("新建文件夹")
                .font(.headline)
            
            TextField("文件夹名称", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("取消") {
                    showingCreateFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)
                
                Button("创建") {
                    createFolder()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
    
    private func createFolder() {
        let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else { return }
        
        let parentId = currentPath.last?.objectId ?? 0xFFFFFFFF
        let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId ?? 0xFFFFFFFF
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = folderName.withCString { cString in
                Kalam_CreateFolder(storageId, parentId, UnsafeMutablePointer(mutating: cString))
            }
            let success = result > 0
            
            DispatchQueue.main.async {
                if success {
                    // Clear cache and reload
                    FileSystemManager.shared.clearCache(for: device)
                    loadFiles()
                    showingCreateFolderDialog = false
                    newFolderName = ""
                } else {
                    // Show error alert
                    print("Failed to create folder: \(folderName)")
                }
            }
        }
    }
    
    // MARK: - Drag & Drop Support
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard !currentPath.isEmpty || device.storageInfo.first != nil else {
            print("Cannot upload: No valid destination")
            return false
        }
        
        // Determine parent ID and storage ID
        let parentId = currentPath.last?.objectId ?? 0xFFFFFFFF
        let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId ?? 0xFFFFFFFF
        
        var fileURLs: [URL] = []
        
        // Extract file URLs from providers
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url as? URL {
                        DispatchQueue.main.async {
                            fileURLs.append(url)
                            
                            // Check if all files have been processed
                            if fileURLs.count == providers.count {
                                uploadDroppedFiles(fileURLs, parentId: parentId, storageId: storageId)
                            }
                        }
                    }
                }
            }
        }
        
        // Handle case where no files were loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if fileURLs.isEmpty {
                print("No valid files were dropped")
            }
        }
        
        return true
    }
    
    private func uploadDroppedFiles(_ urls: [URL], parentId: UInt32, storageId: UInt32) {
        print("Uploading \(urls.count) dropped files...")
        
        for url in urls {
            // Skip directories and hidden files
            var isDirectory: ObjCBool = false
            if url.lastPathComponent.hasPrefix(".") || 
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                print("Skipping: \(url.lastPathComponent) (hidden or directory)")
                continue
            }
            
            // Upload file
            FileTransferManager.shared.uploadFile(to: device, sourceURL: url, parentId: parentId, storageId: storageId)
        }
    }
}

// MARK: - Table Double Click Support

struct TableDoubleClickModifier: NSViewRepresentable {
    let onDoubleClick: () -> Void
    
    func makeNSView(context: Context) -> DoubleClickHelperView {
        let view = DoubleClickHelperView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    
    func updateNSView(_ nsView: DoubleClickHelperView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
    
    class DoubleClickHelperView: NSView {
        var onDoubleClick: (() -> Void)?
        private weak var tableView: NSTableView?
        private var retryCount = 0
        private let maxRetries = 30
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            print("DoubleClickHelperView: viewDidMoveToWindow called")
            setupDoubleClick()
        }
        
        private func setupDoubleClick() {
            guard tableView == nil else { 
                print("DoubleClickHelperView: tableView already set")
                return 
            }
            
            guard retryCount < maxRetries else {
                print("DoubleClickHelperView: Max retries reached, giving up")
                return
            }
            
            retryCount += 1
            print("DoubleClickHelperView: searching for NSTableView (attempt \(retryCount))...")
            
            // Search in the entire window's view hierarchy
            if let window = self.window {
                if let table = findTableView(in: window.contentView) {
                    print("DoubleClickHelperView: Found NSTableView!")
                    self.tableView = table
                    table.doubleAction = #selector(handleDoubleClick)
                    table.target = self
                    return
                }
            }
            
            print("DoubleClickHelperView: NSTableView not found, retrying...")
            // If not found, try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.setupDoubleClick()
            }
        }
        
        private func findTableView(in view: NSView?) -> NSTableView? {
            guard let view = view else { return nil }
            
            // Check if this view is a table view
            if let tableView = view as? NSTableView {
                return tableView
            }
            
            // Recursively search subviews
            for subview in view.subviews {
                if let found = findTableView(in: subview) {
                    return found
                }
            }
            
            return nil
        }
        
        @objc private func handleDoubleClick() {
            print("DoubleClickHelperView: handleDoubleClick called!")
            onDoubleClick?()
        }
    }
}

#Preview {
    NavigationStack {
        FileBrowserView(device: Device(
            deviceIndex: 0,
            name: "Pixel 7",
            manufacturer: "Google",
            model: "Pixel 7",
            serialNumber: "ABC123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(storageId: 1, maxCapacity: 128_000_000_000, freeSpace: 32_000_000_000, description: "内部存储")
            ]
        ))
    }
}
