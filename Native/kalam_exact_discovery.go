package main

import (
	"fmt"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

type nativeDeviceEnumerator func() ([]usbDeviceLocator, error)

type nativeScanFailure struct {
	DeviceID  string  `json:"deviceId"`
	StorageID *uint32 `json:"storageId,omitempty"`
	Stage     string  `json:"stage"`
	Error     string  `json:"error"`
}

type nativeScanResult struct {
	Devices  []DeviceJSON        `json:"devices"`
	Failures []nativeScanFailure `json:"failures"`
}

func enumerateLiveDeviceLocators() ([]usbDeviceLocator, error) {
	locators, err := mtp.FindDeviceLocators()
	if err != nil {
		return nil, fmt.Errorf("enumerate MTP devices: %w", err)
	}
	result := make([]usbDeviceLocator, 0, len(locators))
	seen := make(map[string]struct{}, len(locators))
	for _, vendorLocator := range locators {
		locator := locatorFromVendor(vendorLocator)
		id, err := locator.canonicalID()
		if err != nil {
			return nil, err
		}
		if _, exists := seen[id]; exists {
			return nil, fmt.Errorf("duplicate physical MTP locator")
		}
		seen[id] = struct{}{}
		result = append(result, locator)
	}
	return result, nil
}

var liveDeviceEnumerator = enumerateLiveDeviceLocators

func scanNativeDevices(
	enumerate nativeDeviceEnumerator,
	registry *nativeSessionRegistry,
) (nativeScanResult, error) {
	locators, err := enumerate()
	if err != nil {
		return nativeScanResult{}, err
	}
	deviceList := make([]DeviceJSON, 0, len(locators))
	failures := make([]nativeScanFailure, 0)
	for _, locator := range locators {
		id, err := locator.canonicalID()
		if err != nil {
			return nativeScanResult{}, err
		}
		var info *mtp.DeviceInfo
		var storages []mtpx.StorageData
		var storageErr error
		err = registry.inspectLocator(locator, func(session *nativeDeviceSession) error {
			if session.fetchDeviceInfo == nil || session.fetchStorages == nil {
				return fmt.Errorf("exact session cannot inspect device")
			}
			var fetchErr error
			info, fetchErr = session.fetchDeviceInfo()
			if fetchErr != nil {
				return fmt.Errorf("FetchDeviceInfo failed: %w", fetchErr)
			}
			storages, fetchErr = session.fetchStorages()
			if fetchErr != nil {
				storages = []mtpx.StorageData{}
				storageErr = fmt.Errorf("FetchStorages failed: %w", fetchErr)
			}
			return nil
		})
		if err != nil {
			failures = append(failures, nativeScanFailure{
				DeviceID: id,
				Stage:    "device",
				Error:    nativeBridgeErrorCode(err),
			})
			continue
		}
		if storageErr != nil {
			failures = append(failures, nativeScanFailure{
				DeviceID: id,
				Stage:    "storage",
				Error:    nativeBridgeErrorCode(storageErr),
			})
		}
		deviceName := info.Model
		if info.Manufacturer != "" && !containsIgnoreCase(info.Model, info.Manufacturer) {
			deviceName = info.Manufacturer + " " + info.Model
		}
		device := DeviceJSON{
			ID:           id,
			Name:         deviceName,
			Manufacturer: info.Manufacturer,
			Model:        info.Model,
			SerialNumber: info.SerialNumber,
			Storage:      []StorageJSON{},
			MTPSupport: MTPSupportJSON{
				MtpVersion:      fmt.Sprintf("%d.%d", info.MTPVersion/100, (info.MTPVersion%100)/10),
				DeviceVersion:   info.DeviceVersion,
				VendorExtension: info.Manufacturer,
			},
		}
		for _, storage := range storages {
			device.Storage = append(device.Storage, StorageJSON{
				ID:          storage.Sid,
				Description: storage.Info.StorageDescription,
				FreeSpace:   storage.Info.FreeSpaceInBytes,
				MaxCapacity: storage.Info.MaxCapability,
			})
		}
		deviceList = append(deviceList, device)
	}
	return nativeScanResult{
		Devices:  deviceList,
		Failures: failures,
	}, nil
}
