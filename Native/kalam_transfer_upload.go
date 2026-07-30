package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

type mtpUploadDevice interface {
	SendObjectInfo(uint32, uint32, *mtp.ObjectInfo) (uint32, uint32, uint32, error)
	SendObject(io.Reader, int64, mtp.ProgressFunc) error
	DeleteObject(uint32) error
}

func uploadToMTPDevice(
	device mtpUploadDevice,
	request nativeUploadRequest,
) (uint64, error) {
	if device == nil {
		return 0, errNativeDisconnected
	}
	if err := StorageID(request.storageID).Validate(); err != nil {
		return 0, newTransferError(transferErrorInvalidInput, err)
	}
	if err := ParentID(request.parentID).Validate(); err != nil {
		return 0, newTransferError(transferErrorInvalidInput, err)
	}
	if request.operation != nil && request.operation.isCancelled() {
		return 0, &cancelError{taskID: request.operation.taskID}
	}
	source, err := inspectUploadSource(request.sourcePath, cfg.FileSize.MaxSize)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			return 0, newTransferError(transferErrorLocalIO, err)
		}
		return 0, newTransferError(transferErrorInvalidInput, err)
	}
	defer source.file.Close()
	if request.name != source.name || request.size != uint64(source.size) {
		return 0, newTransferError(
			transferErrorInvalidInput,
			fmt.Errorf("upload request does not match inspected source"),
		)
	}
	if request.operation != nil && request.operation.isCancelled() {
		return 0, &cancelError{taskID: request.operation.taskID}
	}

	info := mtp.ObjectInfo{
		StorageID:        request.storageID,
		ParentObject:     request.parentID,
		Filename:         request.name,
		ObjectFormat:     ObjectFormatGenericFile,
		CompressedSize:   source.compressedSize,
		ModificationDate: time.Unix(source.modification, 0),
	}
	_, _, objectID, err := device.SendObjectInfo(request.storageID, request.parentID, &info)
	if err != nil {
		return 0, fmt.Errorf("SendObjectInfo failed: %w", err)
	}
	failAfterObjectInfo := func(primary error) (uint64, error) {
		if objectID == 0 {
			return 0, primary
		}
		if cleanupErr := device.DeleteObject(objectID); cleanupErr != nil {
			return 0, fmt.Errorf(
				"upload failed and object %d cleanup failed: %v; primary error: %w",
				objectID,
				cleanupErr,
				primary,
			)
		}
		return 0, primary
	}
	if request.operation != nil && request.operation.isCancelled() {
		return failAfterObjectInfo(&cancelError{taskID: request.operation.taskID})
	}
	if _, err := source.file.Seek(0, 0); err != nil {
		return failAfterObjectInfo(newTransferError(transferErrorLocalIO, err))
	}
	progress := request.progress
	if progress == nil {
		progress = func(uint64) {}
	}
	err = device.SendObject(source.file, source.size, func(bytes int64) error {
		if request.operation != nil && request.operation.isCancelled() {
			return &cancelError{taskID: request.operation.taskID}
		}
		if bytes < 0 {
			return fmt.Errorf("upload reported a negative byte count")
		}
		progress(uint64(bytes))
		return nil
	})
	if err != nil {
		return failAfterObjectInfo(fmt.Errorf("SendObject failed: %w", err))
	}
	progress(request.size)
	return request.size, nil
}
