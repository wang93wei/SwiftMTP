package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

//export Kalam_DownloadFile
func Kalam_DownloadFile(objectID uint32, destinationPath *C.char, taskID *C.char) int32 {
	if taskID == nil {
		fmt.Printf("Kalam_DownloadFile: taskID is nil\n")
		return 0
	}
	taskIDStr := C.GoString(taskID)
	operation, err := transferCancellations.begin(taskIDStr)
	if err != nil {
		fmt.Printf("Kalam_DownloadFile: %v\n", err)
		return 0
	}
	defer operation.finish()

	objectIDTyped := ObjectID(objectID)
	if err := objectIDTyped.Validate(); err != nil {
		fmt.Printf("Kalam_DownloadFile: %v\n", err)
		return 0
	}
	if destinationPath == nil {
		fmt.Printf("Kalam_DownloadFile: destinationPath is nil\n")
		return 0
	}
	destPath := C.GoString(destinationPath)
	if destPath == "" {
		fmt.Printf("Kalam_DownloadFile: Empty destination path\n")
		return 0
	}

	validatedPath := filepath.Clean(destPath)

	if strings.Contains(validatedPath, "..") {
		fmt.Printf("Kalam_DownloadFile: Path contains traversal attempt: %s\n", destPath)
		return 0
	}

	if !filepath.IsAbs(validatedPath) {
		fmt.Printf("Kalam_DownloadFile: Path must be absolute: %s\n", destPath)
		return 0
	}

	if operation.isCancelled() {
		fmt.Printf("Kalam_DownloadFile: Task %s was cancelled before start\n", taskIDStr)
		return 0
	}

	dir := filepath.Dir(validatedPath)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create directory %s: %v\n", dir, err)
			return 0
		}
	}

	if _, err := os.Stat(validatedPath); err == nil {
		fmt.Printf("Kalam_DownloadFile: File already exists at %s\n", validatedPath)
		if removeErr := os.Remove(validatedPath); removeErr != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to remove existing file %s: %v\n", validatedPath, removeErr)
			return 0
		}
	}

	var lastError error

	for attempt := 0; attempt < cfg.Retries.Download; attempt++ {
		if attempt > 0 {
			fmt.Printf("Kalam_DownloadFile: Retry attempt %d/%d\n", attempt+1, cfg.Retries.Download)
			backoffDuration := time.Duration(1<<uint(attempt-1)) * time.Second
			if backoffDuration > 4*time.Second {
				backoffDuration = 4 * time.Second
			}
			fmt.Printf("Kalam_DownloadFile: Waiting %v before retry...\n", backoffDuration)
			time.Sleep(backoffDuration)

			runtime.GC()
		}

		file, err := os.Create(validatedPath)
		if err != nil {
			fmt.Printf("Kalam_DownloadFile: Failed to create file %s: %v\n", validatedPath, err)
			lastError = err
			continue
		}

		defer file.Close()

		var writtenBytes int64
		var downloadCompleted bool

		progressCb := func(sent int64) error {
			writtenBytes = sent

			if operation.isCancelled() {
				fmt.Printf("Kalam_DownloadFile: Task %s cancelled during download (received %d bytes)\n", taskIDStr, sent)
				return fmt.Errorf("task %s cancelled during download", taskIDStr)
			}
			return nil
		}

		downloadErr := withLegacyMTPDevice(func(dev *mtp.Device) error {
			dev.Timeout = int(cfg.Timeouts.LargeFileDownload.Milliseconds())

			var objInfo mtp.ObjectInfo
			if err := dev.GetObjectInfo(uint32(objectIDTyped), &objInfo); err != nil {
				return fmt.Errorf("failed to get object info: %w", err)
			}

			fmt.Printf("Kalam_DownloadFile: Starting download of %s (%d bytes)\n", objInfo.Filename, objInfo.CompressedSize)

			if int64(objInfo.CompressedSize) > cfg.FileSize.LargeThreshold {
				fmt.Printf("Kalam_DownloadFile: Large file detected (%.1f MB), download may take time\n", float64(objInfo.CompressedSize)/1024/1024)
			}

			func() {
				defer func() {
					if r := recover(); r != nil {
						fmt.Printf("Kalam_DownloadFile: Panic during download: %v\n", r)
						lastError = fmt.Errorf("panic during download: %v", r)
					}
				}()

				err := dev.GetObject(uint32(objectIDTyped), file, progressCb)
				if err != nil {
					lastError = fmt.Errorf("download failed: %w", err)
				} else {
					downloadCompleted = true
				}
			}()

			if lastError != nil {
				return lastError
			}

			return nil
		})

		if syncErr := file.Sync(); syncErr != nil {
			fmt.Printf("Kalam_DownloadFile: Error syncing file %s: %v\n", validatedPath, syncErr)
		}
		if closeErr := file.Close(); closeErr != nil {
			fmt.Printf("Kalam_DownloadFile: Error closing file %s: %v\n", validatedPath, closeErr)
		}

		if downloadErr != nil || lastError != nil {
			fmt.Printf("Kalam_DownloadFile: Download attempt %d failed: %v\n", attempt+1, downloadErr)
			if lastError != nil {
				fmt.Printf("Kalam_DownloadFile: Additional error: %v\n", lastError)
			}

			if removeErr := os.Remove(validatedPath); removeErr != nil {
				fmt.Printf("Kalam_DownloadFile: Warning - failed to remove partial file %s: %v\n", validatedPath, removeErr)
			}

			errorStr := strings.ToLower(downloadErr.Error())
			if strings.Contains(errorStr, "device") ||
				strings.Contains(errorStr, "connection") ||
				strings.Contains(errorStr, "timeout") ||
				strings.Contains(errorStr, "not found") ||
				strings.Contains(errorStr, "no device") ||
				strings.Contains(errorStr, "LIBUSB_ERROR") {
				fmt.Printf("Kalam_DownloadFile: Recoverable error detected, will retry\n")
				continue
			}
			fmt.Printf("Kalam_DownloadFile: Non-recoverable error, stopping retries\n")
			break
		}

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

	fmt.Printf("Kalam_DownloadFile: All retry attempts failed. Last error: %v\n", lastError)
	return 0
}
