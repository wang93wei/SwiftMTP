package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

//export Kalam_UploadFile
func Kalam_UploadFile(storageID uint32, parentID uint32, sourcePath *C.char, taskID *C.char) int32 {
	if taskID == nil {
		fmt.Printf("Kalam_UploadFile: taskID is nil\n")
		return 0
	}
	taskIDStr := C.GoString(taskID)
	operation, err := transferCancellations.begin(taskIDStr)
	if err != nil {
		fmt.Printf("Kalam_UploadFile: %v\n", err)
		return 0
	}
	defer operation.finish()

	storageIDTyped := StorageID(storageID)
	parentIDTyped := ParentID(parentID)
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
	path := C.GoString(sourcePath)
	if path == "" {
		fmt.Printf("Kalam_UploadFile: Empty source path\n")
		return 0
	}
	if operation.isCancelled() {
		fmt.Printf("Kalam_UploadFile: Task %s was cancelled before start\n", taskIDStr)
		return 0
	}

	source, err := inspectUploadSource(path, cfg.FileSize.MaxSize)
	if err != nil {
		fmt.Printf("Kalam_UploadFile: Invalid upload source: %v\n", err)
		return 0
	}
	defer source.file.Close()

	if operation.isCancelled() {
		fmt.Printf("Kalam_UploadFile: Task %s was cancelled before mutation\n", taskIDStr)
		return 0
	}

	fmt.Printf("Kalam_UploadFile: Starting upload of %s (%d bytes)\n", source.name, source.size)

	var result int32

	err = withLegacyMTPDevice(func(dev *mtp.Device) error {
		var objInfo mtp.ObjectInfo
		objInfo.StorageID = uint32(storageIDTyped)
		objInfo.ParentObject = uint32(parentIDTyped)
		objInfo.Filename = source.name
		objInfo.ObjectFormat = ObjectFormatGenericFile
		objInfo.CompressedSize = source.compressedSize
		objInfo.ModificationDate = time.Unix(source.modification, 0)

		fmt.Printf("Kalam_UploadFile: Sending object info for %s\n", source.name)

		_, _, newHandle, err := dev.SendObjectInfo(uint32(storageIDTyped), uint32(parentIDTyped), &objInfo)
		if err != nil {
			fmt.Printf("Kalam_UploadFile: SendObjectInfo failed: %v\n", err)
			return fmt.Errorf("SendObjectInfo failed: %w", err)
		}

		fmt.Printf("Kalam_UploadFile: Got handle %d for %s\n", newHandle, source.name)

		if operation.isCancelled() {
			fmt.Printf("Kalam_UploadFile: Task %s cancelled before data transfer\n", taskIDStr)
			return &cancelError{taskID: taskIDStr}
		}

		fmt.Printf("Kalam_UploadFile: Starting data transfer for %s\n", source.name)

		if _, err := source.file.Seek(0, 0); err != nil {
			fmt.Printf("Kalam_UploadFile: Failed to seek file: %v\n", err)
			return fmt.Errorf("failed to seek file: %w", err)
		}

		progressCb := func(sent int64) error {
			if operation.isCancelled() {
				fmt.Printf("Kalam_UploadFile: Task %s cancelled during transfer (sent %d bytes)\n", taskIDStr, sent)
				return &cancelError{taskID: taskIDStr}
			}
			return nil
		}

		err = dev.SendObject(source.file, source.size, progressCb)

		if err != nil {
			fmt.Printf("Kalam_UploadFile: SendObject failed: %v\n", err)
			return fmt.Errorf("SendObject failed: %w", err)
		}

		fmt.Printf("Kalam_UploadFile: Successfully uploaded %s (%d bytes)\n", source.name, source.size)

		result = 1
		return nil
	})

	if err != nil {
		fmt.Printf("Kalam_UploadFile: Upload failed: %v\n", err)
		return 0
	}

	return result
}
