import Darwin
import Foundation
@testable import SwiftMTP

final class GoMTPFilesystemAdapterState {
    let lock = NSLock()
    var payload = """
    {"ok":true,
     "files":[{"id":2,"parentId":4294967295,"storageId":1,"name":"a.txt","size":4,"isFolder":false,"modTime":0}],
     "failures":[{"storageId":1,"parentId":4294967295,"objectId":3,
                  "stage":"object_info","error":"invalid_object_handle"}]}
    """
    var freeCount = 0
    var openedDeviceIDs: [String] = []
    var receivedTokens: [String] = []
}

func makeGoMTPTestSnapshot(
    deviceID: MTPDeviceID,
    storageID: MTPStorageID
) -> MTPDeviceSnapshot {
    MTPDeviceSnapshot(
        deviceID: deviceID,
        name: "Phone",
        manufacturer: "Acme",
        model: "P",
        storages: [
            MTPStorage(
                id: storageID,
                description: "Internal",
                freeSpace: 1,
                maxCapacity: 2
            ),
        ]
    )
}

struct GoMTPFilesystemAdapterFixture {
    let deviceID: MTPDeviceID
    let storageID: MTPStorageID
    let state: GoMTPFilesystemAdapterState
    let session: any MTPBackendSession

    init() throws {
        let deviceID = try MTPDeviceID(validating: "go:5:2.4:18d1:4ee1")
        let storageID = try MTPStorageID(validating: 1)
        let state = GoMTPFilesystemAdapterState()
        let abi = KalamFileSystemABI(
            open: { pointer in
                state.openedDeviceIDs.append(String(cString: pointer))
                return strdup(#"{"ok":true,"token":"token-a"}"#)
            },
            close: { pointer in
                state.receivedTokens.append(String(cString: pointer))
                return strdup(#"{"ok":true}"#)
            },
            list: { pointer, _, _ in
                state.receivedTokens.append(String(cString: pointer))
                return strdup(state.payload)
            },
            free: { pointer in
                state.lock.withLock { state.freeCount += 1 }
                Darwin.free(pointer)
            },
            create: { pointer, _, _, _ in
                state.receivedTokens.append(String(cString: pointer))
                return strdup(#"{"ok":true,"objectId":9}"#)
            },
            delete: { pointer, _ in
                state.receivedTokens.append(String(cString: pointer))
                return strdup(#"{"ok":true}"#)
            },
            refresh: { pointer, _ in
                state.receivedTokens.append(String(cString: pointer))
                return strdup(
                    #"{"ok":true,"storage":{"id":1,"description":"Internal","freeSpace":1,"maxCapacity":2}}"#
                )
            }
        )
        let kernel = KalamMTPKernelBoundary(fileSystemABI: abi)
        kernel.recordSnapshots([
            makeGoMTPTestSnapshot(deviceID: deviceID, storageID: storageID),
        ])

        self.deviceID = deviceID
        self.storageID = storageID
        self.state = state
        self.session = try kernel.openSession(for: deviceID)
    }
}
