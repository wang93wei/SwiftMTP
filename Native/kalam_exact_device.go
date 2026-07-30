package main

import (
	"errors"
	"fmt"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

type nativeDeviceSession struct {
	locator usbDeviceLocator
	device  *mtp.Device

	fetchDeviceInfo func() (*mtp.DeviceInfo, error)
	fetchStorages   func() ([]mtpx.StorageData, error)
	listFiles       func(storageID uint32, parentID uint32) (nativeDirectoryListing, error)
	createFolder    func(storageID uint32, parentID uint32, name string) (uint32, error)
	deleteObject    func(objectID uint32) error
	downloadFile    func(request nativeDownloadRequest) (uint64, error)
	uploadFile      func(request nativeUploadRequest) (uint64, error)
	refreshStorage  func(storageID uint32) (StorageJSON, error)
	dispose         func()
}

type nativeObjectFailure struct {
	StorageID uint32 `json:"storageId"`
	ParentID  uint32 `json:"parentId"`
	ObjectID  uint32 `json:"objectId"`
	Stage     string `json:"stage"`
	Error     string `json:"error"`
}

type nativeDirectoryListing struct {
	Files    []FileJSON
	Failures []nativeObjectFailure
}

func openLiveNativeSession(locator usbDeviceLocator) (*nativeDeviceSession, error) {
	device, err := mtpx.InitializeExact(mtpx.Init{DebugMode: false}, locator.vendorLocator())
	if err != nil {
		return nil, fmt.Errorf("open exact MTP device: %w", err)
	}
	session := &nativeDeviceSession{
		locator: locator,
		device:  device,
	}
	session.fetchDeviceInfo = func() (*mtp.DeviceInfo, error) {
		return mtpx.FetchDeviceInfo(device)
	}
	session.fetchStorages = func() ([]mtpx.StorageData, error) {
		return mtpx.FetchStorages(device)
	}
	session.listFiles = func(storageID uint32, parentID uint32) (nativeDirectoryListing, error) {
		var handles mtp.Uint32Array
		if err := device.GetObjectHandles(storageID, 0, parentID, &handles); err != nil {
			return nativeDirectoryListing{}, fmt.Errorf("GetObjectHandles failed: %w", err)
		}
		files := make([]FileJSON, 0, len(handles.Values))
		failures := make([]nativeObjectFailure, 0)
		for _, handle := range handles.Values {
			var info mtp.ObjectInfo
			if err := device.GetObjectInfo(handle, &info); err != nil {
				if isInvalidObjectHandleError(err) {
					failures = append(failures, nativeObjectFailure{
						StorageID: storageID,
						ParentID:  parentID,
						ObjectID:  handle,
						Stage:     "object_info",
						Error:     "invalid_object_handle",
					})
					continue
				}
				return nativeDirectoryListing{}, fmt.Errorf(
					"GetObjectInfo %d failed: %w",
					handle,
					err,
				)
			}
			files = append(files, FileJSON{
				ID:        handle,
				ParentID:  info.ParentObject,
				StorageID: info.StorageID,
				Name:      info.Filename,
				Size:      uint64(info.CompressedSize),
				IsFolder:  info.ObjectFormat == ObjectFormatFolder,
				ModTime:   info.ModificationDate.Unix(),
			})
		}
		return nativeDirectoryListing{Files: files, Failures: failures}, nil
	}
	session.createFolder = func(storageID uint32, parentID uint32, name string) (uint32, error) {
		info := mtp.ObjectInfo{
			StorageID:      storageID,
			ParentObject:   parentID,
			Filename:       name,
			ObjectFormat:   ObjectFormatFolder,
			CompressedSize: 0,
		}
		_, _, handle, err := device.SendObjectInfo(storageID, parentID, &info)
		if err != nil {
			return 0, fmt.Errorf("SendObjectInfo failed: %w", err)
		}
		return handle, nil
	}
	session.deleteObject = func(objectID uint32) error {
		if err := device.DeleteObject(objectID); err != nil {
			return fmt.Errorf("DeleteObject failed: %w", err)
		}
		return nil
	}
	session.downloadFile = func(request nativeDownloadRequest) (uint64, error) {
		return downloadFromMTPDevice(device, request)
	}
	session.uploadFile = func(request nativeUploadRequest) (uint64, error) {
		return uploadToMTPDevice(device, request)
	}
	session.refreshStorage = func(storageID uint32) (StorageJSON, error) {
		var info mtp.StorageInfo
		if err := device.GetStorageInfo(storageID, &info); err != nil {
			return StorageJSON{}, fmt.Errorf("GetStorageInfo failed: %w", err)
		}
		return StorageJSON{
			ID:          storageID,
			Description: info.StorageDescription,
			FreeSpace:   info.FreeSpaceInBytes,
			MaxCapacity: info.MaxCapability,
		}, nil
	}
	session.dispose = func() {
		mtpx.Dispose(device)
	}
	return session, nil
}

func isInvalidObjectHandleError(err error) bool {
	var responseError mtp.RCError
	return errors.As(err, &responseError) &&
		uint16(responseError) == uint16(mtp.RC_InvalidObjectHandle)
}
