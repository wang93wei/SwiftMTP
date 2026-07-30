package main

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

func TestKalamInitIsIdempotentAndReloadsConfigAfterCleanup(t *testing.T) {
	Kalam_CleanupDevicePool()
	t.Cleanup(Kalam_CleanupDevicePool)

	firstDownloadDir := t.TempDir()
	t.Setenv("DOWNLOAD_DIR", firstDownloadDir)
	Kalam_Init()

	first := bridgeRuntime.snapshot()
	if !first.initialized || first.worker == nil {
		t.Fatal("Kalam_Init must start one cleanup worker")
	}
	if cfg.Download.DefaultDir != firstDownloadDir {
		t.Fatalf("first init loaded download dir %q, want %q", cfg.Download.DefaultDir, firstDownloadDir)
	}

	secondDownloadDir := t.TempDir()
	t.Setenv("DOWNLOAD_DIR", secondDownloadDir)
	Kalam_Init()

	idempotent := bridgeRuntime.snapshot()
	if idempotent.generation != first.generation || idempotent.worker != first.worker {
		t.Fatal("repeated Kalam_Init must reuse the active runtime generation")
	}
	if cfg.Download.DefaultDir != firstDownloadDir {
		t.Fatalf("repeated init unexpectedly reloaded config: got %q", cfg.Download.DefaultDir)
	}

	Kalam_CleanupDevicePool()
	stopped := bridgeRuntime.snapshot()
	if stopped.initialized || stopped.worker != nil {
		t.Fatal("cleanup must stop and detach the active cleanup worker")
	}

	Kalam_Init()
	reinitialized := bridgeRuntime.snapshot()
	if reinitialized.generation != first.generation+1 {
		t.Fatalf(
			"re-init generation = %d, want %d",
			reinitialized.generation,
			first.generation+1,
		)
	}
	if reinitialized.worker == nil || reinitialized.worker == first.worker {
		t.Fatal("re-init must create a fresh cleanup worker")
	}
	if cfg.Download.DefaultDir != secondDownloadDir {
		t.Fatalf("re-init loaded download dir %q, want %q", cfg.Download.DefaultDir, secondDownloadDir)
	}
}

func TestInactiveNativeRegistryRequiresExplicitInitialize(t *testing.T) {
	locator := usbDeviceLocator{
		Bus:       1,
		PortPath:  []uint8{2, 3},
		VendorID:  0x18d1,
		ProductID: 0x4ee1,
	}
	registry := newInactiveNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		return fakeNativeSession(locator, nil), nil
	})

	if _, err := registry.open(locator); !errors.Is(err, errBridgeShuttingDown) {
		t.Fatalf("open before explicit init must fail closed: %v", err)
	}
	registry.initialize()
	token, err := registry.open(locator)
	if err != nil {
		t.Fatalf("open after explicit init: %v", err)
	}
	if err := registry.close(token); err != nil {
		t.Fatalf("close initialized session: %v", err)
	}
}

func TestConcurrentKalamInitStartsOneRuntimeGeneration(t *testing.T) {
	Kalam_CleanupDevicePool()
	t.Cleanup(Kalam_CleanupDevicePool)
	before := bridgeRuntime.snapshot()

	const callerCount = 16
	var callers sync.WaitGroup
	callers.Add(callerCount)
	for range callerCount {
		go func() {
			defer callers.Done()
			Kalam_Init()
		}()
	}
	callers.Wait()

	after := bridgeRuntime.snapshot()
	if !after.initialized || after.worker == nil {
		t.Fatal("concurrent init must leave one active cleanup worker")
	}
	if after.generation != before.generation+1 {
		t.Fatalf(
			"concurrent init generation = %d, want %d",
			after.generation,
			before.generation+1,
		)
	}
}

func TestPoolCleanupWorkerStopWaitsForRunningCleanup(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	worker := startPoolCleanupWorker(time.Millisecond, func() {
		once.Do(func() { close(started) })
		<-release
	})
	<-started

	stopped := make(chan struct{})
	go func() {
		worker.stopAndWait()
		close(stopped)
	}()

	select {
	case <-stopped:
		t.Fatal("worker stop returned before the running cleanup completed")
	case <-time.After(20 * time.Millisecond):
	}

	close(release)
	select {
	case <-stopped:
	case <-time.After(time.Second):
		t.Fatal("worker stop did not join the running cleanup")
	}
}

func TestKalamCleanupWaitsForPoolOperationAndDisposesOnce(t *testing.T) {
	Kalam_CleanupDevicePool()
	Kalam_Init()
	t.Cleanup(Kalam_CleanupDevicePool)

	originalDispose := disposePooledDevice
	var disposeCount atomic.Int32
	disposePooledDevice = func(*mtp.Device) {
		disposeCount.Add(1)
	}
	t.Cleanup(func() {
		disposePooledDevice = originalDispose
	})

	entry := &devicePoolEntry{
		device:   &mtp.Device{},
		lastUsed: time.Now(),
	}
	devicePoolMu.Lock()
	devicePool = []*devicePoolEntry{entry, entry}
	devicePoolMu.Unlock()

	deviceMu.Lock()
	cleanupDone := make(chan struct{})
	go func() {
		Kalam_CleanupDevicePool()
		close(cleanupDone)
	}()

	select {
	case <-cleanupDone:
		t.Fatal("cleanup returned while a pooled-device operation was still active")
	case <-time.After(20 * time.Millisecond):
	}
	if disposeCount.Load() != 0 {
		t.Fatal("pool device was disposed while an operation still owned deviceMu")
	}

	deviceMu.Unlock()
	select {
	case <-cleanupDone:
	case <-time.After(time.Second):
		t.Fatal("cleanup did not complete after the pooled-device operation ended")
	}
	if disposeCount.Load() != 1 {
		t.Fatalf("cleanup dispose count = %d, want 1", disposeCount.Load())
	}

	Kalam_CleanupDevicePool()
	if disposeCount.Load() != 1 {
		t.Fatalf("repeated cleanup dispose count = %d, want 1", disposeCount.Load())
	}
}
