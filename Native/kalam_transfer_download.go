package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

func downloadFromMTPDevice(
	device *mtp.Device,
	request nativeDownloadRequest,
) (uint64, error) {
	if device == nil {
		return 0, errNativeDisconnected
	}
	if err := ObjectID(request.objectID).Validate(); err != nil {
		return 0, newTransferError(transferErrorInvalidInput, err)
	}
	if request.destinationPath == "" ||
		!filepath.IsAbs(request.destinationPath) ||
		filepath.Clean(request.destinationPath) != request.destinationPath {
		return 0, newTransferError(
			transferErrorInvalidInput,
			fmt.Errorf("download destination must be an absolute standardized path"),
		)
	}
	if request.operation != nil && request.operation.isCancelled() {
		return 0, &cancelError{taskID: request.operation.taskID}
	}

	destinationDirectory := filepath.Dir(request.destinationPath)
	if err := os.MkdirAll(destinationDirectory, 0o700); err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	file, err := os.CreateTemp(destinationDirectory, ".swiftmtp-download-*")
	if err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	tempPath := file.Name()
	keepTemp := true
	defer func() {
		_ = file.Close()
		if keepTemp {
			_ = os.Remove(tempPath)
		}
	}()

	var info mtp.ObjectInfo
	if err := device.GetObjectInfo(request.objectID, &info); err != nil {
		return 0, fmt.Errorf("GetObjectInfo failed: %w", err)
	}
	device.Timeout = int(cfg.Timeouts.LargeFileDownload.Milliseconds())
	progress := request.progress
	if progress == nil {
		progress = func(uint64) {}
	}
	err = device.GetObject(request.objectID, file, func(bytes int64) error {
		if request.operation != nil && request.operation.isCancelled() {
			return &cancelError{taskID: request.operation.taskID}
		}
		if bytes < 0 {
			return fmt.Errorf("download reported a negative byte count")
		}
		progress(uint64(bytes))
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("GetObject failed: %w", err)
	}
	if err := file.Sync(); err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	if err := file.Close(); err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	stat, err := os.Stat(tempPath)
	if err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	actualBytes := uint64(stat.Size())
	if info.CompressedSize != uploadCompressedSizeSentinel &&
		actualBytes != uint64(info.CompressedSize) {
		return 0, fmt.Errorf(
			"download size mismatch: received %d, expected %d",
			actualBytes,
			info.CompressedSize,
		)
	}
	if err := os.Rename(tempPath, request.destinationPath); err != nil {
		return 0, newTransferError(transferErrorLocalIO, err)
	}
	keepTemp = false
	progress(actualBytes)
	return actualBytes, nil
}
