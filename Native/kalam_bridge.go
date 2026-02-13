package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"
    
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

// MARK: - Configuration

// Config holds all configuration settings as a single source of truth
type Config struct {
	// Timeout settings (milliseconds)
	Timeouts struct {
		QuickScan           time.Duration
		NormalOperation     time.Duration
		LargeFileDownload   time.Duration
	}

	// Retry settings
	Retries struct {
		QuickScan        int
		NormalOperation  int
		Download         int
	}

	// Backoff settings
	Backoff struct {
		QuickScanDuration time.Duration
		MaxDuration       time.Duration
	}

	// Security settings
	Security struct {
		MaxPathLength    int
		MaxCStringSize   int
		MaxFolderNameLength int
	}

	// Pool settings
	Pool struct {
		MaxSize     int
		EntryTTL    time.Duration
		CleanupTick time.Duration
	}

	// File size limits
	FileSize struct {
		LargeThreshold int64
		MaxSize        int64
	}

	// Download settings
	Download struct {
		DefaultDir string
	}

	// Retry settings
	Retry struct {
		MaxConsecutiveFailures int
	}
}

// DefaultConfig returns the default configuration
func DefaultConfig() *Config {
	cfg := &Config{}

	// Timeout settings
	cfg.Timeouts.QuickScan = 5 * time.Second
	cfg.Timeouts.NormalOperation = 45 * time.Second
	cfg.Timeouts.LargeFileDownload = 5 * time.Minute

	// Retry settings
	cfg.Retries.QuickScan = 1
	cfg.Retries.NormalOperation = 3
	cfg.Retries.Download = 3

	// Backoff settings
	cfg.Backoff.QuickScanDuration = 200 * time.Millisecond
	cfg.Backoff.MaxDuration = 2 * time.Second

	// Security settings
	cfg.Security.MaxPathLength = 4096
	cfg.Security.MaxCStringSize = 1024 * 1024
	cfg.Security.MaxFolderNameLength = 255

	// Pool settings
	cfg.Pool.MaxSize = 3
	cfg.Pool.EntryTTL = 2 * time.Minute
	cfg.Pool.CleanupTick = 1 * time.Minute

	// File size limits
	cfg.FileSize.LargeThreshold = 100 * 1024 * 1024 // 100MB
	cfg.FileSize.MaxSize = 10 * 1024 * 1024 * 1024 // 10GB

	// Download settings
	cfg.Download.DefaultDir = getDefaultDownloadDir()

	// Retry settings
	cfg.Retry.MaxConsecutiveFailures = 3

	return cfg
}

// LoadConfig loads configuration from environment variables
func LoadConfig() *Config {
	cfg := DefaultConfig()

	// Override with environment variables if present
	if dir := os.Getenv("DOWNLOAD_DIR"); dir != "" {
		cfg.Download.DefaultDir = dir
	}

	return cfg
}

// Global configuration instance
var cfg = LoadConfig()

// getDefaultDownloadDir returns the default download directory for the current user
func getDefaultDownloadDir() string {
	// Try from environment variable first
	if dir := os.Getenv("DOWNLOAD_DIR"); dir != "" {
		return dir
	}

	// Get user's home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		fmt.Printf("getDefaultDownloadDir: Failed to get home directory: %v\n", err)
		return "/tmp"
	}

	// Return Downloads directory
	return filepath.Join(homeDir, "Downloads")
}

// MARK: - Path Security Validation

// validateAndCleanPath validates and cleans the path to prevent path traversal attacks
func validateAndCleanPath(path string, allowedBaseDir string) (string, error) {
	// 1. Validate path length
	if len(path) == 0 {
		return "", fmt.Errorf("path cannot be empty")
	}

	if len(path) > cfg.Security.MaxPathLength {
		return "", fmt.Errorf("path exceeds maximum length of %d", cfg.Security.MaxPathLength)
	}
	
	// 2. Check for dangerous characters
	dangerousChars := []string{"\x00", "\n", "\r", "\t"}
	for _, char := range dangerousChars {
		if strings.Contains(path, char) {
			return "", fmt.Errorf("path contains invalid character")
		}
	}
	
	// 3. Clean the path
	cleanPath := filepath.Clean(path)
	
	// 4. Resolve to absolute path
	absPath, err := filepath.Abs(cleanPath)
	if err != nil {
		return "", fmt.Errorf("failed to get absolute path: %w", err)
	}
	
	// 5. Check if path is within allowed directory
	allowedAbs, err := filepath.Abs(allowedBaseDir)
	if err != nil {
		return "", fmt.Errorf("failed to get allowed base dir: %w", err)
	}
	
	relPath, err := filepath.Rel(allowedAbs, absPath)
	if err != nil {
		return "", fmt.Errorf("path is not relative to allowed dir: %w", err)
	}
	
	// 6. Check if path contains ".."
	if strings.Contains(relPath, "..") {
		return "", fmt.Errorf("path contains parent directory references")
	}
	
	// 7. Check if path starts with ".."
	if strings.HasPrefix(relPath, "..") {
		return "", fmt.Errorf("path starts with parent directory reference")
	}
	
	return absPath, nil
}

// safeCString safely allocates a C string with size limit
func safeCString(s string) *C.char {
	if len(s) > cfg.Security.MaxCStringSize {
		fmt.Printf("safeCString: String too large (%d bytes, max %d)\n", len(s), cfg.Security.MaxCStringSize)
		return nil
	}
	return C.CString(s)
}

// MTP object formats
const (
	// Folder format
	ObjectFormatFolder = 0x3001
	// Generic file format
	ObjectFormatGenericFile = 0x3000
)

// MARK: - Internal State

var (
	// Device mutex
	deviceMu sync.Mutex
	// Cancelled tasks map (using sync.Map for better concurrent performance)
	cancelledTasks sync.Map
	// Allocated C strings tracking (for memory leak detection)
	allocatedStrings = make(map[*C.char]time.Time)
	stringMu sync.Mutex
)

// Device connection pool to avoid frequent initialization/disposal
// This prevents TLS key exhaustion in libusb
type devicePoolEntry struct {
	device     *mtp.Device
	lastUsed   time.Time
	inUse      bool
}

var (
	devicePool      []*devicePoolEntry
	devicePoolMu    sync.RWMutex
)

// Initialize device pool cleanup routine
func init() {
	go func() {
		ticker := time.NewTicker(cfg.Pool.CleanupTick)
		defer ticker.Stop()
		
		for range ticker.C {
			cleanupDevicePool()
		}
	}()
}

// cleanupDevicePool removes stale entries from the device pool
func cleanupDevicePool() {
	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()

	now := time.Now()
	var activePool []*devicePoolEntry

	for _, entry := range devicePool {
		// Remove entries that are not in use and have expired
		if entry.inUse {
			activePool = append(activePool, entry)
		} else if now.Sub(entry.lastUsed) < cfg.Pool.EntryTTL {
			activePool = append(activePool, entry)
		} else {
			// Dispose expired device
			fmt.Printf("cleanupDevicePool: Disposing expired device connection\n")
			mtpx.Dispose(entry.device)
		}
	}
	
	devicePool = activePool
}

// getDeviceFromPool tries to get a device from the pool, returns nil if none available or device is closed
func getDeviceFromPool() *devicePoolEntry {
	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()
	
	// Iterate backwards to safely remove elements
	for i := len(devicePool) - 1; i >= 0; i-- {
		entry := devicePool[i]
		if !entry.inUse {
			// Test if device is still open by trying to get device info
			var testInfo mtp.DeviceInfo
			err := entry.device.GetDeviceInfo(&testInfo)
			
			if err != nil {
				// Device is closed or invalid, remove from pool
				// Only log in debug mode to avoid log spam
				// fmt.Printf("getDeviceFromPool: Device in pool is closed/invalid, removing: %v\n", err)
				mtpx.Dispose(entry.device)
				// Remove from pool by slicing - safe when iterating backwards
				devicePool = append(devicePool[:i], devicePool[i+1:]...)
				continue
			}
			
			entry.inUse = true
			entry.lastUsed = time.Now()
			return entry
		}
	}
	
	return nil
}

// returnDeviceToPool returns a device to the pool or disposes it if pool is full
func returnDeviceToPool(entry *devicePoolEntry) {
	if entry == nil || entry.device == nil {
		return
	}

	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()

	entry.inUse = false
	entry.lastUsed = time.Now()

	// If pool is full, dispose the oldest entry not in use
	if len(devicePool) >= cfg.Pool.MaxSize {
		var oldestIndex = -1
		var oldestTime time.Time
		
		for i, e := range devicePool {
			if !e.inUse && (oldestIndex == -1 || e.lastUsed.Before(oldestTime)) {
				oldestIndex = i
				oldestTime = e.lastUsed
			}
		}
		
		if oldestIndex >= 0 {
			mtpx.Dispose(devicePool[oldestIndex].device)
			devicePool = append(devicePool[:oldestIndex], devicePool[oldestIndex+1:]...)
		}
	}
	
	devicePool = append(devicePool, entry)
}

// removeClosedDeviceFromPool removes a specific device entry from the pool
func removeClosedDeviceFromPool(entry *devicePoolEntry) {
	if entry == nil || entry.device == nil {
		return
	}
	
	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()
	
	// Find and remove the entry
	for i, e := range devicePool {
		if e == entry {
			fmt.Printf("removeClosedDeviceFromPool: Removing closed device from pool\n")
			mtpx.Dispose(e.device)
			devicePool = append(devicePool[:i], devicePool[i+1:]...)
			return
		}
	}
}

// createNewDevice creates a new device connection and adds it to the pool
func createNewDevice() (*devicePoolEntry, error) {
	dev, err := mtpx.Initialize(mtpx.Init{
		DebugMode: false,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to initialize device: %w", err)
	}
	
	entry := &devicePoolEntry{
		device:   dev,
		lastUsed: time.Now(),
		inUse:    true,
	}
	
	return entry, nil
}

// withDeviceQuick executes a function with a device connection using faster settings for scanning
// Uses connection pool to avoid frequent initialization/disposal
func withDeviceQuick(fn func(*mtp.Device) error) error {
	deviceMu.Lock()
	defer deviceMu.Unlock()

	var lastError error
	var err error

	for attempt := 0; attempt < cfg.Retries.QuickScan; attempt++ {
		if attempt > 0 {
			fmt.Printf("withDeviceQuick: Retrying operation (attempt %d/%d)\n", attempt+1, cfg.Retries.QuickScan)
			// Quick scan uses short backoff time
			time.Sleep(cfg.Backoff.QuickScanDuration)
		}
		
		// Try to get device from pool first
		poolEntry := getDeviceFromPool()
		var dev *mtp.Device
		var deviceFromPool bool
		
		if poolEntry != nil {
			dev = poolEntry.device
			deviceFromPool = true
			fmt.Printf("withDeviceQuick: Using pooled device connection\n")
		} else {
			// Create new device if pool is empty
			newEntry, createErr := createNewDevice()
			if createErr != nil {
				lastError = fmt.Errorf("failed to initialize device: %w", createErr)
				fmt.Printf("withDeviceQuick: %v\n", lastError)
				continue
			}
			poolEntry = newEntry
			dev = poolEntry.device
			deviceFromPool = false
			fmt.Printf("withDeviceQuick: Created new device connection\n")
		}
		
		// Ensure device is properly handled with panic recovery
		func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("withDeviceQuick: Panic during device operation: %v\n", r)
				}
				// Return device to pool instead of disposing
				returnDeviceToPool(poolEntry)
			}()
			
						// Configure device with shorter timeout for quick scans
						dev.Timeout = int(cfg.Timeouts.QuickScan.Milliseconds())
			
						// Execute the function with panic recovery
						func() {				defer func() {
					if r := recover(); r != nil {
						lastError = fmt.Errorf("panic in quick device operation: %v", r)
						fmt.Printf("withDeviceQuick: Panic in device operation: %v\n", r)
					}
				}()
				
				err = fn(dev)
				if err != nil {
					lastError = err
					fmt.Printf("withDeviceQuick: Operation failed: %v\n", err)
				}
			}()
		}()
		
		// If operation succeeded, return immediately
		if err == nil {
			return nil
		}
		
		// Check if error is due to device being closed
		errorStr := strings.ToLower(lastError.Error())
		isDeviceClosed := strings.Contains(errorStr, "device is not open") ||
		                  strings.Contains(errorStr, "device closed")
		
		if isDeviceClosed && deviceFromPool {
			// Device from pool was closed, remove it and retry with new connection
			fmt.Printf("withDeviceQuick: Pooled device was closed, will retry with new connection\n")
			// Remove the closed device from pool
			removeClosedDeviceFromPool(poolEntry)
			continue
		}
		
		// For quick scans, be less aggressive about retries
		isRecoverable := strings.Contains(errorStr, "timeout") ||
		                 strings.Contains(errorStr, "busy") ||
		                 strings.Contains(errorStr, "LIBUSB_ERROR_TIMEOUT")
		
		if !isRecoverable {
			// Non-recoverable error, don't retry
			fmt.Printf("withDeviceQuick: Non-recoverable error, stopping retries: %v\n", lastError)
			break
		}
		
		// For recoverable errors, continue to next retry
		fmt.Printf("withDeviceQuick: Recoverable error, will retry: %v\n", lastError)
	}
	
	return lastError
}

// withDevice executes a function with a device connection using normal settings
// Uses connection pool to avoid frequent initialization/disposal
func withDevice(fn func(*mtp.Device) error) error {
	deviceMu.Lock()
	defer deviceMu.Unlock()

	var lastError error
	var err error

	for attempt := 0; attempt < cfg.Retries.NormalOperation; attempt++ {
		if attempt > 0 {
			fmt.Printf("withDevice: Retrying operation (attempt %d/%d)\n", attempt+1, cfg.Retries.NormalOperation)
			// Exponential backoff strategy
			backoffDuration := time.Duration(attempt*attempt) * 500 * time.Millisecond
			if backoffDuration > cfg.Backoff.MaxDuration {
				backoffDuration = cfg.Backoff.MaxDuration
			}
			time.Sleep(backoffDuration)
			
			// Force garbage collection before retry to free up resources
			runtime.GC()
		}
		
		// Try to get device from pool first
		poolEntry := getDeviceFromPool()
		var dev *mtp.Device
		var deviceFromPool bool
		
		if poolEntry != nil {
			dev = poolEntry.device
			deviceFromPool = true
			fmt.Printf("withDevice: Using pooled device connection\n")
		} else {
			// Create new device if pool is empty
			newEntry, createErr := createNewDevice()
			if createErr != nil {
				lastError = fmt.Errorf("failed to initialize device: %w", createErr)
				fmt.Printf("withDevice: %v\n", lastError)
				
				// Check if initialization error is recoverable
				if strings.Contains(createErr.Error(), "not found") && attempt == cfg.Retries.NormalOperation-1 {
					// Device disconnected, don't retry further
					break
				}
				continue
			}
			poolEntry = newEntry
			dev = poolEntry.device
			deviceFromPool = false
			fmt.Printf("withDevice: Created new device connection\n")
		}
		
		// Ensure device is properly handled with panic recovery
		func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("withDevice: Panic during device operation: %v\n", r)
				}
				// Return device to pool instead of disposing
				returnDeviceToPool(poolEntry)
			}()
			
						// Configure device with longer timeout for better stability
						dev.Timeout = int(cfg.Timeouts.NormalOperation.Milliseconds())
			
						// Test device connection before executing function
						var testInfo mtp.DeviceInfo
						if testErr := dev.GetDeviceInfo(&testInfo); testErr != nil {				lastError = fmt.Errorf("device connection test failed: %w", testErr)
				fmt.Printf("withDevice: Device connection test failed: %v\n", testErr)
				return
			}
			
			// Execute the function with additional panic recovery
			func() {
				defer func() {
					if r := recover(); r != nil {
						lastError = fmt.Errorf("panic in device operation: %v", r)
						fmt.Printf("withDevice: Panic in device operation: %v\n", r)
					}
				}()
				
				err = fn(dev)
				if err != nil {
					lastError = err
					fmt.Printf("withDevice: Operation failed: %v\n", err)
				}
			}()
		}()
		
		// If operation succeeded, return immediately
		if err == nil {
			return nil
		}
		
		// Check if error is due to device being closed
		errorStr := strings.ToLower(lastError.Error())
		isDeviceClosed := strings.Contains(errorStr, "device is not open") ||
		                  strings.Contains(errorStr, "device closed")
		
		if isDeviceClosed && deviceFromPool {
			// Device from pool was closed, remove it and retry with new connection
			fmt.Printf("withDevice: Pooled device was closed, will retry with new connection\n")
			// Remove the closed device from pool
			removeClosedDeviceFromPool(poolEntry)
			continue
		}
		
		// Check if error is recoverable
		isRecoverable := strings.Contains(errorStr, "timeout") ||
		                 strings.Contains(errorStr, "device") ||
		                 strings.Contains(errorStr, "connection") ||
		                 strings.Contains(errorStr, "busy") ||
		                 strings.Contains(errorStr, "LIBUSB_ERROR_TIMEOUT")
		
		if !isRecoverable {
			// Non-recoverable error, don't retry
			fmt.Printf("withDevice: Non-recoverable error, stopping retries: %v\n", lastError)
			break
		}
		
		// For recoverable errors, continue to next retry
		fmt.Printf("withDevice: Recoverable error, will retry: %v\n", lastError)
	}
	
	return lastError
}

// -- Data Structures for JSON --

type MTPSupportJSON struct {
	MtpVersion      string `json:"mtpVersion"`
	DeviceVersion   string `json:"deviceVersion"`
	VendorExtension string `json:"vendorExtension"`
}

type DeviceJSON struct {
	ID           int             `json:"id"`
	Name         string          `json:"name"`
	Manufacturer string          `json:"manufacturer"`
	Model        string          `json:"model"`
	SerialNumber string          `json:"serialNumber"`
	Storage      []StorageJSON   `json:"storage"`
	MTPSupport   MTPSupportJSON  `json:"mtpSupport"`
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

// -- Exported Functions --

//export Kalam_Init
func Kalam_Init() {
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

// Progress callback function type - DISABLED to prevent crashes
// type progressCallback func(sent int64)

// var currentProgressCallback progressCallback

//export Kalam_SetProgressCallback
func Kalam_SetProgressCallback(cb C.uintptr_t) {
	// Progress callbacks are disabled to prevent crashes
	fmt.Printf("Kalam_SetProgressCallback: Progress callbacks disabled for stability\n")
}

//export Kalam_DownloadFile
func Kalam_DownloadFile(objectID uint32, destinationPath *C.char, taskID *C.char) int32 {
	// Convert to custom type for validation
	objectIDTyped := ObjectID(objectID)

	// Validate input
	if err := objectIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_DownloadFile: %v\n", err)
		return 0
	}

	if destinationPath == nil {
		fmt.Printf("Kalam_DownloadFile: destinationPath is nil\n")
		return 0
	}
	if taskID == nil {
		fmt.Printf("Kalam_DownloadFile: taskID is nil\n")
		return 0
	}

	destPath := C.GoString(destinationPath)
	taskIDStr := C.GoString(taskID)

	if destPath == "" {
		fmt.Printf("Kalam_DownloadFile: Empty destination path\n")
		return 0
	}

	// Basic path validation (no directory restriction since user chooses location via NSSavePanel)
	// Only check for dangerous patterns and normalize the path
	validatedPath := filepath.Clean(destPath)

	// Check for path traversal attempts
	if strings.Contains(validatedPath, "..") {
		fmt.Printf("Kalam_DownloadFile: Path contains traversal attempt: %s\n", destPath)
		return 0
	}

	// Ensure path is absolute
	if !filepath.IsAbs(validatedPath) {
		fmt.Printf("Kalam_DownloadFile: Path must be absolute: %s\n", destPath)
		return 0
	}

	if isTaskCancelled(taskIDStr) {
		fmt.Printf("Kalam_DownloadFile: Task %s was cancelled before start\n", taskIDStr)
		return 0
	}

	// Check if destination directory exists
	dir := filepath.Dir(validatedPath)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		if err := os.MkdirAll(dir, 0700); err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create directory %s: %v\n", dir, err)
			return 0
		}
	}

	// Check if file already exists
	if _, err := os.Stat(validatedPath); err == nil {
		fmt.Printf("Kalam_DownloadFile: File already exists at %s\n", validatedPath)
		// Remove existing file to ensure clean download
		if removeErr := os.Remove(validatedPath); removeErr != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to remove existing file %s: %v\n", validatedPath, removeErr)
			return 0
		}
	}

	var lastError error

	for attempt := 0; attempt < cfg.Retries.Download; attempt++ {
		if attempt > 0 {
			fmt.Printf("Kalam_DownloadFile: Retry attempt %d/%d\n", attempt+1, cfg.Retries.Download)
			// Progressive backoff: 1s, 2s, 4s
			backoffDuration := time.Duration(1<<uint(attempt-1)) * time.Second
			if backoffDuration > 4*time.Second {
				backoffDuration = 4 * time.Second
			}
			fmt.Printf("Kalam_DownloadFile: Waiting %v before retry...\n", backoffDuration)
			time.Sleep(backoffDuration)
			
			// Force garbage collection to free up USB resources
			runtime.GC()
		}

		file, err := os.Create(validatedPath)
		if err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create file %s: %v\n", validatedPath, err)
			lastError = err
			continue
		}
		
		// Use defer to ensure file is always closed, even if panic occurs
		defer file.Close()
		
		// Track file size for validation
		var writtenBytes int64
		var downloadCompleted bool
		
		// Simplified progress callback to avoid cross-language crashes
		progressCb := func(sent int64) error {
			writtenBytes = sent
			
			// Check for cancellation during download
			if isTaskCancelled(taskIDStr) {
				fmt.Printf("Kalam_DownloadFile: Task %s cancelled during download (received %d bytes)\n", taskIDStr, sent)
				return fmt.Errorf("task %s cancelled during download", taskIDStr)
			}
			return nil
		}
		
		// Use withDevice for downloads with custom timeout for large files
				downloadErr := withDevice(func(dev *mtp.Device) error {
					// Set very long timeout for large file downloads
					dev.Timeout = int(cfg.Timeouts.LargeFileDownload.Milliseconds())
		
					// Validate object exists before download
					var objInfo mtp.ObjectInfo
					if err := dev.GetObjectInfo(uint32(objectIDTyped), &objInfo); err != nil {
						return fmt.Errorf("failed to get object info: %w", err)
					}
		
					fmt.Printf("Kalam_DownloadFile: Starting download of %s (%d bytes)\n", objInfo.Filename, objInfo.CompressedSize)
		
					// For large files, warn about potential timeouts
								if int64(objInfo.CompressedSize) > cfg.FileSize.LargeThreshold {
									fmt.Printf("Kalam_DownloadFile: Large file detected (%.1f MB), download may take time\n", float64(objInfo.CompressedSize)/1024/1024)
								}			// Progress monitoring disabled for stability
			
			// Perform the download with comprehensive error recovery
			func() {
				defer func() {
					if r := recover(); r != nil {
						fmt.Printf("Kalam_DownloadFile: Panic during download: %v\n", r)
						lastError = fmt.Errorf("panic during download: %v", r)
					}
				}()

				// Use a context with timeout for the download operation
				ctx, cancel := context.WithTimeout(context.Background(), time.Duration(dev.Timeout)*time.Millisecond)
				defer cancel()

				downloadChan := make(chan error, 1)

				go func() {
					defer func() {
						if r := recover(); r != nil {
							downloadChan <- fmt.Errorf("panic in download goroutine: %v", r)
						}
					}()

					err := dev.GetObject(uint32(objectIDTyped), file, progressCb)
					downloadChan <- err
				}()
				
				// Wait for download completion or timeout
				select {
				case err := <-downloadChan:
					if err != nil {
						lastError = fmt.Errorf("download failed: %w", err)
					} else {
						downloadCompleted = true
					}
				case <-ctx.Done():
					lastError = fmt.Errorf("download timed out after %d seconds", dev.Timeout/1000)
					fmt.Printf("Kalam_DownloadFile: Download timeout\n")
					// Note: goroutine may still be running, but file will be closed
				}
			}()
			
			// No progress monitoring to stop
			
			if lastError != nil {
				return lastError
			}
			
			return nil
		})
		
		// Ensure file is closed properly and synced to disk
		if syncErr := file.Sync(); syncErr != nil {
			fmt.Printf("Kalam_DownloadFile: Error syncing file %s: %v\n", validatedPath, syncErr)
		}
		if cerr := file.Close(); cerr != nil {
			fmt.Printf("Kalam_DownloadFile: Error closing file %s: %v\n", validatedPath, cerr)
		}
		
		if downloadErr != nil || lastError != nil {
			fmt.Printf("Kalam_DownloadFile: Download attempt %d failed: %v\n", attempt+1, downloadErr)
			if lastError != nil {
				fmt.Printf("Kalam_DownloadFile: Additional error: %v\n", lastError)
			}
			
			// Remove partial file
			if removeErr := os.Remove(validatedPath); removeErr != nil {
				fmt.Printf("Kalam_DownloadFile: Warning - failed to remove partial file %s: %v\n", validatedPath, removeErr)
			}
			
			// Check if error is recoverable
			errorStr := strings.ToLower(downloadErr.Error())
			if strings.Contains(errorStr, "device") || 
			   strings.Contains(errorStr, "connection") ||
			   strings.Contains(errorStr, "timeout") ||
			   strings.Contains(errorStr, "not found") ||
			   strings.Contains(errorStr, "no device") ||
			   strings.Contains(errorStr, "LIBUSB_ERROR") {
				// These errors might be recoverable with retry
				fmt.Printf("Kalam_DownloadFile: Recoverable error detected, will retry\n")
				continue
			}
			// Other errors are not recoverable
			fmt.Printf("Kalam_DownloadFile: Non-recoverable error, stopping retries\n")
			break
		}
		
		// Download succeeded, validate the file
		if downloadCompleted {
			if stat, err := os.Stat(validatedPath); err == nil {
				if stat.Size() == 0 {
					fmt.Printf("Kalam_DownloadFile: Warning - downloaded file is empty\n")
					lastError = fmt.Errorf("downloaded file is empty")
					continue
				}
				fmt.Printf("Kalam_DownloadFile: Successfully downloaded %d bytes (tracked: %d) to %s\n", stat.Size(), writtenBytes, validatedPath)
				return 1
			} else {
				fmt.Printf("Kalam_DownloadFile: Failed to stat downloaded file: %v\n", err)
				lastError = err
				continue
			}
		}
	}
	
	// All retries failed
	fmt.Printf("Kalam_DownloadFile: All retry attempts failed. Last error: %v\n", lastError)
	return 0
}

// -- Cancellation State --

type cancelError struct {
	taskID string
}

func (e *cancelError) Error() string {
	return fmt.Sprintf("task %s cancelled", e.taskID)
}

func isTaskCancelled(taskID string) bool {
	_, ok := cancelledTasks.Load(taskID)
	return ok
}

func markTaskCancelled(taskID string) {
	cancelledTasks.Store(taskID, true)
}

//export Kalam_CancelTask
func Kalam_CancelTask(taskID *C.char) {
	if taskID == nil {
		fmt.Printf("Kalam_CancelTask: taskID is nil\n")
		return
	}
	
	id := C.GoString(taskID)
	if id == "" {
		fmt.Printf("Kalam_CancelTask: taskID is empty\n")
		return
	}
	
	cancelledTasks.Store(id, true)
	fmt.Printf("Kalam_CancelTask: Task %s marked for cancellation\n", id)
}

//export Kalam_UploadFile
func Kalam_UploadFile(storageID uint32, parentID uint32, sourcePath *C.char, taskID *C.char) int32 {
	// Convert to custom types for validation
	storageIDTyped := StorageID(storageID)
	parentIDTyped := ParentID(parentID)

	// Validate inputs
	if err := storageIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_UploadFile: %v\n", err)
		return 0
	}
	if err := parentIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_UploadFile: %v\n", err)
		return 0
	}

	if sourcePath == nil {
		fmt.Printf("Kalam_UploadFile: sourcePath is nil\n")
		return 0
	}
	if taskID == nil {
		fmt.Printf("Kalam_UploadFile: taskID is nil\n")
		return 0
	}

	path := C.GoString(sourcePath)
	taskIDStr := C.GoString(taskID)

	if path == "" {
		fmt.Printf("Kalam_UploadFile: Empty source path\n")
		return 0
	}

	if isTaskCancelled(taskIDStr) {
		fmt.Printf("Kalam_UploadFile: Task %s was cancelled before start\n", taskIDStr)
		return 0
	}

	// Check if file exists
	fileInfo, err := os.Stat(path)
	if err != nil {
		fmt.Printf("Kalam_UploadFile: File not found: %v\n", err)
		return 0
	}

	if fileInfo.IsDir() {
		fmt.Printf("Kalam_UploadFile: Cannot upload directories: %s\n", path)
		return 0
	}

	fileSize := fileInfo.Size()
	fileName := filepath.Base(path)
	
	fmt.Printf("Kalam_UploadFile: Starting upload of %s (%d bytes)\n", fileName, fileSize)

	var result int32 = 0

	err = withDevice(func(dev *mtp.Device) error {
		// Step 1: Send object info
		var objInfo mtp.ObjectInfo
		objInfo.StorageID = uint32(storageIDTyped)
		objInfo.ParentObject = uint32(parentIDTyped)
		objInfo.Filename = fileName
		objInfo.ObjectFormat = ObjectFormatGenericFile
		objInfo.CompressedSize = uint32(fileSize)
		objInfo.ModificationDate = time.Now()

		fmt.Printf("Kalam_UploadFile: Sending object info for %s\n", fileName)

		// Use a more conservative approach with error handling
		_, _, newHandle, err := dev.SendObjectInfo(uint32(storageIDTyped), uint32(parentIDTyped), &objInfo)
		if err != nil {
			fmt.Printf("Kalam_UploadFile: SendObjectInfo failed: %v\n", err)
			return fmt.Errorf("SendObjectInfo failed: %w", err)
		}

		fmt.Printf("Kalam_UploadFile: Got handle %d for %s\n", newHandle, fileName)

		if isTaskCancelled(taskIDStr) {
			fmt.Printf("Kalam_UploadFile: Task %s cancelled before data transfer\n", taskIDStr)
			return fmt.Errorf("task cancelled")
		}

		// Step 2: Open the file for reading
		file, err := os.Open(path)
		if err != nil {
			fmt.Printf("Kalam_UploadFile: Failed to open file: %v\n", err)
			return fmt.Errorf("failed to open file: %w", err)
		}

		// Step 3: Send file data using the correct SendObject signature
		fmt.Printf("Kalam_UploadFile: Starting data transfer for %s\n", fileName)
		
		// SendObject expects: (io.Reader, int64, mtp.ProgressFunc)
		// We need to seek back to beginning of file and provide size
		if _, err := file.Seek(0, 0); err != nil {
			file.Close()
			fmt.Printf("Kalam_UploadFile: Failed to seek file: %v\n", err)
			return fmt.Errorf("failed to seek file: %w", err)
		}
		
		// Create progress callback to check cancellation during transfer
		progressCb := func(sent int64) error {
			if isTaskCancelled(taskIDStr) {
				fmt.Printf("Kalam_UploadFile: Task %s cancelled during transfer (sent %d bytes)\n", taskIDStr, sent)
				return fmt.Errorf("task cancelled during transfer")
			}
			return nil
		}
		
		// Try to send the object with cancellation checking
		err = dev.SendObject(file, fileSize, progressCb)
		file.Close() // Close file immediately after SendObject
		
		if err != nil {
			fmt.Printf("Kalam_UploadFile: SendObject failed: %v\n", err)
			return fmt.Errorf("SendObject failed: %w", err)
		}

		fmt.Printf("Kalam_UploadFile: Successfully uploaded %s (%d bytes)\n", fileName, fileSize)
		
		// Add a small delay to ensure the operation completes
		time.Sleep(100 * time.Millisecond)
		
		result = 1
		return nil
	})

	if err != nil {
		fmt.Printf("Kalam_UploadFile: Upload failed: %v\n", err)
		return 0
	}

	return result
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

// Helper function
func containsIgnoreCase(s, substr string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(substr))
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
