package main

/*
#include <stdlib.h>
*/
import "C"

import (
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

// MARK: - 常量定义

// 超时设置（毫秒）
const (
	// 快速扫描超时（5秒）
	QuickScanTimeout = 5000
	// 正常操作超时（45秒）
	NormalOperationTimeout = 45000
	// 大文件下载超时（300秒 = 5分钟）
	LargeFileDownloadTimeout = 300000
)

// 重试设置
const (
	// 快速扫描最大重试次数
	QuickScanMaxRetries = 1
	// 正常操作最大重试次数
	NormalOperationMaxRetries = 3
	// 下载最大重试次数
	DownloadMaxRetries = 3
)

// 退避设置
const (
	// 快速扫描退避时间（毫秒）
	QuickScanBackoffDuration = 200
	// 退避时间上限（毫秒）
	MaxBackoffDuration = 2000
	// 最大连续失败次数
	MaxConsecutiveFailures = 3
)

// 文件大小限制
const (
	// 大文件阈值（100MB）
	LargeFileThreshold = 100 * 1024 * 1024
	// 最大文件大小（10GB）
	MaxFileSize = 10 * 1024 * 1024 * 1024
)

// MTP 对象格式
const (
	// 文件夹格式
	ObjectFormatFolder = 0x3001
	// 通用文件格式
	ObjectFormatGenericFile = 0x3000
)

// MARK: - 内部状态

var (
	// 设备互斥锁
	deviceMu sync.Mutex
	// 取消任务互斥锁
	cancelMu sync.Mutex
	// 已取消的任务映射
	cancelledTasks = make(map[string]bool)
)

// withDeviceQuick executes a function with a fresh device connection using faster settings for scanning
// withDeviceQuick 使用快速设置执行设备连接操作
// 用于设备扫描，使用较短的超时和重试次数
func withDeviceQuick(fn func(*mtp.Device) error) error {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	
	var lastError error
	
	for attempt := 0; attempt < QuickScanMaxRetries; attempt++ {
		if attempt > 0 {
			fmt.Printf("withDeviceQuick: Reinitializing device connection (attempt %d/%d)\n", attempt+1, QuickScanMaxRetries)
			// 快速扫描使用短退避时间
			time.Sleep(time.Duration(QuickScanBackoffDuration) * time.Millisecond)
		}
		
		dev, err := mtpx.Initialize(mtpx.Init{
			DebugMode: false,
		})
		if err != nil {
			lastError = fmt.Errorf("failed to initialize device: %w", err)
			fmt.Printf("withDeviceQuick: %v\n", lastError)
			continue
		}
		
		// Ensure device is properly disposed with panic recovery
		func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("withDeviceQuick: Panic during device operation: %v\n", r)
				}
				mtpx.Dispose(dev)
			}()
			
			// Configure device with shorter timeout for quick scans
			dev.Timeout = QuickScanTimeout
			
			// Skip additional connection test for quick scans to save time
			// Execute the function with panic recovery
			func() {
				defer func() {
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
		
		// For quick scans, be less aggressive about retries
		errorStr := strings.ToLower(lastError.Error())
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

// withDevice 使用正常设置执行设备连接操作
// 用于文件传输等正常操作，使用较长的超时和重试次数
func withDevice(fn func(*mtp.Device) error) error {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	
	var lastError error
	
	for attempt := 0; attempt < NormalOperationMaxRetries; attempt++ {
		if attempt > 0 {
			fmt.Printf("withDevice: Reinitializing device connection (attempt %d/%d)\n", attempt+1, NormalOperationMaxRetries)
			// 指数退避策略
			backoffDuration := time.Duration(attempt*attempt) * 500 * time.Millisecond
			if backoffDuration > time.Duration(MaxBackoffDuration)*time.Millisecond {
				backoffDuration = time.Duration(MaxBackoffDuration) * time.Millisecond
			}
			time.Sleep(backoffDuration)
			
			// Force garbage collection before retry to free up resources
			runtime.GC()
		}
		
		dev, err := mtpx.Initialize(mtpx.Init{
			DebugMode: false,
		})
		if err != nil {
			lastError = fmt.Errorf("failed to initialize device: %w", err)
			fmt.Printf("withDevice: %v\n", lastError)
			
			// Check if initialization error is recoverable
			if strings.Contains(err.Error(), "not found") && attempt == NormalOperationMaxRetries-1 {
				// Device disconnected, don't retry further
				break
			}
			continue
		}
		
		// Ensure device is properly disposed with panic recovery
		func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("withDevice: Panic during device operation: %v\n", r)
				}
				// Always try to dispose the device
				mtpx.Dispose(dev)
			}()
			
			// Configure device with longer timeout for better stability
			dev.Timeout = NormalOperationTimeout
			
			// Test device connection before executing function
			var testInfo mtp.DeviceInfo
			if testErr := dev.GetDeviceInfo(&testInfo); testErr != nil {
				lastError = fmt.Errorf("device connection test failed: %w", testErr)
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
		
		// Check if error is recoverable
		errorStr := strings.ToLower(lastError.Error())
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

	return C.CString(result)
}

//export Kalam_ListFiles
func Kalam_ListFiles(storageID uint32, parentID uint32) *C.char {
	var result string
	
	err := withDevice(func(dev *mtp.Device) error {
		var handles mtp.Uint32Array
		if err := dev.GetObjectHandles(storageID, 0, parentID, &handles); err != nil {
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
		// 统一错误处理：返回 nil 表示错误
		return nil
	}

	return C.CString(result)
}

//export Kalam_FreeString
func Kalam_FreeString(str *C.char) {
    C.free(unsafe.Pointer(str))
}

//export Kalam_CreateFolder
func Kalam_CreateFolder(storageID uint32, parentID uint32, folderName *C.char) uint32 {
	name := C.GoString(folderName)
	if name == "" {
		return 0
	}

	var newHandle uint32
	
	err := withDevice(func(dev *mtp.Device) error {
		var objInfo mtp.ObjectInfo
		objInfo.StorageID = storageID
		objInfo.ParentObject = parentID
		objInfo.Filename = name
		objInfo.ObjectFormat = ObjectFormatFolder
		objInfo.CompressedSize = 0

		_, _, handle, err := dev.SendObjectInfo(storageID, parentID, &objInfo)
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
	err := withDevice(func(dev *mtp.Device) error {
		if err := dev.DeleteObject(objectID); err != nil {
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
	destPath := C.GoString(destinationPath)
	taskIDStr := C.GoString(taskID)
	
	if destPath == "" {
		fmt.Printf("Kalam_DownloadFile: Empty destination path\n")
		return 0
	}

	if isTaskCancelled(taskIDStr) {
		fmt.Printf("Kalam_DownloadFile: Task %s was cancelled before start\n", taskIDStr)
		return 0
	}

	// Check if destination directory exists
	dir := filepath.Dir(destPath)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		if err := os.MkdirAll(dir, 0755); err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create directory %s: %v\n", dir, err)
			return 0
		}
	}

	// Check if file already exists
	if _, err := os.Stat(destPath); err == nil {
		fmt.Printf("Kalam_DownloadFile: File already exists at %s\n", destPath)
		// Remove existing file to ensure clean download
		if removeErr := os.Remove(destPath); removeErr != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to remove existing file %s: %v\n", destPath, removeErr)
			return 0
		}
	}

	var lastError error
	
	for attempt := 0; attempt < DownloadMaxRetries; attempt++ {
		if attempt > 0 {
			fmt.Printf("Kalam_DownloadFile: Retry attempt %d/%d\n", attempt+1, DownloadMaxRetries)
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

		file, err := os.Create(destPath)
		if err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create file %s: %v\n", destPath, err)
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
			// Set very long timeout for large file downloads (up to 5 minutes)
			dev.Timeout = LargeFileDownloadTimeout
			
			// Validate object exists before download
			var objInfo mtp.ObjectInfo
			if err := dev.GetObjectInfo(objectID, &objInfo); err != nil {
				return fmt.Errorf("failed to get object info: %w", err)
			}
			
			fmt.Printf("Kalam_DownloadFile: Starting download of %s (%d bytes)\n", objInfo.Filename, objInfo.CompressedSize)
			
			// For large files, warn about potential timeouts
			if objInfo.CompressedSize > LargeFileThreshold {
				fmt.Printf("Kalam_DownloadFile: Large file detected (%.1f MB), download may take time\n", float64(objInfo.CompressedSize)/1024/1024)
			}
			
			// Progress monitoring disabled for stability
			
			// Perform the download with comprehensive error recovery
			func() {
				defer func() {
					if r := recover(); r != nil {
						fmt.Printf("Kalam_DownloadFile: Panic during download: %v\n", r)
						lastError = fmt.Errorf("panic during download: %v", r)
					}
				}()
				
				// Use a context with timeout for the download operation
				downloadChan := make(chan error, 1)
				
				go func() {
					defer func() {
						if r := recover(); r != nil {
							downloadChan <- fmt.Errorf("panic in download goroutine: %v", r)
						}
					}()
					
					err := dev.GetObject(objectID, file, progressCb)
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
				case <-time.After(time.Duration(dev.Timeout) * time.Millisecond):
					lastError = fmt.Errorf("download timed out after %d seconds", dev.Timeout/1000)
					fmt.Printf("Kalam_DownloadFile: Download timeout\n")
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
			fmt.Printf("Kalam_DownloadFile: Error syncing file %s: %v\n", destPath, syncErr)
		}
		if cerr := file.Close(); cerr != nil {
			fmt.Printf("Kalam_DownloadFile: Error closing file %s: %v\n", destPath, cerr)
		}
		
		if downloadErr != nil || lastError != nil {
			fmt.Printf("Kalam_DownloadFile: Download attempt %d failed: %v\n", attempt+1, downloadErr)
			if lastError != nil {
				fmt.Printf("Kalam_DownloadFile: Additional error: %v\n", lastError)
			}
			
			// Remove partial file
			if removeErr := os.Remove(destPath); removeErr != nil {
				fmt.Printf("Kalam_DownloadFile: Warning - failed to remove partial file %s: %v\n", destPath, removeErr)
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
			if stat, err := os.Stat(destPath); err == nil {
				if stat.Size() == 0 {
					fmt.Printf("Kalam_DownloadFile: Warning - downloaded file is empty\n")
					lastError = fmt.Errorf("downloaded file is empty")
					continue
				}
				fmt.Printf("Kalam_DownloadFile: Successfully downloaded %d bytes (tracked: %d) to %s\n", stat.Size(), writtenBytes, destPath)
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
	cancelMu.Lock()
	defer cancelMu.Unlock()
	return cancelledTasks[taskID]
}

func markTaskCancelled(taskID string) {
	cancelMu.Lock()
	defer cancelMu.Unlock()
	cancelledTasks[taskID] = true
}

//export Kalam_CancelTask
func Kalam_CancelTask(taskID *C.char) {
	id := C.GoString(taskID)
	cancelMu.Lock()
	cancelledTasks[id] = true
	cancelMu.Unlock()
	fmt.Printf("Kalam_CancelTask: Task %s marked for cancellation\n", id)
}

//export Kalam_UploadFile
func Kalam_UploadFile(storageID uint32, parentID uint32, sourcePath *C.char, taskID *C.char) int32 {
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
		objInfo.StorageID = storageID
		objInfo.ParentObject = parentID
		objInfo.Filename = fileName
		objInfo.ObjectFormat = ObjectFormatGenericFile
		objInfo.CompressedSize = uint32(fileSize)
		objInfo.ModificationDate = time.Now()

		fmt.Printf("Kalam_UploadFile: Sending object info for %s\n", fileName)
		
		// Use a more conservative approach with error handling
		_, _, newHandle, err := dev.SendObjectInfo(storageID, parentID, &objInfo)
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
	err := withDevice(func(dev *mtp.Device) error {
		// Try to refresh the device storage
		// This helps to clear the cache after file operations
		fmt.Printf("Kalam_RefreshStorage: Refreshing storage %d\n", storageID)
		
		// Get storage info to trigger refresh
		var info mtp.StorageInfo
		if err := dev.GetStorageInfo(storageID, &info); err != nil {
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

func main() {}
