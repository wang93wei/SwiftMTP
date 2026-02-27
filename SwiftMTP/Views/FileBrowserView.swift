
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileBrowserView: View {
    let device: Device
    
    @State var currentPath: [FileItem] = []
    @State var currentFiles: [FileItem] = []
    @State var selectedFiles: Set<FileItem.ID> = []
    @State var isLoading = false
    @State var pendingNavigation: FileItem?
    @State var isDropTargeted = false
    
    @Namespace var toolbarNamespace
    
    @StateObject var transferManager = FileTransferManager.shared
    @State var showTransferPanel = false
    
    var hasSelectedFolders: Bool {
        currentFiles.contains { selectedFiles.contains($0.id) && $0.isDirectory }
    }
    
    var hasDownloadableFiles: Bool {
        !selectedFiles.isEmpty && !hasSelectedFolders
    }

    @State var showingDeleteAlert = false
    @State var fileToDelete: FileItem?
    @State var showingErrorAlert = false
    @State var errorMessage = ""
    
    @State var sortOption: SortOption = .name
    @State var sortAscending: Bool = true
    
    @State var showingCreateFolderDialog = false
    @State var newFolderName = ""

    
    
    var deleteAlertTitle: String {
        guard let file = fileToDelete else { return L10n.FileBrowser.deleteFile }
        return file.isDirectory ? L10n.FileBrowser.deleteFolder : L10n.FileBrowser.deleteFile
    }
    
    func deleteAlertMessage(for file: FileItem) -> String {
        if file.isDirectory {
            return L10n.FileBrowser.confirmDeleteFolderWithName.localized(file.name)
        } else {
            return L10n.FileBrowser.confirmDeleteFileWithName.localized(file.name)
        }
    }
    
    
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
                currentPath.removeAll()
                currentFiles.removeAll()
                selectedFiles.removeAll()
                isLoading = false
            }
            .alert(deleteAlertTitle, isPresented: $showingDeleteAlert) {
                Button(L10n.FileBrowser.cancel, role: .cancel) {}
                Button(L10n.FileBrowser.delete, role: .destructive) {
                    if let file = fileToDelete {
                        deleteFile(file)
                    }
                }
            } message: {
                if let file = fileToDelete {
                    Text(deleteAlertMessage(for: file))
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
    
    var contentView: some View {
        VStack(spacing: 0) {
            breadcrumbBar
                .background(.ultraThinMaterial)
            Divider()
                .opacity(0.15)
            fileContentView
        }
    }
    
    @ViewBuilder
    var fileContentView: some View {
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
    
    var emptyFolderView: some View {
        VStack(spacing: 16) {
            emptyFolderIconView
            emptyFolderMessageView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    var emptyFolderIconView: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 80)
            
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.blue)
        }
    }
    
    var emptyFolderMessageView: some View {
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
    var fileTableView: some View {
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
                navigateInto(folder)
                pendingNavigation = nil
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    
    func nameCell(for file: FileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .tint(file.isDirectory ? .blue : .gray)
            Text(file.name)
        }
    }
    
    func sizeCell(for file: FileItem) -> some View {
        Text(file.formattedSize)
    }
    
    func typeCell(for file: FileItem) -> some View {
        let localizedType: String
        if file.fileType == "folder" {
            localizedType = L10n.FileBrowser.folder
        } else {
            localizedType = file.fileType
        }
        return Text(localizedType)
    }
    
    func dateCell(for file: FileItem) -> some View {
        Text(file.formattedDate)
    }
    

    func handleDoubleClickWithItem(_ item: FileItem?) {
        let targetItem = item ?? (selectedFiles.first.flatMap { selectedId in
            currentFiles.first { $0.id == selectedId }
        })

        guard let targetItem = targetItem else {
            return
        }

        if targetItem.isDirectory {
            pendingNavigation = targetItem
        }
    }
    
    @ViewBuilder
    func fileContextMenu(for items: Set<FileItem.ID>) -> some View {
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
    
    var breadcrumbBar: some View {
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

    struct RejectDropDelegate: DropDelegate {
        func validateDrop(info: DropInfo) -> Bool {
            return false
        }

        func performDrop(info: DropInfo) -> Bool {
            return false
        }
    }
    
    func loadFiles() async {
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
    
    func sortFiles(_ files: [FileItem]) -> [FileItem] {

        let folders = files.filter { $0.isDirectory }
        let regularFiles = files.filter { !$0.isDirectory }

        let sortedFolders: [FileItem]
        let sortedFiles: [FileItem]

        switch sortOption {
        case .name:
            sortedFolders = folders.sorted { $0.name.localizedStandardCompare($1.name) == (sortAscending ? .orderedAscending : .orderedDescending) }
            sortedFiles = regularFiles.sorted { $0.name.localizedStandardCompare($1.name) == (sortAscending ? .orderedAscending : .orderedDescending) }
        case .size:
            sortedFolders = folders.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
            sortedFiles = regularFiles.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
        case .type:
            sortedFolders = folders.sorted { $0.fileType.localizedStandardCompare($1.fileType) == (sortAscending ? .orderedAscending : .orderedDescending) }
            sortedFiles = regularFiles.sorted { $0.fileType.localizedStandardCompare($1.fileType) == (sortAscending ? .orderedAscending : .orderedDescending) }
        case .modifiedDate:
            sortedFolders = folders.sorted { sortAscending ? $0.sortableDate < $1.sortableDate : $0.sortableDate > $1.sortableDate }
            sortedFiles = regularFiles.sorted { sortAscending ? $0.sortableDate < $1.sortableDate : $0.sortableDate > $1.sortableDate }
        }

        let result = sortedFolders + sortedFiles
        return result
    }
    
    func navigateInto(_ folder: FileItem) {
        Task {
            currentPath.append(folder)
            await loadFiles()
        }
    }
    
    func navigateUp() {
        Task {
            guard !currentPath.isEmpty else { return }
            currentPath.removeLast()
            await loadFiles()
        }
    }
    
    func navigateToRoot() {
        Task {
            currentPath.removeAll()
            await loadFiles()
        }
    }
    
    func navigateToPath(at index: Int) {
        Task {
            currentPath = Array(currentPath.prefix(index + 1))
            await loadFiles()
        }
    }
    
}

#Preview {
    NavigationStack {
        FileBrowserView(device: .preview)
    }
}
