package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
	"unsafe"
)

var (
	cancelledTasks   sync.Map
	allocatedStrings = make(map[*C.char]time.Time)
	stringMu         sync.Mutex
)

// safeCString safely allocates a C string with size limit
func safeCString(s string) *C.char {
	if len(s) > cfg.Security.MaxCStringSize {
		fmt.Printf("safeCString: String too large (%d bytes, max %d)\n", len(s), cfg.Security.MaxCStringSize)
		return nil
	}
	return C.CString(s)
}

func trackedCString(s string) *C.char {
	result := safeCString(s)
	if result == nil {
		return nil
	}
	stringMu.Lock()
	allocatedStrings[result] = time.Now()
	stringMu.Unlock()
	return result
}

func bridgeJSON(value any) *C.char {
	data, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	return trackedCString(string(data))
}

type bridgeOpenResponse struct {
	OK    bool   `json:"ok"`
	Token string `json:"token,omitempty"`
	Error string `json:"error,omitempty"`
}

type bridgeListResponse struct {
	OK       bool                  `json:"ok"`
	Files    []FileJSON            `json:"files,omitempty"`
	Failures []nativeObjectFailure `json:"failures,omitempty"`
	Error    string                `json:"error,omitempty"`
}

type bridgeMutationResponse struct {
	OK       bool         `json:"ok"`
	ObjectID uint32       `json:"objectId,omitempty"`
	Storage  *StorageJSON `json:"storage,omitempty"`
	Error    string       `json:"error,omitempty"`
}

type bridgeScanResponse struct {
	OK       bool                `json:"ok"`
	Devices  []DeviceJSON        `json:"devices,omitempty"`
	Failures []nativeScanFailure `json:"failures,omitempty"`
	Error    string              `json:"error,omitempty"`
}

func nativeBridgeErrorCode(err error) string {
	switch {
	case err == nil:
		return ""
	case isDisconnectedNativeError(err):
		return "disconnected"
	case errors.Is(err, errStaleSessionToken):
		return "stale_token"
	case errors.Is(err, errUnknownSessionToken):
		return "unknown_token"
	case errors.Is(err, errNativeDisconnected):
		return "disconnected"
	case errors.Is(err, errBridgeShuttingDown):
		return "shutting_down"
	case errors.Is(err, errAmbiguousLegacySession):
		return "ambiguous_session"
	default:
		return "operation_failed"
	}
}

// -- Exported Functions --

//export Kalam_Init
func Kalam_Init() {
	bridgeRuntime.initialize()
	fmt.Println("Kalam Kernel Bridge Initialized")
}

//export Kalam_Scan
func Kalam_Scan() *C.char {
	result, err := scanNativeDevices(liveDeviceEnumerator, nativeSessions)
	if err != nil {
		fmt.Printf("Kalam_Scan: %v\n", err)
		return nil
	}
	return bridgeJSON(result.Devices)
}

//export Kalam_ScanResult
func Kalam_ScanResult() *C.char {
	result, err := scanNativeDevices(liveDeviceEnumerator, nativeSessions)
	if err != nil {
		return bridgeJSON(bridgeScanResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeScanResponse{
		OK:       true,
		Devices:  result.Devices,
		Failures: result.Failures,
	})
}

//export Kalam_OpenSession
func Kalam_OpenSession(deviceID *C.char) *C.char {
	if deviceID == nil {
		return bridgeJSON(bridgeOpenResponse{Error: "invalid_input"})
	}
	locator, err := parseUSBDeviceLocator(C.GoString(deviceID))
	if err != nil {
		return bridgeJSON(bridgeOpenResponse{Error: "invalid_input"})
	}
	token, err := nativeSessions.open(locator)
	if err != nil {
		return bridgeJSON(bridgeOpenResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeOpenResponse{OK: true, Token: token})
}

//export Kalam_CloseSession
func Kalam_CloseSession(token *C.char) *C.char {
	if token == nil || C.GoString(token) == "" {
		return bridgeJSON(bridgeMutationResponse{Error: "invalid_input"})
	}
	err := nativeSessions.close(C.GoString(token))
	if err != nil {
		return bridgeJSON(bridgeMutationResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeMutationResponse{OK: true})
}

//export Kalam_ListFilesSession
func Kalam_ListFilesSession(token *C.char, storageID uint32, parentID uint32) *C.char {
	if token == nil {
		return bridgeJSON(bridgeListResponse{Error: "invalid_input"})
	}
	var listing nativeDirectoryListing
	err := nativeSessions.withSession(C.GoString(token), func(session *nativeDeviceSession) error {
		var operationErr error
		listing, operationErr = session.listFiles(storageID, parentID)
		return operationErr
	})
	if err != nil {
		return bridgeJSON(bridgeListResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeListResponse{
		OK:       true,
		Files:    listing.Files,
		Failures: listing.Failures,
	})
}

//export Kalam_CreateFolderSession
func Kalam_CreateFolderSession(
	token *C.char,
	storageID uint32,
	parentID uint32,
	folderName *C.char,
) *C.char {
	if token == nil || folderName == nil {
		return bridgeJSON(bridgeMutationResponse{Error: "invalid_input"})
	}
	name := C.GoString(folderName)
	if name == "" {
		return bridgeJSON(bridgeMutationResponse{Error: "invalid_input"})
	}
	var handle uint32
	err := nativeSessions.withSession(C.GoString(token), func(session *nativeDeviceSession) error {
		var operationErr error
		handle, operationErr = session.createFolder(storageID, parentID, name)
		return operationErr
	})
	if err != nil {
		return bridgeJSON(bridgeMutationResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeMutationResponse{OK: true, ObjectID: handle})
}

//export Kalam_DeleteObjectSession
func Kalam_DeleteObjectSession(token *C.char, objectID uint32) *C.char {
	if token == nil {
		return bridgeJSON(bridgeMutationResponse{Error: "invalid_input"})
	}
	err := nativeSessions.withSession(C.GoString(token), func(session *nativeDeviceSession) error {
		return session.deleteObject(objectID)
	})
	if err != nil {
		return bridgeJSON(bridgeMutationResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeMutationResponse{OK: true})
}

//export Kalam_RefreshStorageSession
func Kalam_RefreshStorageSession(token *C.char, storageID uint32) *C.char {
	if token == nil {
		return bridgeJSON(bridgeMutationResponse{Error: "invalid_input"})
	}
	var storage StorageJSON
	err := nativeSessions.withSession(C.GoString(token), func(session *nativeDeviceSession) error {
		var operationErr error
		storage, operationErr = session.refreshStorage(storageID)
		return operationErr
	})
	if err != nil {
		return bridgeJSON(bridgeMutationResponse{Error: nativeBridgeErrorCode(err)})
	}
	return bridgeJSON(bridgeMutationResponse{OK: true, Storage: &storage})
}

//export Kalam_ListFiles
func Kalam_ListFiles(storageID uint32, parentID uint32) *C.char {
	// Convert to custom types for validation
	storageIDTyped := StorageID(storageID)
	parentIDTyped := ParentID(parentID)

	// Validate inputs and return error JSON if validation fails
	if err := storageIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_ListFiles: %v\n", err)
		errorJSON := fmt.Sprintf(`{"error": "INVALID_STORAGE_ID", "message": "%v"}`, err)
		return safeCString(errorJSON)
	}
	if err := parentIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_ListFiles: %v\n", err)
		errorJSON := fmt.Sprintf(`{"error": "INVALID_PARENT_ID", "message": "%v"}`, err)
		return safeCString(errorJSON)
	}

	var result string

	err := nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		listing, err := session.listFiles(uint32(storageIDTyped), uint32(parentIDTyped))
		if err != nil {
			return err
		}
		jsonData, err := json.Marshal(listing.Files)
		if err != nil {
			return fmt.Errorf("JSON marshal failed: %w", err)
		}

		result = string(jsonData)
		return nil
	})

	if err != nil {
		fmt.Printf("Kalam_ListFiles: %v\n", err)
		// Unified error handling: return nil to indicate error
		return nil
	}

	cStr := safeCString(result)
	if cStr == nil {
		fmt.Printf("Kalam_ListFiles: Failed to allocate C string for result\n")
		return nil
	}

	// Track allocated string
	stringMu.Lock()
	allocatedStrings[cStr] = time.Now()
	stringMu.Unlock()

	return cStr
}

//export Kalam_FreeString
func Kalam_FreeString(str *C.char) {
	if str == nil {
		return
	}

	// Remove from tracking
	stringMu.Lock()
	delete(allocatedStrings, str)
	stringMu.Unlock()

	C.free(unsafe.Pointer(str))
}

//export Kalam_CreateFolder
func Kalam_CreateFolder(storageID uint32, parentID uint32, folderName *C.char) uint32 {
	// Convert to custom types for validation
	storageIDTyped := StorageID(storageID)
	parentIDTyped := ParentID(parentID)

	// Validate inputs and return error codes if validation fails
	if err := storageIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_CreateFolder: %v\n", err)
		return 0xFFFFFFFF // Error code: INVALID_STORAGE_ID
	}
	if err := parentIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_CreateFolder: %v\n", err)
		return 0xFFFFFFFE // Error code: INVALID_PARENT_ID
	}

	if folderName == nil {
		fmt.Printf("Kalam_CreateFolder: folderName is nil\n")
		return 0xFFFFFFFD // Error code: INVALID_ARGUMENT
	}

	name := C.GoString(folderName)
	if name == "" {
		fmt.Printf("Kalam_CreateFolder: folderName is empty\n")
		return 0xFFFFFFFD // Error code: INVALID_ARGUMENT
	}

	// Validate folder name length
	if len(name) > cfg.Security.MaxFolderNameLength {
		fmt.Printf("Kalam_CreateFolder: folder name too long (%d chars)\n", len(name))
		return 0xFFFFFFFC // Error code: NAME_TOO_LONG
	}

	// Check for invalid characters
	invalidChars := []string{"/", "\\", ":", "*", "?", "\"", "<", ">", "|"}
	for _, char := range invalidChars {
		if strings.Contains(name, char) {
			fmt.Printf("Kalam_CreateFolder: folder name contains invalid character: %s\n", char)
			return 0
		}
	}

	var newHandle uint32

	err := nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		var operationErr error
		newHandle, operationErr = session.createFolder(
			uint32(storageIDTyped),
			uint32(parentIDTyped),
			name,
		)
		return operationErr
	})

	if err != nil {
		fmt.Printf("Kalam_CreateFolder: %v\n", err)
		return 0
	}

	return newHandle
}

//export Kalam_DeleteObject
func Kalam_DeleteObject(objectID uint32) int32 {
	// Convert to custom type for validation
	objectIDTyped := ObjectID(objectID)

	// Validate input
	if err := objectIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_DeleteObject: %v\n", err)
		return 0
	}

	err := nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		return session.deleteObject(uint32(objectIDTyped))
	})

	if err != nil {
		fmt.Printf("Kalam_DeleteObject: %v\n", err)
		return 0
	}

	return 1
}

//export Kalam_RefreshStorage
func Kalam_RefreshStorage(storageID uint32) int32 {
	// Convert to custom type for validation
	storageIDTyped := StorageID(storageID)

	// Validate input
	if err := storageIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_RefreshStorage: %v\n", err)
		return 0
	}

	err := nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		_, operationErr := session.refreshStorage(uint32(storageIDTyped))
		return operationErr
	})

	if err != nil {
		fmt.Printf("Kalam_RefreshStorage: %v\n", err)
		return 0
	}

	return 1
}

//export Kalam_ResetDeviceCache
func Kalam_ResetDeviceCache() int32 {
	fmt.Printf("Kalam_ResetDeviceCache: Attempting to reset device cache\n")

	// Force a device reset by closing and reopening
	// This is more aggressive but should clear all caches
	err := nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		if session.fetchDeviceInfo == nil {
			return fmt.Errorf("active exact session cannot inspect device")
		}
		_, operationErr := session.fetchDeviceInfo()
		return operationErr
	})

	if err != nil {
		fmt.Printf("Kalam_ResetDeviceCache: %v\n", err)
		return 0
	}

	return 1
}

// cleanupLeakedStrings cleans up leaked C string memory
// Call this function periodically to clean up strings that were not properly freed
func cleanupLeakedStrings() {
	stringMu.Lock()
	defer stringMu.Unlock()

	now := time.Now()
	const maxAge = 5 * time.Minute // Consider leaked after 5 minutes

	for str, allocTime := range allocatedStrings {
		if now.Sub(allocTime) > maxAge {
			fmt.Printf("Cleaning up leaked string allocated at %v\n", allocTime)
			C.free(unsafe.Pointer(str))
			delete(allocatedStrings, str)
		}
	}
}

//export Kalam_CleanupLeakedStrings
func Kalam_CleanupLeakedStrings() {
	cleanupLeakedStrings()
}

//export Kalam_CleanupDevicePool
func Kalam_CleanupDevicePool() {
	fmt.Printf("Kalam_CleanupDevicePool: Cleaning up all device connections\n")
	bridgeRuntime.cleanup()
	fmt.Printf("Kalam_CleanupDevicePool: Device pool cleanup completed\n")
}

func main() {}
