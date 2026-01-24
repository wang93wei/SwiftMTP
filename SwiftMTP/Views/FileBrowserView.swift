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
    
    @Namespace private var toolbarNamespace
    
    @StateObject private var transferManager = FileTransferManager.shared
    @State private var showTransferPanel = false
    
    // Check if any selected items are folders
    private var hasSelectedFolders: Bool {
        currentFiles.contains { selectedFiles.contains($0.id) && $0.isDirectory }
    }
    
    // Check if there are downloadable files selected
    private var hasDownloadableFiles: Bool {
        !selectedFiles.isEmpty && !hasSelectedFolders
    }

    @State private var showingDeleteAlert = false
    @State private var fileToDelete: FileItem?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Sorting state
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    
    // Create folder state
    @State private var showingCreateFolderDialog = false
    @State private var newFolderName = ""

    // Upload file state
    @State private var pendingUploadFiles: [(url: URL, parentId: UInt32, storageId: UInt32)] = []
    @State private var showingUploadReplaceDialog = false
    @State private var filesToReplace: [(url: URL, existingFile: FileItem)] = []
    
    // MARK: - Sort Option
    
    enum SortOption: String, CaseIterable {
        case name
        case size
        case type
        case modifiedDate
        
        var displayName: String {
            switch self {
            case .name: return L10n.FileBrowser.name
            case .size: return L10n.FileBrowser.size
            case .type: return L10n.FileBrowser.type
            case .modifiedDate: return L10n.FileBrowser.modifiedDate
            }
        }
    }
    
    var body: some View {
        contentView
            .navigationTitle(device.displayName)
            .task {
                await loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshFileList"))) { _ in
                Task {
                    await loadFiles()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceDisconnected"))) { _ in
                // Reset view state when device disconnects
                currentPath.removeAll()
                currentFiles.removeAll()
                selectedFiles.removeAll()
                isLoading = false
            }
            .alert(L10n.FileBrowser.deleteFile, isPresented: $showingDeleteAlert) {
                Button(L10n.FileBrowser.cancel, role: .cancel) {}
                Button(L10n.FileBrowser.delete, role: .destructive) {
                    if let file = fileToDelete {
                        deleteFile(file)
                    }
                }
            } message: {
                if let file = fileToDelete {
                    Text(L10n.FileBrowser.confirmDeleteFileWithName.localized(file.name))
                }
            }
            .alert(L10n.FileBrowser.operationFailed, isPresented: $showingErrorAlert) {
                Button(L10n.MainWindow.ok) {}
            } message: {
                Text(errorMessage)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        navigateUp()
                    } label: {
                        Label(L10n.FileBrowser.back, systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .help(L10n.FileBrowser.goBack)
                    .disabled(currentPath.isEmpty)
                    .glassEffect()
                }

                ToolbarItem {
                    GlassEffectContainer(spacing: 1) {
                        HStack(spacing: 1) {
                            refreshButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            sortMenu
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            newFolderButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            uploadFilesButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            downloadButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            deleteButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                            transferTasksButton
                                .glassEffectUnion(id: "group1", namespace: toolbarNamespace)
                        }
                    }
                }
            }
            .sheet(isPresented: $showTransferPanel) {
                FileTransferView()
                    .environmentObject(transferManager)
                    .frame(minWidth: 600, minHeight: 400)
            }            .sheet(isPresented: $showingCreateFolderDialog) {
                createFolderDialog
            }
        
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            breadcrumbBar
                .background(.ultraThinMaterial)
            Divider()
                .opacity(0.15)
            fileContentView
        }
    }
    
    @ViewBuilder
    private var fileContentView: some View {
        let content: some View = Group {
            if isLoading {
                ProgressView(L10n.FileBrowser.loadingFiles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentFiles.isEmpty {
                emptyFolderView
            } else {
                fileTableView
            }
        }

        content
            .overlay(
                Group {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    }
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDroppedFiles(providers)
            }
            .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }
    
    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            emptyFolderIconView
            emptyFolderMessageView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var emptyFolderIconView: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 80)
            
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.blue)
        }
    }
    
    private var emptyFolderMessageView: some View {
        VStack(spacing: 8) {
            Text(L10n.FileBrowser.folderEmpty)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(L10n.FileBrowser.noFilesInFolder)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(L10n.FileBrowser.dragFilesToUpload)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var fileTableView: some View {
        Table(currentFiles, selection: $selectedFiles) {
            TableColumn(L10n.FileBrowser.name) { file in
                nameCell(for: file)
            }
            .width(min: 200, ideal: 400)

            TableColumn(L10n.FileBrowser.size) { file in
                sizeCell(for: file)
            }
            .width(100)

            TableColumn(L10n.FileBrowser.type) { file in
                typeCell(for: file)
            }
            .width(120)

            TableColumn(L10n.FileBrowser.modifiedDate) { file in
                dateCell(for: file)
            }
            .width(180)
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { items in
            fileContextMenu(for: items)
        }
        .overlay(
            TableDoubleClickModifier(
                onDoubleClick: handleDoubleClickWithItem
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 可排序的列标题
    private func sortableHeader(title: String, option: SortOption) -> some View {
        Button {
            print("[SortableHeader] Clicked on \(title)")
            if sortOption == option {
                sortAscending.toggle()
            } else {
                sortOption = option
                sortAscending = true
            }
            print("[SortableHeader] After click: sortOption=\(sortOption), sortAscending=\(sortAscending)")
            Task {
                await loadFiles()
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                if sortOption == option {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(.plain)
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
        // 根据文件类型返回本地化字符串
        let localizedType: String
        if file.fileType == "folder" {
            localizedType = L10n.FileBrowser.folder
        } else {
            localizedType = file.fileType
        }
        return Text(localizedType)
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

    private func handleDoubleClickWithItem(_ item: FileItem?) {
        // Use the provided item if available, otherwise use selectedFiles
        let targetItem = item ?? (selectedFiles.first.flatMap { selectedId in
            currentFiles.first { $0.id == selectedId }
        })

        guard let targetItem = targetItem else {
            print("handleDoubleClickWithItem: No item found")
            return
        }

        print("handleDoubleClickWithItem: Double clicked on \(targetItem.name), isDirectory: \(targetItem.isDirectory)")

        if targetItem.isDirectory {
            print("handleDoubleClickWithItem: Setting pendingNavigation to: \(targetItem.name)")
            pendingNavigation = targetItem
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for items: Set<FileItem.ID>) -> some View {
        if items.count == 1, let fileId = items.first,
           let file = currentFiles.first(where: { $0.id == fileId }) {
            
            if !file.isDirectory {
                Button(L10n.FileBrowser.download, systemImage: "arrow.down.circle") {
                    downloadFile(file)
                }
            }
            
            Divider()
            
            Button(L10n.FileBrowser.delete, systemImage: "trash", role: .destructive) {
                fileToDelete = file
                showingDeleteAlert = true
            }
        } else if items.count > 1 {
            Button(L10n.FileBrowser.downloadSelectedFiles, systemImage: "arrow.down.circle") {
                downloadSelectedFiles()
            }
            
            Divider()
            
            Button(L10n.FileBrowser.deleteSelectedFiles, systemImage: "trash", role: .destructive) {
                deleteSelectedFiles()
            }
        }
    }
    
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    navigateToRoot()
                } label: {
                    Label(L10n.FileBrowser.rootDirectory, systemImage: "house.fill")
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
            .scrollEdgeEffectStyle(.hard, for: .all)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onDrop(of: [.fileURL], delegate: RejectDropDelegate())
    }

    // MARK: - Drop Delegates

    /// 拒绝拖放的委托，用于防止拖放事件冒泡
    private struct RejectDropDelegate: DropDelegate {
        func validateDrop(info: DropInfo) -> Bool {
            return false
        }

        func performDrop(info: DropInfo) -> Bool {
            return false
        }
    }
    
    private func loadFiles() async {
        isLoading = true

        let files: [FileItem]

        if currentPath.isEmpty {
            files = await FileSystemManager.shared.getRootFiles(for: device)
        } else if let parent = currentPath.last {
            files = await FileSystemManager.shared.getChildrenFiles(for: device, parent: parent)
        } else {
            files = []
        }

        currentFiles = sortFiles(files)
        selectedFiles.removeAll()
        isLoading = false
    }
    
    private func sortFiles(_ files: [FileItem]) -> [FileItem] {
        print("[SortFiles] Sorting \(files.count) files, option: \(sortOption), ascending: \(sortAscending)")

        // First separate folders and files
        let folders = files.filter { $0.isDirectory }
        let regularFiles = files.filter { !$0.isDirectory }

        print("[SortFiles] Folders: \(folders.count), Files: \(regularFiles.count)")

        // Sort each group based on current sort option
        let sortedFolders: [FileItem]
        let sortedFiles: [FileItem]

        switch sortOption {
        case .name:
            print("[SortFiles] Sorting by name")
            sortedFolders = folders.sorted { $0.name.localizedStandardCompare($1.name) == (sortAscending ? .orderedAscending : .orderedDescending) }
            sortedFiles = regularFiles.sorted { $0.name.localizedStandardCompare($1.name) == (sortAscending ? .orderedAscending : .orderedDescending) }
        case .size:
            print("[SortFiles] Sorting by size")
            sortedFolders = folders.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
            sortedFiles = regularFiles.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
        case .type:
            print("[SortFiles] Sorting by type")
            sortedFolders = folders.sorted { $0.fileType.localizedStandardCompare($1.fileType) == (sortAscending ? .orderedAscending : .orderedDescending) }
            sortedFiles = regularFiles.sorted { $0.fileType.localizedStandardCompare($1.fileType) == (sortAscending ? .orderedAscending : .orderedDescending) }
        case .modifiedDate:
            print("[SortFiles] Sorting by modified date")
            sortedFolders = folders.sorted { sortAscending ? $0.sortableDate < $1.sortableDate : $0.sortableDate > $1.sortableDate }
            sortedFiles = regularFiles.sorted { sortAscending ? $0.sortableDate < $1.sortableDate : $0.sortableDate > $1.sortableDate }
        }

        // Folders always come first
        let result = sortedFolders + sortedFiles
        print("[SortFiles] Sorted result: \(result.count) items")
        return result
    }
    
    private func navigateInto(_ folder: FileItem) {
        Task {
            currentPath.append(folder)
            await loadFiles()
        }
    }
    
    private func navigateUp() {
        Task {
            guard !currentPath.isEmpty else { return }
            currentPath.removeLast()
            await loadFiles()
        }
    }
    
    private func navigateToRoot() {
        Task {
            currentPath.removeAll()
            await loadFiles()
        }
    }
    
    private func navigateToPath(at index: Int) {
        Task {
            currentPath = Array(currentPath.prefix(index + 1))
            await loadFiles()
        }
    }
    
    private func downloadFile(_ file: FileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // System NSSavePanel already handles file replacement confirmation
                // Just download directly - if file exists, system would have asked user
                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: url, shouldReplace: true)
            }
        }
    }
    
    private func downloadSelectedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.FileBrowser.chooseDownloadLocation

        // 在显示文件选择器之前，确保 AppleLanguages 设置正确
        LanguageManager.ensureAppleLanguages()

        panel.begin { response in
            if response == .OK, let directory = panel.url {
                let filesToDownload = currentFiles.filter { selectedFiles.contains($0.id) && !$0.isDirectory }
                
                // Check for existing files
                let existingFiles = filesToDownload.filter { file in
                    let destination = directory.appendingPathComponent(file.name)
                    return FileManager.default.fileExists(atPath: destination.path)
                }
                
                if !existingFiles.isEmpty {
                    // Show confirmation dialog for file replacement
                    let alert = NSAlert()
                    alert.messageText = L10n.FileBrowser.someFilesAlreadyExist
                    alert.informativeText = L10n.FileBrowser.filesAlreadyExistMessage.localized(
                        existingFiles.count,
                        existingFiles.map { "• \($0.name)" }.joined(separator: "\n")
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.FileBrowser.cancel)
                    alert.addButton(withTitle: L10n.FileBrowser.skipExistingFiles)
                    alert.addButton(withTitle: L10n.FileBrowser.replaceAll)
                    
                    if let window = NSApp.keyWindow {
                        alert.beginSheetModal(for: window) { response in
                            switch response {
                            case .alertSecondButtonReturn:
                                // Skip existing files
                                let filesToActuallyDownload = filesToDownload.filter { file in
                                    let destination = directory.appendingPathComponent(file.name)
                                    return !FileManager.default.fileExists(atPath: destination.path)
                                }
                                for file in filesToActuallyDownload {
                                    let destination = directory.appendingPathComponent(file.name)
                                    FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                                }
                            case .alertThirdButtonReturn:
                                // Replace all files
                                for file in filesToDownload {
                                    let destination = directory.appendingPathComponent(file.name)
                                    FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination, shouldReplace: true)
                                }
                            default:
                                // Cancel
                                break
                            }
                        }
                    } else {
                        // Fallback to modal dialog if no key window is available
                        let response = alert.runModal()
                        switch response {
                        case .alertSecondButtonReturn:
                            // Skip existing files
                            let filesToActuallyDownload = filesToDownload.filter { file in
                                let destination = directory.appendingPathComponent(file.name)
                                return !FileManager.default.fileExists(atPath: destination.path)
                            }
                            for file in filesToActuallyDownload {
                                let destination = directory.appendingPathComponent(file.name)
                                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                            }
                        case .alertThirdButtonReturn:
                            // Replace all files
                            for file in filesToDownload {
                                let destination = directory.appendingPathComponent(file.name)
                                FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination, shouldReplace: true)
                            }
                        default:
                            // Cancel
                            break
                        }
                    }
                } else {
                    // No existing files, download all normally
                    for file in filesToDownload {
                        let destination = directory.appendingPathComponent(file.name)
                        FileTransferManager.shared.downloadFile(from: device, fileItem: file, to: destination)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods

    /// 检查文件是否已存在于目标目录
    private func checkFileExists(_ fileName: String, parentId: UInt32) -> FileItem? {
        let existingFile = currentFiles.first { $0.name == fileName && !$0.isDirectory }
        if existingFile != nil {
            print("[checkFileExists] Found duplicate file: \(fileName)")
        }
        return existingFile
    }

    /// 显示文件替换确认对话框
    private func showFileReplaceDialog(existingFiles: [(url: URL, existingFile: FileItem)], completion: @escaping ([(url: URL, shouldReplace: Bool)]) -> Void) {
        print("[showFileReplaceDialog] Showing dialog for \(existingFiles.count) files")

        let alert = NSAlert()
        alert.messageText = L10n.FileBrowser.someFilesAlreadyExist
        alert.informativeText = L10n.FileBrowser.filesAlreadyExistMessage.localized(
            existingFiles.count,
            existingFiles.map { "• \($0.url.lastPathComponent)" }.joined(separator: "\n")
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.FileBrowser.cancel)
        alert.addButton(withTitle: L10n.FileBrowser.skipExistingFiles)
        alert.addButton(withTitle: L10n.FileBrowser.replaceAll)

        // Try to get a window - prefer key window, then main window, then any window
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first

        print("[showFileReplaceDialog] Window: \(window != nil)")

        if let window = window {
            alert.beginSheetModal(for: window) { response in
                print("[showFileReplaceDialog] User response: \(response)")
                switch response {
                case .alertSecondButtonReturn:
                    // Skip existing files
                    let filesToUpload = existingFiles.map { ($0.url, false) }
                    completion(filesToUpload)
                case .alertThirdButtonReturn:
                    // Replace all files
                    let filesToUpload = existingFiles.map { ($0.url, true) }
                    completion(filesToUpload)
                default:
                    // Cancel
                    completion([])
                }
            }
        } else {
            // If no window is available, cancel the operation
            print("[showFileReplaceDialog] No window available, cancelling")
            completion([])
        }
    }

    /// 处理待上传的文件，检查重复并显示确认对话框
    private func processUploadFiles(_ files: [(url: URL, parentId: UInt32, storageId: UInt32)]) {
        print("[processUploadFiles] Processing \(files.count) files")
        print("[processUploadFiles] Current directory has \(currentFiles.count) files")

        // Check for existing files
        var existingFiles: [(url: URL, existingFile: FileItem)] = []
        var newFiles: [(url: URL, parentId: UInt32, storageId: UInt32)] = []

        for file in files {
            print("[processUploadFiles] Checking file: \(file.url.lastPathComponent)")
            if let existingFile = checkFileExists(file.url.lastPathComponent, parentId: file.parentId) {
                existingFiles.append((url: file.url, existingFile: existingFile))
            } else {
                newFiles.append(file)
            }
        }

        print("[processUploadFiles] Found \(existingFiles.count) existing files, \(newFiles.count) new files")

        // If no existing files, upload all new files
        if existingFiles.isEmpty {
            print("[processUploadFiles] No existing files, uploading \(newFiles.count) new files directly")
            for file in newFiles {
                FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
            }
            return
        }

        print("[processUploadFiles] Showing replace dialog for \(existingFiles.count) files")

        // Show confirmation dialog for existing files
        showFileReplaceDialog(existingFiles: existingFiles) { decision in
            print("[processUploadFiles] User decision: \(decision.count) files to process")
            // Upload new files
            for file in newFiles {
                FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
            }

            // Upload existing files based on user decision
            for (url, shouldReplace) in decision {
                if shouldReplace {
                    let file = files.first { $0.url == url }!
                    FileTransferManager.shared.uploadFile(to: device, sourceURL: file.url, parentId: file.parentId, storageId: file.storageId)
                }
            }
        }
    }

    private func selectFilesToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        // 在显示文件选择器之前，确保 AppleLanguages 设置正确
        LanguageManager.ensureAppleLanguages()

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

                // Process files with duplicate checking
                let filesToUpload = panel.urls.map { (url: $0, parentId: parentId, storageId: storageId) }
                processUploadFiles(filesToUpload)
            }
        }
    }
    
    private func deleteFile(_ file: FileItem) {
        Task {
            let result = Kalam_DeleteObject(file.objectId)
            let success = result > 0

            if success {
                // Clear cache and reload
                await FileSystemManager.shared.clearCache(for: device)
                await loadFiles()
            } else {
                // Show error alert
                errorMessage = L10n.FileBrowser.operationFailedWithMessage.localized(file.name)
                showingErrorAlert = true
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
        let alertTitle = filesToDelete.count == 1 ? L10n.FileBrowser.deleteFile : L10n.FileBrowser.deleteMultipleFiles
        let alertMessage = filesToDelete.count == 1
            ? L10n.FileBrowser.confirmDeleteFileWithName.localized(filesToDelete.first!.name)
            : L10n.FileBrowser.confirmDeleteMultipleFiles.localized(filesToDelete.count, fileNames)
        
        // Create and show alert
        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = alertMessage
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.FileBrowser.cancel)
        alert.addButton(withTitle: L10n.FileBrowser.delete)
        
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn {
                    // User confirmed deletion
                    performBatchDelete(files: filesToDelete)
                }
            }
        } else {
            // Fallback to modal dialog if no key window is available
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                // User confirmed deletion
                performBatchDelete(files: filesToDelete)
            }
        }
    }
    
    private func performBatchDelete(files: [FileItem]) {
    Task {
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

        // Clear cache and reload
        await FileSystemManager.shared.clearCache(for: device)
        await loadFiles()

        // Show result
        if failedFiles.isEmpty {
            print("Successfully deleted \(deletedCount) files")
        } else {
            errorMessage = "The following files failed to delete:\n\n\(failedFiles.joined(separator: "\n"))"
            showingErrorAlert = true
        }

        // Clear selection after deletion
        selectedFiles.removeAll()
    }
}
    
    // MARK: - Toolbar Buttons
    
    private var refreshButton: some View {
        Button {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
        } label: {
            Label(L10n.MainWindow.refresh, systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.refreshFileList)
        .glassEffect()
    }
    
    private var transferTasksButton: some View {
        Button {
            showTransferPanel.toggle()
        } label: {
            Label(L10n.MainWindow.transferTasks, systemImage: "arrow.up.arrow.down.circle")
                .labelStyle(.iconOnly)
        }
        .help(L10n.MainWindow.viewTransferTasks)
        .glassEffect()
        .badge(transferManager.activeTasks.count)
    }
    
    private var newFolderButton: some View {
        Button(L10n.FileBrowser.newFolder, systemImage: "folder.badge.plus") {
            showingCreateFolderDialog = true
        }
        .help(L10n.FileBrowser.createNewFolderHelp)
        .glassEffect()
    }
    
    private var uploadFilesButton: some View {
        Button(L10n.FileBrowser.uploadFiles, systemImage: "square.and.arrow.up") {
            selectFilesToUpload()
        }
        .help(L10n.FileBrowser.uploadFilesHelp)
        .glassEffect()
    }
    
    private var downloadButton: some View {
        Button {
            downloadSelectedFiles()
        } label: {
            Label(L10n.FileBrowser.download, systemImage: "arrow.down.circle")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.downloadHelp)
        .disabled(!hasDownloadableFiles)
        .glassEffect()
    }
    
    private var deleteButton: some View {
        Button {
            deleteSelectedFiles()
        } label: {
            Label(L10n.FileBrowser.deleteFile, systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.deleteHelp)
        .disabled(selectedFiles.isEmpty)
        .tint(selectedFiles.isEmpty ? .secondary : .red)
        .glassEffect()
    }

    private var sortMenu: some View {
        Menu {
            Section {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        print("[SortMenu] Before: sortOption=\(sortOption), sortAscending=\(sortAscending)")
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = true
                        }
                        print("[SortMenu] After: sortOption=\(sortOption), sortAscending=\(sortAscending)")
                        Task {
                            await loadFiles()
                        }
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
        } label: {
            Label(L10n.FileBrowser.sort, systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .help(L10n.FileBrowser.sortFiles)
        .glassEffect()
    }

    // MARK: - Create Folder Dialog
    
    private var createFolderDialog: some View {
        VStack(spacing: 16) {
            Text(L10n.FileBrowser.createNewFolderDialog)
                .font(.headline)

            TextField(L10n.FileBrowser.folderNamePlaceholder, text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button(L10n.FileBrowser.cancel) {
                    showingCreateFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.FileBrowser.create) {
                    createFolder()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onDrop(of: [.fileURL], delegate: RejectDropDelegate())
    }
    
    private func createFolder() {
    let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !folderName.isEmpty else { return }

    let parentId = currentPath.last?.objectId ?? 0xFFFFFFFF
    let storageId = currentPath.first?.storageId ?? device.storageInfo.first?.storageId ?? 0xFFFFFFFF

    Task {
        let result = folderName.withCString { cString in
            Kalam_CreateFolder(storageId, parentId, UnsafeMutablePointer(mutating: cString))
        }
        let success = result > 0

        if success {
            // Clear cache and reload
            await FileSystemManager.shared.clearCache(for: device)
            await loadFiles()
            showingCreateFolderDialog = false
            newFolderName = ""
        } else {
            // Show error alert
            print("Failed to create folder: \(folderName)")
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
        let dispatchGroup = DispatchGroup()
        
        // Extract file URLs from providers
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                dispatchGroup.enter()
                provider.loadObject(ofClass: URL.self) { url, error in
                    defer {
                        dispatchGroup.leave()
                    }
                    
                    if let error = error {
                        print("Failed to load dropped file: \(error)")
                        return
                    }
                    
                    if let url = url as? URL {
                        fileURLs.append(url)
                    }
                }
            }
        }
        
        // Wait for all files to be loaded, then upload
        dispatchGroup.notify(queue: .main) {
            print("Loaded \(fileURLs.count) out of \(providers.count) dropped files")
            
            if fileURLs.isEmpty {
                print("No valid files were dropped")
                return
            }
            
            self.uploadDroppedFiles(fileURLs, parentId: parentId, storageId: storageId)
        }
        
        return true
    }
    
    private func uploadDroppedFiles(_ urls: [URL], parentId: UInt32, storageId: UInt32) {
        print("Uploading \(urls.count) dropped files...")

        var filesToUpload: [(url: URL, parentId: UInt32, storageId: UInt32)] = []

        for url in urls {
            // Skip directories and hidden files
            var isDirectory: ObjCBool = false
            if url.lastPathComponent.hasPrefix(".") ||
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                print("Skipping: \(url.lastPathComponent) (hidden or directory)")
                continue
            }

            filesToUpload.append((url: url, parentId: parentId, storageId: storageId))
        }

        // Process files with duplicate checking
        processUploadFiles(filesToUpload)
    }
}

// MARK: - Table Double Click Support

struct TableDoubleClickModifier: NSViewRepresentable {
    let onDoubleClick: (FileItem?) -> Void

    func makeNSView(context: Context) -> DoubleClickHelperView {
        let view = DoubleClickHelperView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickHelperView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    class DoubleClickHelperView: NSView {
        var onDoubleClick: ((FileItem?) -> Void)?
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

            guard let tableView = tableView else {
                print("DoubleClickHelperView: tableView is nil!")
                onDoubleClick?(nil)
                return
            }

            let clickedRow = tableView.clickedRow
            print("DoubleClickHelperView: clickedRow = \(clickedRow)")

            // Just return nil and let the caller handle it via selectedFiles
            // This is a simpler approach that works with SwiftUI Table
            onDoubleClick?(nil)
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
