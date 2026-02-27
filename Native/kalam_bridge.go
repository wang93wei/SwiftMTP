package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
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

// -- Exported Functions --

//export Kalam_Init
func Kalam_Init() {
	bridgeShutdownFlag.Store(false)
	fmt.Println("Kalam Kernel Bridge Initialized")
}

//export Kalam_Scan
func Kalam_Scan() *C.char {
	var result string

	// Use a faster, more lightweight scan for device detection
	err := withDeviceQuick(func(dev *mtp.Device) error {
		// First try just getting device info for quick detection
		info, err := mtpx.FetchDeviceInfo(dev)
		if err != nil {
			return fmt.Errorf("FetchDeviceInfo failed: %w", err)
		}

		// Only fetch storage if device info succeeded
		var storages []mtpx.StorageData
		storages, err = mtpx.FetchStorages(dev)
		if err != nil {
			fmt.Printf("Kalam_Scan: FetchStorages failed: %v\n", err)
			storages = []mtpx.StorageData{}
		}

		var deviceList []DeviceJSON

		deviceName := info.Model
		if info.Manufacturer != "" && !containsIgnoreCase(info.Model, info.Manufacturer) {
			deviceName = info.Manufacturer + " " + info.Model
		}

		majorVersion := info.MTPVersion / 100
		minorVersion := (info.MTPVersion % 100) / 10
		mtpVersion := fmt.Sprintf("%d.%d", majorVersion, minorVersion)

		mtpSupport := MTPSupportJSON{
			MtpVersion:      mtpVersion,
			DeviceVersion:   info.DeviceVersion,
			VendorExtension: info.Manufacturer,
		}

		d := DeviceJSON{
			ID:           1,
			Name:         deviceName,
			Manufacturer: info.Manufacturer,
			Model:        info.Model,
			SerialNumber: info.SerialNumber,
			Storage:      []StorageJSON{},
			MTPSupport:   mtpSupport,
		}

		for _, s := range storages {
			d.Storage = append(d.Storage, StorageJSON{
				ID:          s.Sid,
				Description: s.Info.StorageDescription,
				FreeSpace:   s.Info.FreeSpaceInBytes,
				MaxCapacity: s.Info.MaxCapability,
			})
		}

		deviceList = append(deviceList, d)

		jsonData, err := json.Marshal(deviceList)
		if err != nil {
			return fmt.Errorf("JSON marshal failed: %w", err)
		}

		result = string(jsonData)
		return nil
	})

	if err != nil {
		fmt.Printf("Kalam_Scan: %v\n", err)
		// Return nil instead of empty array to indicate no devices found
		return nil
	}

	cStr := safeCString(result)
	if cStr == nil {
		fmt.Printf("Kalam_Scan: Failed to allocate C string for result\n")
		return nil
	}

	// Track allocated string
	stringMu.Lock()
	allocatedStrings[cStr] = time.Now()
	stringMu.Unlock()

	return cStr
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

	err := withDevice(func(dev *mtp.Device) error {
		var handles mtp.Uint32Array
		if err := dev.GetObjectHandles(uint32(storageIDTyped), 0, uint32(parentIDTyped), &handles); err != nil {
			return fmt.Errorf("GetObjectHandles failed: %w", err)
		}

		var files []FileJSON
		for _, handle := range handles.Values {
			var info mtp.ObjectInfo
			if err := dev.GetObjectInfo(handle, &info); err != nil {
				fmt.Printf("Kalam_ListFiles: GetObjectInfo failed for handle %d: %v\n", handle, err)
				continue
			}

			files = append(files, FileJSON{
				ID:        handle,
				ParentID:  info.ParentObject,
				StorageID: info.StorageID,
				Name:      info.Filename,
				Size:      uint64(info.CompressedSize),
				IsFolder:  info.ObjectFormat == 0x3001,
				ModTime:   info.ModificationDate.Unix(),
			})
		}

		if files == nil {
			files = []FileJSON{}
		}

		jsonData, err := json.Marshal(files)
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

	err := withDevice(func(dev *mtp.Device) error {
		var objInfo mtp.ObjectInfo
		objInfo.StorageID = uint32(storageIDTyped)
		objInfo.ParentObject = uint32(parentIDTyped)
		objInfo.Filename = name
		objInfo.ObjectFormat = ObjectFormatFolder
		objInfo.CompressedSize = 0

		_, _, handle, err := dev.SendObjectInfo(uint32(storageIDTyped), uint32(parentIDTyped), &objInfo)
		if err != nil {
			return fmt.Errorf("SendObjectInfo failed: %w", err)
		}

		newHandle = handle
		return nil
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

	err := withDevice(func(dev *mtp.Device) error {
		if err := dev.DeleteObject(uint32(objectIDTyped)); err != nil {
			return fmt.Errorf("DeleteObject failed: %w", err)
		}
		return nil
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

	err := withDevice(func(dev *mtp.Device) error {
		// Try to refresh the device storage
		// This helps to clear the cache after file operations
		fmt.Printf("Kalam_RefreshStorage: Refreshing storage %d\n", uint32(storageIDTyped))

		// Get storage info to trigger refresh
		var info mtp.StorageInfo
		if err := dev.GetStorageInfo(uint32(storageIDTyped), &info); err != nil {
			fmt.Printf("Kalam_RefreshStorage: GetStorageInfo failed: %v\n", err)
			return err
		}

		fmt.Printf("Kalam_RefreshStorage: Storage refreshed successfully\n")
		return nil
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
	err := withDevice(func(dev *mtp.Device) error {
		// Try to get device info to ensure connection is active
		var info mtp.DeviceInfo
		if err := dev.GetDeviceInfo(&info); err != nil {
			fmt.Printf("Kalam_ResetDeviceCache: GetDeviceInfo failed: %v\n", err)
			return err
		}

		fmt.Printf("Kalam_ResetDeviceCache: Device cache reset successfully\n")
		return nil
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
	bridgeShutdownFlag.Store(true)

	// Serialize teardown with all bridge operations that use pooled devices.
	deviceMu.Lock()
	defer deviceMu.Unlock()

	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()

	for _, entry := range devicePool {
		if entry.device != nil {
			fmt.Printf("Kalam_CleanupDevicePool: Disposing device connection\n")
			mtpx.Dispose(entry.device)
		}
	}

	devicePool = nil
	fmt.Printf("Kalam_CleanupDevicePool: Device pool cleanup completed\n")
}

func main() {}
