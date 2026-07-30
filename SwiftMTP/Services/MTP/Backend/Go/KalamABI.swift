import Foundation

nonisolated struct KalamFileSystemABI: @unchecked Sendable {
    let open: (UnsafeMutablePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    let close: (UnsafeMutablePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    let list: (UnsafeMutablePointer<CChar>, UInt32, UInt32) -> UnsafeMutablePointer<CChar>?
    let free: (UnsafeMutablePointer<CChar>) -> Void
    let create: (
        UnsafeMutablePointer<CChar>,
        UInt32,
        UInt32,
        UnsafeMutablePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?
    let delete: (UnsafeMutablePointer<CChar>, UInt32) -> UnsafeMutablePointer<CChar>?
    let refresh: (UnsafeMutablePointer<CChar>, UInt32) -> UnsafeMutablePointer<CChar>?

    static let live = Self(
        open: Kalam_OpenSession,
        close: Kalam_CloseSession,
        list: Kalam_ListFilesSession,
        free: Kalam_FreeString,
        create: Kalam_CreateFolderSession,
        delete: Kalam_DeleteObjectSession,
        refresh: Kalam_RefreshStorageSession
    )
}

nonisolated struct KalamTransferABI: @unchecked Sendable {
    typealias Download = (
        UnsafeMutablePointer<CChar>,
        UInt32,
        UnsafeMutablePointer<CChar>,
        UnsafeMutablePointer<CChar>,
        @escaping MTPTransferProgress
    ) -> UnsafeMutablePointer<CChar>?
    typealias Upload = (
        UnsafeMutablePointer<CChar>,
        UInt32,
        UInt32,
        UnsafeMutablePointer<CChar>,
        UnsafeMutablePointer<CChar>,
        UInt64,
        UnsafeMutablePointer<CChar>,
        @escaping MTPTransferProgress
    ) -> UnsafeMutablePointer<CChar>?
    typealias TaskLifecycle = (UnsafeMutablePointer<CChar>) -> Int32

    let download: Download
    let upload: Upload
    let prepare: TaskLifecycle
    let cancel: (UnsafeMutablePointer<CChar>) -> Void
    let abort: TaskLifecycle

    static let live = Self(
        download: kalamDownloadFileSession,
        upload: kalamUploadFileSession,
        prepare: Kalam_PrepareTransferTask,
        cancel: Kalam_CancelTask,
        abort: Kalam_AbortTransferTask
    )
}

private nonisolated final class KalamProgressBox {
    let progress: MTPTransferProgress

    init(progress: @escaping MTPTransferProgress) {
        self.progress = progress
    }
}

@_cdecl("SwiftMTPKalamTransferProgress")
private nonisolated func swiftMTPKalamTransferProgress(
    bytes: UInt64,
    context: UInt
) {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: context) else {
        return
    }
    Unmanaged<KalamProgressBox>
        .fromOpaque(pointer)
        .takeUnretainedValue()
        .progress(bytes)
}

private nonisolated func kalamDownloadFileSession(
    token: UnsafeMutablePointer<CChar>,
    objectID: UInt32,
    destinationPath: UnsafeMutablePointer<CChar>,
    taskID: UnsafeMutablePointer<CChar>,
    progress: @escaping MTPTransferProgress
) -> UnsafeMutablePointer<CChar>? {
    let box = Unmanaged.passRetained(KalamProgressBox(progress: progress))
    defer { box.release() }
    let callback: @convention(c) (UInt64, UInt) -> Void = swiftMTPKalamTransferProgress
    return Kalam_DownloadFileSession(
        token,
        objectID,
        destinationPath,
        taskID,
        unsafeBitCast(callback, to: UInt.self),
        UInt(bitPattern: box.toOpaque())
    )
}

private nonisolated func kalamUploadFileSession(
    token: UnsafeMutablePointer<CChar>,
    storageID: UInt32,
    parentID: UInt32,
    sourcePath: UnsafeMutablePointer<CChar>,
    name: UnsafeMutablePointer<CChar>,
    size: UInt64,
    taskID: UnsafeMutablePointer<CChar>,
    progress: @escaping MTPTransferProgress
) -> UnsafeMutablePointer<CChar>? {
    let box = Unmanaged.passRetained(KalamProgressBox(progress: progress))
    defer { box.release() }
    let callback: @convention(c) (UInt64, UInt) -> Void = swiftMTPKalamTransferProgress
    return Kalam_UploadFileSession(
        token,
        storageID,
        parentID,
        sourcePath,
        name,
        size,
        taskID,
        unsafeBitCast(callback, to: UInt.self),
        UInt(bitPattern: box.toOpaque())
    )
}
