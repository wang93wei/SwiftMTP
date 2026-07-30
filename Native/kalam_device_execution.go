package main

import (
	"fmt"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

var deviceMu sync.Mutex

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
	if bridgeShutdownFlag.Load() {
		return fmt.Errorf("bridge is shutting down")
	}

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
	if bridgeShutdownFlag.Load() {
		return fmt.Errorf("bridge is shutting down")
	}

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
