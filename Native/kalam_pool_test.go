package main

import "testing"

func TestGetDeviceFromPoolEmpty(t *testing.T) {
	devicePoolMu.Lock()
	oldPool := devicePool
	devicePool = nil
	devicePoolMu.Unlock()

	t.Cleanup(func() {
		devicePoolMu.Lock()
		devicePool = oldPool
		devicePoolMu.Unlock()
	})

	if got := getDeviceFromPool(); got != nil {
		t.Fatalf("expected nil from empty pool, got %#v", got)
	}
	if got := getDeviceFromPool(); got != nil {
		t.Fatalf("expected nil from empty pool on second call, got %#v", got)
	}
}

func TestReturnDeviceToPoolSkipsInvalidEntry(t *testing.T) {
	devicePoolMu.Lock()
	oldPool := devicePool
	devicePool = nil
	devicePoolMu.Unlock()

	t.Cleanup(func() {
		devicePoolMu.Lock()
		devicePool = oldPool
		devicePoolMu.Unlock()
	})

	entry := &devicePoolEntry{}
	returnDeviceToPool(entry)

	devicePoolMu.RLock()
	defer devicePoolMu.RUnlock()
	if len(devicePool) != 0 {
		t.Fatalf("expected pool length 0, got %d", len(devicePool))
	}
}

func TestRemoveClosedDeviceFromPoolSkipsInvalidEntry(t *testing.T) {
	devicePoolMu.Lock()
	oldPool := devicePool
	devicePool = nil
	devicePoolMu.Unlock()

	t.Cleanup(func() {
		devicePoolMu.Lock()
		devicePool = oldPool
		devicePoolMu.Unlock()
	})

	entry := &devicePoolEntry{}
	removeClosedDeviceFromPool(entry)

	devicePoolMu.RLock()
	defer devicePoolMu.RUnlock()
	if len(devicePool) != 0 {
		t.Fatalf("expected pool length 0, got %d", len(devicePool))
	}
}
