package main

import (
	"fmt"
	"sync"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

// Device connection pool to avoid frequent initialization/disposal
// This prevents TLS key exhaustion in libusb
type devicePoolEntry struct {
	device   *mtp.Device
	lastUsed time.Time
	inUse    bool
	disposed bool
}

var (
	devicePool          []*devicePoolEntry
	devicePoolMu        sync.RWMutex
	disposePooledDevice = mtpx.Dispose
)

func disposePoolEntryLocked(entry *devicePoolEntry) {
	if entry == nil || entry.device == nil || entry.disposed {
		return
	}
	entry.disposed = true
	disposePooledDevice(entry.device)
}

func disposeDevicePool() {
	devicePoolMu.Lock()
	defer devicePoolMu.Unlock()
	for _, entry := range devicePool {
		disposePoolEntryLocked(entry)
	}
	devicePool = nil
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
			disposePoolEntryLocked(entry)
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
				disposePoolEntryLocked(entry)
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
			disposePoolEntryLocked(devicePool[oldestIndex])
			devicePool = append(devicePool[:oldestIndex], devicePool[oldestIndex+1:]...)
		}
	}

	for _, existing := range devicePool {
		if existing == entry {
			return
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
			disposePoolEntryLocked(e)
			devicePool = append(devicePool[:i], devicePool[i+1:]...)
			return
		}
	}
}
