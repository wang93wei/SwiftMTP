
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
    @State private var isShowingRootBrowser = false

    enum SortOption: CaseIterable {
        case name
        case size
        case type
        case modifiedDate

        var displayName: String {
            switch self {
            case .name:
                return L10n.FileBrowser.name
            case .size:
                return L10n.FileBrowser.size
            case .type:
                return L10n.FileBrowser.type
            case .modifiedDate:
                return L10n.FileBrowser.modifiedDate
            }
        }
    }

    
    
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
    
    

    private struct EntryPoint: Identifiable, Hashable {
        enum Kind: Hashable {
            case recommended
            case browseAll
        }

        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let kind: Kind
        let folder: FileItem?
    }

    private let recommendedDirectoryNames: [(key: String, title: String, subtitle: String, systemImage: String)] = [
        ("dcim", L10n.FileBrowser.importDcimTitle, L10n.FileBrowser.importDcimSubtitle, "photo.stack.fill"),
        ("pictures", L10n.FileBrowser.importPicturesTitle, L10n.FileBrowser.importPicturesSubtitle, "photo.fill.on.rectangle.fill"),
        ("movies", L10n.FileBrowser.importMoviesTitle, L10n.FileBrowser.importMoviesSubtitle, "film.stack.fill"),
        ("download", L10n.FileBrowser.importDownloadsTitle, L10n.FileBrowser.importDownloadsSubtitle, "arrow.down.circle.fill")
    ]

    private var isAtRoot: Bool {
        currentPath.isEmpty
    }

    private var rootEntryPoints: [EntryPoint] {
        guard isAtRoot else { return [] }

        var entries: [EntryPoint] = []
        var usedFolders = Set<FileItem.ID>()

        for item in currentFiles where item.isDirectory {
            let normalizedName = item.name.lowercased()
            if let match = recommendedDirectoryNames.first(where: { normalizedName.contains($0.key) || $0.key.contains(normalizedName) }) {
                usedFolders.insert(item.id)
                entries.append(
                    EntryPoint(
                        id: item.id.uuidString,
                        title: match.title,
                        subtitle: match.subtitle,
                        systemImage: match.systemImage,
                        kind: .recommended,
                        folder: item
                    )
                )
            }
        }

        if entries.isEmpty {
            let fallbackFolders = currentFiles
                .filter(\.isDirectory)
                .prefix(3)

            entries.append(contentsOf: fallbackFolders.map { folder in
                usedFolders.insert(folder.id)
                return EntryPoint(
                    id: folder.id.uuidString,
                    title: folder.name,
                    subtitle: L10n.FileBrowser.importFallbackFolderSubtitle,
                    systemImage: "folder.fill",
                    kind: .recommended,
                    folder: folder
                )
            })
        }

        entries.append(
            EntryPoint(
                id: "browse-all",
                title: L10n.FileBrowser.importBrowseAllTitle,
                subtitle: L10n.FileBrowser.importBrowseAllSubtitle,
                systemImage: "tablecells.fill",
                kind: .browseAll,
                folder: nil
            )
        )

        return entries
    }

    var shouldShowImportHome: Bool {
        isAtRoot && !isShowingRootBrowser && !isLoading && !currentFiles.isEmpty
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
                isShowingRootBrowser = false
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
                            primaryToolbarContent

                            if shouldShowBrowsingToolbarActions {
                                browsingToolbarContent
                            }
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
            if !shouldShowImportHome {
                breadcrumbBar
                    .background(.ultraThinMaterial)
                Divider()
                    .opacity(0.15)
            }
            fileContentView
        }
    }

    @ViewBuilder
    var fileContentView: some View {
        let content: some View = Group {
            if isLoading {
                ProgressView(L10n.FileBrowser.loadingFiles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shouldShowImportHome {
                importHomeView
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
    
    var importHomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                importHeroCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(rootEntryPoints) { entry in
                        importEntryCard(for: entry)
                    }
                }

                browseHintView
            }
            .padding(24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    var importHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.FileBrowser.importHeroTitle, systemImage: "cable.connector")
                .font(.title2.weight(.semibold))

            Text(L10n.FileBrowser.importHeroSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(L10n.FileBrowser.importUsbConnected, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label(L10n.FileBrowser.importItemsReady.localized(currentFiles.count), systemImage: "externaldrive.fill.badge.checkmark")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func importEntryCard(for entry: EntryPoint) -> some View {
        Button {
            handleEntrySelection(entry)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: entry.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(entry.kind == .browseAll ? AnyShapeStyle(.secondary) : AnyShapeStyle(.blue))

                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(entry.kind == .browseAll ? L10n.FileBrowser.importOpenBrowser : L10n.FileBrowser.importOpenFolder)
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    var browseHintView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.FileBrowser.importBrowseHintTitle)
                .font(.headline)

            Text(L10n.FileBrowser.importBrowseHintSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func handleEntrySelection(_ entry: EntryPoint) {
        switch entry.kind {
        case .browseAll:
            isShowingRootBrowser = true
        case .recommended:
            guard let folder = entry.folder else { return }
            navigateInto(folder)
        }
    }

    
    var emptyFolderView: some View {
        VStack(spacing: 20) {
            emptyFolderIconView
            emptyFolderMessageView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            isShowingRootBrowser = false
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
