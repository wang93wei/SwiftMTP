package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

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
			} // Progress monitoring disabled for stability

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
