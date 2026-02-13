//
//  LocalizationManager.swift
//  SwiftMTP
//
//  Localization helper for internationalization
//

import Foundation

enum L10n {
    enum MainWindow {
        static var deviceList: String { LanguageManager.shared.localizedString(for: "deviceList") }
        static var noDeviceSelected: String { LanguageManager.shared.localizedString(for: "noDeviceSelected") }
        static var selectDeviceFromList: String { LanguageManager.shared.localizedString(for: "selectDeviceFromList") }
        static var refresh: String { LanguageManager.shared.localizedString(for: "refresh") }
        static var refreshFileList: String { LanguageManager.shared.localizedString(for: "refreshFileList") }
        static var refreshDeviceList: String { LanguageManager.shared.localizedString(for: "refreshDeviceList") }
        static var transferTasks: String { LanguageManager.shared.localizedString(for: "transferTasks") }
        static var viewTransferTasks: String { LanguageManager.shared.localizedString(for: "viewTransferTasks") }
        static var deviceDisconnected: String { LanguageManager.shared.localizedString(for: "deviceDisconnected") }
        static var ok: String { LanguageManager.shared.localizedString(for: "ok") }
        static var deviceDisconnectedMessage: String { LanguageManager.shared.localizedString(for: "deviceDisconnectedMessage") }
        static var androidDevice: String { LanguageManager.shared.localizedString(for: "androidDevice") }
    }

    enum DeviceList {
        static var devices: String { LanguageManager.shared.localizedString(for: "devices") }
        static var scanningDevices: String { LanguageManager.shared.localizedString(for: "scanningDevices") }
        static var noDevices: String { LanguageManager.shared.localizedString(for: "noDevices") }
        static var connectDeviceViaUSB: String { LanguageManager.shared.localizedString(for: "connectDeviceViaUSB") }
    }

    enum FileBrowser {
        static var deleteFile: String { LanguageManager.shared.localizedString(for: "deleteFile") }
        static var cancel: String { LanguageManager.shared.localizedString(for: "cancel") }
        static var delete: String { LanguageManager.shared.localizedString(for: "delete") }
        static var confirmDeleteFile: String { LanguageManager.shared.localizedString(for: "confirmDeleteFile") }
        static var operationFailed: String { LanguageManager.shared.localizedString(for: "operationFailed") }
        static var back: String { LanguageManager.shared.localizedString(for: "back") }
        static var goBack: String { LanguageManager.shared.localizedString(for: "goBack") }
        static var newFolder: String { LanguageManager.shared.localizedString(for: "newFolder") }
        static var createNewFolder: String { LanguageManager.shared.localizedString(for: "createNewFolder") }
        static var folder: String { LanguageManager.shared.localizedString(for: "folder") }
        static var create: String { LanguageManager.shared.localizedString(for: "create") }
        static var uploadFiles: String { LanguageManager.shared.localizedString(for: "uploadFiles") }
        static var uploadToCurrentDir: String { LanguageManager.shared.localizedString(for: "uploadToCurrentDir") }
        static var download: String { LanguageManager.shared.localizedString(for: "download") }
        static var downloadSelectedFiles: String { LanguageManager.shared.localizedString(for: "downloadSelectedFiles") }
        static var deleteSelectedFiles: String { LanguageManager.shared.localizedString(for: "deleteSelectedFiles") }
        static var folderEmpty: String { LanguageManager.shared.localizedString(for: "folderEmpty") }
        static var noFilesInFolder: String { LanguageManager.shared.localizedString(for: "noFilesInFolder") }
        static var dragFilesToUpload: String { LanguageManager.shared.localizedString(for: "dragFilesToUpload") }
        static var loadingFileList: String { LanguageManager.shared.localizedString(for: "loadingFileList") }
        static var deleteFailed: String { LanguageManager.shared.localizedString(for: "deleteFailed") }
        static var confirmDeleteFolder: String { LanguageManager.shared.localizedString(for: "confirmDeleteFolder") }
        static var moveToTrash: String { LanguageManager.shared.localizedString(for: "moveToTrash") }
        static var uploadSuccess: String { LanguageManager.shared.localizedString(for: "uploadSuccess") }
        static var uploadSuccessMessage: String { LanguageManager.shared.localizedString(for: "uploadSuccessMessage") }
        static var uploadFailed: String { LanguageManager.shared.localizedString(for: "uploadFailed") }
        static var uploadFailedMessage: String { LanguageManager.shared.localizedString(for: "uploadFailedMessage") }
        static var downloadSuccess: String { LanguageManager.shared.localizedString(for: "downloadSuccess") }
        static var downloadSuccessMessage: String { LanguageManager.shared.localizedString(for: "downloadSuccessMessage") }
        static var downloadFailed: String { LanguageManager.shared.localizedString(for: "downloadFailed") }
        static var downloadFailedMessage: String { LanguageManager.shared.localizedString(for: "downloadFailedMessage") }
        static var createFolderFailed: String { LanguageManager.shared.localizedString(for: "createFolderFailed") }
        static var createFolderFailedMessage: String { LanguageManager.shared.localizedString(for: "createFolderFailedMessage") }
        static var folderNamePlaceholder: String { LanguageManager.shared.localizedString(for: "folderNamePlaceholder") }
        static var name: String { LanguageManager.shared.localizedString(for: "name") }
        static var size: String { LanguageManager.shared.localizedString(for: "size") }
        static var type: String { LanguageManager.shared.localizedString(for: "type") }
        static var modifiedDate: String { LanguageManager.shared.localizedString(for: "modifiedDate") }
        static var rootDirectory: String { LanguageManager.shared.localizedString(for: "rootDirectory") }
        static var downloadFile: String { LanguageManager.shared.localizedString(for: "downloadFile") }
        static var downloadSelected: String { LanguageManager.shared.localizedString(for: "downloadSelected") }
        static var someFilesExist: String { LanguageManager.shared.localizedString(for: "someFilesExist") }
        static var filesExistMessage: String { LanguageManager.shared.localizedString(for: "filesExistMessage") }
        static var skip: String { LanguageManager.shared.localizedString(for: "skip") }
        static var skipExisting: String { LanguageManager.shared.localizedString(for: "skipExisting") }
        static var replaceAll: String { LanguageManager.shared.localizedString(for: "replaceAll") }
        static var replace: String { LanguageManager.shared.localizedString(for: "replace") }
        static var cancelDownload: String { LanguageManager.shared.localizedString(for: "cancelDownload") }
        static var selectDownloadLocation: String { LanguageManager.shared.localizedString(for: "selectDownloadLocation") }
        static var selectUploadFiles: String { LanguageManager.shared.localizedString(for: "selectUploadFiles") }
        static var selectUploadFolder: String { LanguageManager.shared.localizedString(for: "selectUploadFolder") }
        static var newFolderName: String { LanguageManager.shared.localizedString(for: "newFolderName") }
        static var enterFolderName: String { LanguageManager.shared.localizedString(for: "enterFolderName") }
        static var selectDestination: String { LanguageManager.shared.localizedString(for: "selectDestination") }
        static var cancelUpload: String { LanguageManager.shared.localizedString(for: "cancelUpload") }
        static var uploadFile: String { LanguageManager.shared.localizedString(for: "uploadFile") }
        static var uploadToDevice: String { LanguageManager.shared.localizedString(for: "uploadToDevice") }
        static var deleteConfirmTitle: String { LanguageManager.shared.localizedString(for: "deleteConfirmTitle") }
        static var deleteFolderConfirmMessage: String { LanguageManager.shared.localizedString(for: "deleteFolderConfirmMessage") }
        static var moveToTrashConfirm: String { LanguageManager.shared.localizedString(for: "moveToTrashConfirm") }
        static var downloadTo: String { LanguageManager.shared.localizedString(for: "downloadTo") }
        static var status: String { LanguageManager.shared.localizedString(for: "status") }
        static var progress: String { LanguageManager.shared.localizedString(for: "progress") }
        static var noFilesSelected: String { LanguageManager.shared.localizedString(for: "noFilesSelected") }
        static var selectFilesToOperate: String { LanguageManager.shared.localizedString(for: "selectFilesToOperate") }
        static var createNewFolderDialog: String { LanguageManager.shared.localizedString(for: "createNewFolderDialog") }
        static var uploadFilesToCurrentDir: String { LanguageManager.shared.localizedString(for: "uploadFilesToCurrentDir") }
        static var confirmDeleteFileWithName: String { LanguageManager.shared.localizedString(for: "confirmDeleteFileWithName") }
        static var operationFailedWithMessage: String { LanguageManager.shared.localizedString(for: "operationFailedWithMessage") }
        static var help: String { LanguageManager.shared.localizedString(for: "help") }
        static var createNewFolderHelp: String { LanguageManager.shared.localizedString(for: "createNewFolderHelp") }
        static var uploadFilesHelp: String { LanguageManager.shared.localizedString(for: "uploadFilesHelp") }
        static var downloadHelp: String { LanguageManager.shared.localizedString(for: "downloadHelp") }
        static var deleteHelp: String { LanguageManager.shared.localizedString(for: "deleteHelp") }
        static var loadingFiles: String { LanguageManager.shared.localizedString(for: "loadingFiles") }
        static var someFilesAlreadyExist: String { LanguageManager.shared.localizedString(for: "someFilesAlreadyExist") }
        static var filesAlreadyExistMessage: String { LanguageManager.shared.localizedString(for: "filesAlreadyExistMessage") }
        static var skipExistingFiles: String { LanguageManager.shared.localizedString(for: "skipExistingFiles") }
        static var chooseDownloadLocation: String { LanguageManager.shared.localizedString(for: "chooseDownloadLocation") }
        static var selectUploadLocation: String { LanguageManager.shared.localizedString(for: "selectUploadLocation") }
        static var uploadingTo: String { LanguageManager.shared.localizedString(for: "uploadingTo") }
        static var deleteMultipleFiles: String { LanguageManager.shared.localizedString(for: "deleteMultipleFiles") }
        static var confirmDeleteMultipleFiles: String { LanguageManager.shared.localizedString(for: "confirmDeleteMultipleFiles") }
        static var sort: String { LanguageManager.shared.localizedString(for: "sort") }
        static var sortFiles: String { LanguageManager.shared.localizedString(for: "sortFiles") }
    }

    enum FileTransfer {
        static var fileTransferTitle: String { LanguageManager.shared.localizedString(for: "fileTransferTitle") }
        static var fileTransfer: String { LanguageManager.shared.localizedString(for: "fileTransfer") }
        static var done: String { LanguageManager.shared.localizedString(for: "done") }
        static var closeTransferWindow: String { LanguageManager.shared.localizedString(for: "closeTransferWindow") }
        static var noTransferTasks: String { LanguageManager.shared.localizedString(for: "noTransferTasks") }
        static var noActiveTransfers: String { LanguageManager.shared.localizedString(for: "noActiveTransfers") }
        static var inProgress: String { LanguageManager.shared.localizedString(for: "inProgress") }
        static var completed: String { LanguageManager.shared.localizedString(for: "completed") }
        static var statusCompleted: String { LanguageManager.shared.localizedString(for: "completed") }
        static var clearCompleted: String { LanguageManager.shared.localizedString(for: "clearCompleted") }
        static var clearCompletedTasks: String { LanguageManager.shared.localizedString(for: "clearCompletedTasks") }
        static var clear: String { LanguageManager.shared.localizedString(for: "clear") }
        static var uploadType: String { LanguageManager.shared.localizedString(for: "uploadType") }
        static var downloadType: String { LanguageManager.shared.localizedString(for: "downloadType") }
        static var statusPending: String { LanguageManager.shared.localizedString(for: "statusPending") }
        static var statusTransferring: String { LanguageManager.shared.localizedString(for: "statusTransferring") }
        static var statusPaused: String { LanguageManager.shared.localizedString(for: "statusPaused") }
        static var statusFailed: String { LanguageManager.shared.localizedString(for: "statusFailed") }
        static var statusCancelled: String { LanguageManager.shared.localizedString(for: "statusCancelled") }
        static var estimatedTimeSeconds: String { LanguageManager.shared.localizedString(for: "estimatedTimeSeconds") }
        static var estimatedTimeMinutes: String { LanguageManager.shared.localizedString(for: "estimatedTimeMinutes") }
        static var estimatedTimeHours: String { LanguageManager.shared.localizedString(for: "estimatedTimeHours") }
        static var cannotCreateDirectory: String { LanguageManager.shared.localizedString(for: "cannotCreateDirectory") }
        static var cannotReplaceExistingFile: String { LanguageManager.shared.localizedString(for: "cannotReplaceExistingFile") }
        static var fileAlreadyExistsAtDestination: String { LanguageManager.shared.localizedString(for: "fileAlreadyExistsAtDestination") }
        static var deviceDisconnectedReconnect: String { LanguageManager.shared.localizedString(for: "deviceDisconnectedReconnect") }
        static var downloadedFileInvalidOrCorrupted: String { LanguageManager.shared.localizedString(for: "downloadedFileInvalidOrCorrupted") }
        static var downloadFailed: String { LanguageManager.shared.localizedString(for: "downloadFailed") }
        static var deviceDisconnectedCheckUSB: String { LanguageManager.shared.localizedString(for: "deviceDisconnectedCheckUSB") }
        static var checkConnectionAndStorage: String { LanguageManager.shared.localizedString(for: "checkConnectionAndStorage") }
        static var cannotReadFileInfo: String { LanguageManager.shared.localizedString(for: "cannotReadFileInfo") }
        static var uploadFailed: String { LanguageManager.shared.localizedString(for: "uploadFailed") }
    }

    enum Settings {
        static var general: String { LanguageManager.shared.localizedString(for: "general") }
        static var transfer: String { LanguageManager.shared.localizedString(for: "transfer") }
        static var advanced: String { LanguageManager.shared.localizedString(for: "advanced") }
        static var about: String { LanguageManager.shared.localizedString(for: "about") }
        static var downloadSettings: String { LanguageManager.shared.localizedString(for: "downloadSettings") }
        static var defaultDownloadLocation: String { LanguageManager.shared.localizedString(for: "defaultDownloadLocation") }
        static var select: String { LanguageManager.shared.localizedString(for: "select") }
        static var notifications: String { LanguageManager.shared.localizedString(for: "notifications") }
        static var showNotificationOnTransferComplete: String { LanguageManager.shared.localizedString(for: "showNotificationOnTransferComplete") }
        static var deviceDetection: String { LanguageManager.shared.localizedString(for: "deviceDetection") }
        static var scanInterval: String { LanguageManager.shared.localizedString(for: "scanInterval") }
        static var seconds: String { LanguageManager.shared.localizedString(for: "seconds") }
        static var appName: String { LanguageManager.shared.localizedString(for: "appName") }
        static var version: String { LanguageManager.shared.localizedString(for: "version") }
        static var author: String { LanguageManager.shared.localizedString(for: "author") }
        static var mtpFileTransferTool: String { LanguageManager.shared.localizedString(for: "mtpFileTransferTool") }
        static var copyright: String { LanguageManager.shared.localizedString(for: "copyright") }
        static var builtWith: String { LanguageManager.shared.localizedString(for: "builtWith") }
        // Update checking
        static var checkForUpdates: String { LanguageManager.shared.localizedString(for: "checkForUpdates") }
        static var checkingForUpdates: String { LanguageManager.shared.localizedString(for: "checkingForUpdates") }
        static var updateAvailable: String { LanguageManager.shared.localizedString(for: "updateAvailable") }
        static var updateAvailableTitle: String { LanguageManager.shared.localizedString(for: "updateAvailableTitle") }
        static var updateAvailableMessage: String { LanguageManager.shared.localizedString(for: "updateAvailableMessage") }
        static var noUpdateAvailableTitle: String { LanguageManager.shared.localizedString(for: "noUpdateAvailableTitle") }
        static var noUpdateMessage: String { LanguageManager.shared.localizedString(for: "noUpdateMessage") }
        static var downloadUpdate: String { LanguageManager.shared.localizedString(for: "downloadUpdate") }
        static var autoCheckUpdates: String { LanguageManager.shared.localizedString(for: "autoCheckUpdates") }
    }

    enum Common {
        static var path: String { LanguageManager.shared.localizedString(for: "path") }
        static var cancel: String { LanguageManager.shared.localizedString(for: "cancel") }
        static var ok: String { LanguageManager.shared.localizedString(for: "ok") }
        static var error: String { LanguageManager.shared.localizedString(for: "operationFailed") }
        static var language: String { LanguageManager.shared.localizedString(for: "language") }
        static var languageSettings: String { LanguageManager.shared.localizedString(for: "languageSettings") }
        static var selectLanguage: String { LanguageManager.shared.localizedString(for: "selectLanguage") }
        static var languageEnglish: String { LanguageManager.shared.localizedString(for: "languageEnglish") }
        static var languageChinese: String { LanguageManager.shared.localizedString(for: "languageChinese") }
        static var languageJapanese: String { LanguageManager.shared.localizedString(for: "languageJapanese") }
        static var languageKorean: String { LanguageManager.shared.localizedString(for: "languageKorean") }
        static var languageRussian: String { LanguageManager.shared.localizedString(for: "languageRussian") }
        static var languageFrench: String { LanguageManager.shared.localizedString(for: "languageFrench") }
        static var languageGerman: String { LanguageManager.shared.localizedString(for: "languageGerman") }
        static var languageChangeConfirm: String { LanguageManager.shared.localizedString(for: "languageChangeConfirm") }
        static var languageChangeMessage: String { LanguageManager.shared.localizedString(for: "languageChangeMessage") }
        static var languageChangeImmediate: String { LanguageManager.shared.localizedString(for: "languageChangeImmediate") }
        static var languageChangeRestart: String { LanguageManager.shared.localizedString(for: "languageChangeRestart") }
        static var apply: String { LanguageManager.shared.localizedString(for: "apply") }
        static var restartRequired: String { LanguageManager.shared.localizedString(for: "restartRequired") }
        static var restartMessage: String { LanguageManager.shared.localizedString(for: "restartMessage") }
        static var restartNow: String { LanguageManager.shared.localizedString(for: "restartNow") }
        static var restartLater: String { LanguageManager.shared.localizedString(for: "restartLater") }
        static var systemDefault: String { LanguageManager.shared.localizedString(for: "systemDefault") }
        static var swiftMtpHelp: String { LanguageManager.shared.localizedString(for: "swiftMtpHelp") }
    }

    enum DeviceError {
        static var deviceNotFound: String { LanguageManager.shared.localizedString(for: "deviceNotFound") }
        static var deviceDisconnected: String { LanguageManager.shared.localizedString(for: "deviceDisconnected") }
        static var deviceInitializationFailed: String { LanguageManager.shared.localizedString(for: "deviceInitializationFailed") }
        static var deviceBusy: String { LanguageManager.shared.localizedString(for: "deviceBusy") }
        static var deviceTimeout: String { LanguageManager.shared.localizedString(for: "deviceTimeout") }
        static var deviceNotSupported: String { LanguageManager.shared.localizedString(for: "deviceNotSupported") }
    }

    enum FileSystemError {
        static var fileNotFound: String { LanguageManager.shared.localizedString(for: "fileNotFound") }
        static var folderNotFound: String { LanguageManager.shared.localizedString(for: "folderNotFound") }
        static var fileAlreadyExists: String { LanguageManager.shared.localizedString(for: "fileAlreadyExists") }
        static var invalidPath: String { LanguageManager.shared.localizedString(for: "invalidPath") }
        static var pathTooLong: String { LanguageManager.shared.localizedString(for: "pathTooLong") }
        static var invalidFileName: String { LanguageManager.shared.localizedString(for: "invalidFileName") }
        static var permissionDenied: String { LanguageManager.shared.localizedString(for: "permissionDenied") }
        static var storageNotFound: String { LanguageManager.shared.localizedString(for: "storageNotFound") }
        static var storageFull: String { LanguageManager.shared.localizedString(for: "storageFull") }
    }

    enum TransferError {
        static var transferCancelled: String { LanguageManager.shared.localizedString(for: "transferCancelled") }
        static var transferFailed: String { LanguageManager.shared.localizedString(for: "transferFailed") }
        static var downloadFailed: String { LanguageManager.shared.localizedString(for: "downloadFailed") }
        static var uploadFailed: String { LanguageManager.shared.localizedString(for: "uploadFailed") }
        static var fileTooLarge: String { LanguageManager.shared.localizedString(for: "fileTooLarge") }
        static var insufficientStorage: String { LanguageManager.shared.localizedString(for: "insufficientStorage") }
        static var destinationDirectoryDoesNotExist: String { LanguageManager.shared.localizedString(for: "destinationDirectoryDoesNotExist") }
        static var fileAlreadyExistsAtDestination: String { LanguageManager.shared.localizedString(for: "fileAlreadyExistsAtDestination") }
        static var corruptedFile: String { LanguageManager.shared.localizedString(for: "corruptedFile") }
        static var networkError: String { LanguageManager.shared.localizedString(for: "networkError") }
        static var timeout: String { LanguageManager.shared.localizedString(for: "timeout") }
    }

    enum ConfigurationError {
        static var invalidConfiguration: String { LanguageManager.shared.localizedString(for: "invalidConfiguration") }
        static var missingConfiguration: String { LanguageManager.shared.localizedString(for: "missingConfiguration") }
        static var configurationLoadFailed: String { LanguageManager.shared.localizedString(for: "configurationLoadFailed") }
    }

    enum ScanError {
        static var scanFailed: String { LanguageManager.shared.localizedString(for: "scanFailed") }
        static var scanTimeout: String { LanguageManager.shared.localizedString(for: "scanTimeout") }
        static var scanCancelled: String { LanguageManager.shared.localizedString(for: "scanCancelled") }
        static var noDevicesFound: String { LanguageManager.shared.localizedString(for: "noDevicesFound") }
        static var maxRetriesExceeded: String { LanguageManager.shared.localizedString(for: "maxRetriesExceeded") }
    }
}

extension String {
    /// 格式化字符串，支持中文文件名
    /// - Parameter args: 格式化参数
    /// - Returns: 格式化后的字符串
    /// - Note: 此方法直接格式化当前字符串，不再尝试查找本地化
    func localized(_ args: CVarArg...) -> String {
        // 直接格式化当前字符串，不再尝试查找本地化
        // 避免对已经是本地化字符串的文本进行二次查找
        
        // 使用字符串替换而不是格式化，避免中文文件名乱码
        var result = self
        for (index, arg) in args.enumerated() {
            // 首先尝试带位置参数的格式（如 %1$@, %1$d）
            let positionalPlaceholder = "%\(index + 1)$@"
            if let argString = arg as? String {
                if result.contains(positionalPlaceholder) {
                    result = result.replacingOccurrences(of: positionalPlaceholder, with: argString)
                }
            } else {
                // 对于非字符串参数（如 Int），使用格式化
                let positionalFormattedPlaceholder = "%\(index + 1)$d"
                if let argInt = arg as? Int, result.contains(positionalFormattedPlaceholder) {
                    result = result.replacingOccurrences(of: positionalFormattedPlaceholder, with: String(argInt))
                }
            }
            
            // 如果没有带位置参数的占位符，尝试不带位置参数的格式（如 %@, %d）
            if !result.contains("%\(index + 1)$@") && !result.contains("%\(index + 1)$d") {
                if let argString = arg as? String {
                    result = result.replacingOccurrences(of: "%@", with: argString, options: .literal, range: result.range(of: "%@"))
                } else if let argInt = arg as? Int {
                    result = result.replacingOccurrences(of: "%d", with: String(argInt), options: .literal, range: result.range(of: "%d"))
                } else {
                    // 其他类型使用原始格式化方法
                    result = String(format: self, args)
                    break // 格式化成功，跳出循环
                }
            }
        }
        
        return result
    }
}