package main

import (
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

// MARK: - Custom Types

// StorageID represents a unique storage identifier on the MTP device
type StorageID uint32

// Validate checks if the storage ID is valid
func (id StorageID) Validate() error {
	if id == 0 {
		return fmt.Errorf("invalid storage ID: %d", id)
	}
	return nil
}

// String returns the string representation of the storage ID
func (id StorageID) String() string {
	return fmt.Sprintf("StorageID(%d)", uint32(id))
}

// ObjectID represents a unique object identifier on the MTP device
type ObjectID uint32

// Validate checks if the object ID is valid
func (id ObjectID) Validate() error {
	if id == 0 {
		return fmt.Errorf("invalid object ID: %d", id)
	}
	return nil
}

// String returns the string representation of the object ID
func (id ObjectID) String() string {
	return fmt.Sprintf("ObjectID(%d)", uint32(id))
}

// ParentID represents a parent directory identifier on the MTP device
type ParentID uint32

// Validate checks if the parent ID is valid
func (id ParentID) Validate() error {
	// ParentID can be 0xFFFFFFFF for root directory
	if id == 0 && id != 0xFFFFFFFF {
		return fmt.Errorf("invalid parent ID: %d", id)
	}
	return nil
}

// String returns the string representation of the parent ID
func (id ParentID) String() string {
	return fmt.Sprintf("ParentID(%d)", uint32(id))
}

// MARK: - Interfaces

// DeviceManager defines the contract for device operations
// This interface abstracts device management operations for better testability
type DeviceManager interface {
	// Scan scans for connected MTP devices
	Scan() ([]DeviceJSON, error)

	// Initialize initializes the device connection
	Initialize() error

	// Dispose disposes the device connection
	Dispose() error

	// GetDeviceInfo retrieves device information
	GetDeviceInfo() (*mtp.DeviceInfo, error)

	// GetStorages retrieves storage information
	GetStorages() ([]mtpx.StorageData, error)
}

// FileSystemManager defines the contract for file system operations
// This interface abstracts file system operations for better testability
type FileSystemManager interface {
	// ListFiles lists files in a directory
	ListFiles(storageID StorageID, parentID ParentID) ([]FileJSON, error)

	// CreateFolder creates a new folder
	CreateFolder(storageID StorageID, parentID ParentID, name string) (ObjectID, error)

	// DeleteObject deletes a file or folder
	DeleteObject(objectID ObjectID) error

	// DownloadFile downloads a file from the device
	DownloadFile(objectID ObjectID, destPath string, taskID string) error

	// UploadFile uploads a file to the device
	UploadFile(storageID StorageID, parentID ParentID, srcPath string, taskID string) error

	// RefreshStorage refreshes the device storage cache
	RefreshStorage(storageID StorageID) error
}

// MARK: - Interface Implementations

// mtpDeviceManager implements the DeviceManager interface
// This provides a concrete implementation for device management operations
type mtpDeviceManager struct {
	pool []*devicePoolEntry
	mu   sync.RWMutex
}

// Scan scans for connected MTP devices
func (m *mtpDeviceManager) Scan() ([]DeviceJSON, error) {
	var result string

	err := withDeviceQuick(func(dev *mtp.Device) error {
		info, err := mtpx.FetchDeviceInfo(dev)
		if err != nil {
			return fmt.Errorf("FetchDeviceInfo failed: %w", err)
		}

		var storages []mtpx.StorageData
		storages, err = mtpx.FetchStorages(dev)
		if err != nil {
			fmt.Printf("Scan: FetchStorages failed: %v\n", err)
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
		return nil, err
	}

	var devices []DeviceJSON
	if err := json.Unmarshal([]byte(result), &devices); err != nil {
		return nil, fmt.Errorf("JSON unmarshal failed: %w", err)
	}

	return devices, nil
}

// Initialize initializes the device connection
func (m *mtpDeviceManager) Initialize() error {
	dev, err := mtpx.Initialize(mtpx.Init{
		DebugMode: false,
	})
	if err != nil {
		return fmt.Errorf("failed to initialize device: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	entry := &devicePoolEntry{
		device:   dev,
		lastUsed: time.Now(),
		inUse:    true,
	}

	m.pool = append(m.pool, entry)
	return nil
}

// Dispose disposes the device connection
func (m *mtpDeviceManager) Dispose() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, entry := range m.pool {
		if entry.device != nil {
			mtpx.Dispose(entry.device)
		}
	}

	m.pool = nil
	return nil
}

// GetDeviceInfo retrieves device information
func (m *mtpDeviceManager) GetDeviceInfo() (*mtp.DeviceInfo, error) {
	var info *mtp.DeviceInfo

	err := withDeviceQuick(func(dev *mtp.Device) error {
		var devInfo mtp.DeviceInfo
		if err := dev.GetDeviceInfo(&devInfo); err != nil {
			return fmt.Errorf("GetDeviceInfo failed: %w", err)
		}
		info = &devInfo
		return nil
	})

	return info, err
}

// GetStorages retrieves storage information
func (m *mtpDeviceManager) GetStorages() ([]mtpx.StorageData, error) {
	var storages []mtpx.StorageData

	err := withDeviceQuick(func(dev *mtp.Device) error {
		var s []mtpx.StorageData
		var err error
		s, err = mtpx.FetchStorages(dev)
		if err != nil {
			return fmt.Errorf("FetchStorages failed: %w", err)
		}
		storages = s
		return nil
	})

	return storages, err
}

// fileSystemManager implements the FileSystemManager interface
// This provides a concrete implementation for file system operations
type fileSystemManager struct{}

// ListFiles lists files in a directory
func (m *fileSystemManager) ListFiles(storageID StorageID, parentID ParentID) ([]FileJSON, error) {
	var result string

	err := withDevice(func(dev *mtp.Device) error {
		var handles mtp.Uint32Array
		if err := dev.GetObjectHandles(uint32(storageID), 0, uint32(parentID), &handles); err != nil {
			return fmt.Errorf("GetObjectHandles failed: %w", err)
		}

		var files []FileJSON
		for _, handle := range handles.Values {
			var info mtp.ObjectInfo
			if err := dev.GetObjectInfo(handle, &info); err != nil {
				fmt.Printf("ListFiles: GetObjectInfo failed for handle %d: %v\n", handle, err)
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
		return nil, err
	}

	var files []FileJSON
	if err := json.Unmarshal([]byte(result), &files); err != nil {
		return nil, fmt.Errorf("JSON unmarshal failed: %w", err)
	}

	return files, nil
}

// CreateFolder creates a new folder
func (m *fileSystemManager) CreateFolder(storageID StorageID, parentID ParentID, name string) (ObjectID, error) {
	if name == "" {
		return 0, fmt.Errorf("folder name cannot be empty")
	}

	if len(name) > cfg.Security.MaxFolderNameLength {
		return 0, fmt.Errorf("folder name too long (%d chars)", len(name))
	}

	var newHandle uint32

	err := withDevice(func(dev *mtp.Device) error {
		var objInfo mtp.ObjectInfo
		objInfo.StorageID = uint32(storageID)
		objInfo.ParentObject = uint32(parentID)
		objInfo.Filename = name
		objInfo.ObjectFormat = ObjectFormatFolder
		objInfo.CompressedSize = 0

		_, _, handle, err := dev.SendObjectInfo(uint32(storageID), uint32(parentID), &objInfo)
		if err != nil {
			return fmt.Errorf("SendObjectInfo failed: %w", err)
		}

		newHandle = handle
		return nil
	})

	if err != nil {
		return 0, err
	}

	return ObjectID(newHandle), nil
}

// DeleteObject deletes a file or folder
func (m *fileSystemManager) DeleteObject(objectID ObjectID) error {
	return withDevice(func(dev *mtp.Device) error {
		if err := dev.DeleteObject(uint32(objectID)); err != nil {
			return fmt.Errorf("DeleteObject failed: %w", err)
		}
		return nil
	})
}

// DownloadFile downloads a file from the device
func (m *fileSystemManager) DownloadFile(objectID ObjectID, destPath string, taskID string) error {
	// This is a placeholder - actual implementation is in Kalam_DownloadFile
	return fmt.Errorf("DownloadFile not implemented in fileSystemManager")
}

// UploadFile uploads a file to the device
func (m *fileSystemManager) UploadFile(storageID StorageID, parentID ParentID, srcPath string, taskID string) error {
	// This is a placeholder - actual implementation is in Kalam_UploadFile
	return fmt.Errorf("UploadFile not implemented in fileSystemManager")
}

// RefreshStorage refreshes the device storage cache
func (m *fileSystemManager) RefreshStorage(storageID StorageID) error {
	return withDevice(func(dev *mtp.Device) error {
		var info mtp.StorageInfo
		if err := dev.GetStorageInfo(uint32(storageID), &info); err != nil {
			return fmt.Errorf("GetStorageInfo failed: %w", err)
		}
		return nil
	})
}

// Global instances of the interface implementations
var deviceMgr DeviceManager = &mtpDeviceManager{}
var fileSystemMgr FileSystemManager = &fileSystemManager{}

// -- Data Structures for JSON --

type MTPSupportJSON struct {
	MtpVersion      string `json:"mtpVersion"`
	DeviceVersion   string `json:"deviceVersion"`
	VendorExtension string `json:"vendorExtension"`
}

type DeviceJSON struct {
	ID           int            `json:"id"`
	Name         string         `json:"name"`
	Manufacturer string         `json:"manufacturer"`
	Model        string         `json:"model"`
	SerialNumber string         `json:"serialNumber"`
	Storage      []StorageJSON  `json:"storage"`
	MTPSupport   MTPSupportJSON `json:"mtpSupport"`
}

type StorageJSON struct {
	ID          uint32 `json:"id"`
	Description string `json:"description"`
	FreeSpace   uint64 `json:"freeSpace"`
	MaxCapacity uint64 `json:"maxCapacity"`
}

type FileJSON struct {
	ID        uint32 `json:"id"`
	ParentID  uint32 `json:"parentId"`
	StorageID uint32 `json:"storageId"`
	Name      string `json:"name"`
	Size      uint64 `json:"size"`
	IsFolder  bool   `json:"isFolder"`
	ModTime   int64  `json:"modTime"`
}
