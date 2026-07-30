package main

import (
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
)

func TestCanonicalDeviceLocatorsRemainStableAcrossEnumerationOrder(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}

	forward := canonicalLocatorSet([]usbDeviceLocator{a, b})
	reverse := canonicalLocatorSet([]usbDeviceLocator{b, a})

	if forward[0] != reverse[0] || forward[1] != reverse[1] {
		t.Fatalf("locator set changed after enumeration reorder: %v != %v", forward, reverse)
	}
	if forward[0] == forward[1] {
		t.Fatalf("same VID/PID devices on different paths must stay distinct: %v", forward)
	}
}

func TestCanonicalDeviceLocatorRejectsMissingPortPath(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, VendorID: 0x18d1, ProductID: 0x4ee1}
	if _, err := locator.canonicalID(); err == nil {
		t.Fatal("expected missing port path to fail closed")
	}
}

func TestInjectableScanPreservesLiveShapedIdentityAcrossReverseEnumeration(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	makeRegistry := func() *nativeSessionRegistry {
		return newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
			session := fakeNativeSession(locator, nil)
			session.fetchDeviceInfo = func() (*mtp.DeviceInfo, error) {
				return &mtp.DeviceInfo{
					Manufacturer: "Acme",
					Model:        "Phone",
					MTPVersion:   100,
				}, nil
			}
			session.fetchStorages = func() ([]mtpx.StorageData, error) {
				return []mtpx.StorageData{}, nil
			}
			return session, nil
		})
	}

	forward, err := scanNativeDevices(func() ([]usbDeviceLocator, error) {
		return []usbDeviceLocator{a, b}, nil
	}, makeRegistry())
	if err != nil {
		t.Fatalf("forward scan: %v", err)
	}
	reverse, err := scanNativeDevices(func() ([]usbDeviceLocator, error) {
		return []usbDeviceLocator{b, a}, nil
	}, makeRegistry())
	if err != nil {
		t.Fatalf("reverse scan: %v", err)
	}

	forwardIDs := []string{forward.Devices[0].ID, forward.Devices[1].ID}
	reverseIDs := []string{reverse.Devices[0].ID, reverse.Devices[1].ID}
	sortStrings(forwardIDs)
	sortStrings(reverseIDs)
	if forwardIDs[0] != reverseIDs[0] || forwardIDs[1] != reverseIDs[1] {
		t.Fatalf("scan identity changed after reorder: %v != %v", forwardIDs, reverseIDs)
	}
}

func TestInjectableScanPreservesPartialFailures(t *testing.T) {
	healthy := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	failed := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		if sameUSBLocator(locator, failed) {
			return nil, errNativeDisconnected
		}
		session := fakeNativeSession(locator, nil)
		session.fetchDeviceInfo = func() (*mtp.DeviceInfo, error) {
			return &mtp.DeviceInfo{Manufacturer: "Acme", Model: "Phone"}, nil
		}
		session.fetchStorages = func() ([]mtpx.StorageData, error) {
			return nil, errors.New("storage unavailable")
		}
		return session, nil
	})

	result, err := scanNativeDevices(func() ([]usbDeviceLocator, error) {
		return []usbDeviceLocator{healthy, failed}, nil
	}, registry)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if len(result.Devices) != 1 || len(result.Failures) != 2 {
		t.Fatalf("partial scan result = %+v", result)
	}
	healthyID, _ := healthy.canonicalID()
	failedID, _ := failed.canonicalID()
	if result.Failures[0].DeviceID != healthyID || result.Failures[0].Stage != "storage" {
		t.Fatalf("storage failure missing identity/stage: %+v", result.Failures[0])
	}
	if result.Failures[1].DeviceID != failedID ||
		result.Failures[1].Stage != "device" ||
		result.Failures[1].Error != "disconnected" {
		t.Fatalf("device failure missing typed metadata: %+v", result.Failures[1])
	}
}

func TestExactOpenPinsRequestedLocator(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	var opened []string
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		id, _ := locator.canonicalID()
		opened = append(opened, id)
		return fakeNativeSession(locator, nil), nil
	})

	token, err := registry.open(a)
	if err != nil {
		t.Fatalf("open A: %v", err)
	}
	defer registry.close(token)

	aID, _ := a.canonicalID()
	bID, _ := b.canonicalID()
	if len(opened) != 1 || opened[0] != aID || opened[0] == bID {
		t.Fatalf("exact opener selected wrong device: opened=%v", opened)
	}
}

func TestExactOpenUnknownLocatorFailsWithoutFallback(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		if sameUSBLocator(locator, a) {
			return fakeNativeSession(a, nil), nil
		}
		return nil, errNativeDisconnected
	})

	if _, err := registry.open(b); !errors.Is(err, errNativeDisconnected) {
		t.Fatalf("unknown exact locator must fail closed: %v", err)
	}
}

func TestExactOpenRejectsSecondSessionForSameLocator(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	openCount := 0
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		openCount++
		return fakeNativeSession(locator, nil), nil
	})

	token, err := registry.open(locator)
	if err != nil {
		t.Fatalf("first open: %v", err)
	}
	defer registry.close(token)

	if _, err := registry.open(locator); err == nil {
		t.Fatal("second session for the same physical locator must fail closed")
	}
	if openCount != 1 {
		t.Fatalf("duplicate admission called opener %d times", openCount)
	}
}

func TestNativeSessionTokensPreventCrossDeviceOperationsWithCollidingIDs(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	var callsMu sync.Mutex
	var calls []string
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		id, _ := locator.canonicalID()
		return fakeNativeSession(locator, func(operation string) {
			callsMu.Lock()
			calls = append(calls, id+":"+operation)
			callsMu.Unlock()
		}), nil
	})

	tokenA, _ := registry.open(a)
	tokenB, _ := registry.open(b)
	defer registry.close(tokenA)
	defer registry.close(tokenB)

	if err := registry.withSession(tokenA, func(session *nativeDeviceSession) error {
		_, err := session.listFiles(1, 0xffffffff)
		return err
	}); err != nil {
		t.Fatalf("list A: %v", err)
	}
	if err := registry.withSession(tokenB, func(session *nativeDeviceSession) error {
		return session.deleteObject(7)
	}); err != nil {
		t.Fatalf("delete B: %v", err)
	}
	if err := registry.withSession(tokenA, func(session *nativeDeviceSession) error {
		_, err := session.createFolder(1, 0xffffffff, "folder")
		return err
	}); err != nil {
		t.Fatalf("create A: %v", err)
	}
	if err := registry.withSession(tokenB, func(session *nativeDeviceSession) error {
		_, err := session.refreshStorage(1)
		return err
	}); err != nil {
		t.Fatalf("refresh B: %v", err)
	}

	aID, _ := a.canonicalID()
	bID, _ := b.canonicalID()
	expected := []string{
		aID + ":list",
		bID + ":delete",
		aID + ":create",
		bID + ":refresh",
	}
	if len(calls) != len(expected) {
		t.Fatalf("operations crossed device sessions: %v", calls)
	}
	for index := range expected {
		if calls[index] != expected[index] {
			t.Fatalf("operations crossed device sessions: %v", calls)
		}
	}
}

func sortStrings(values []string) {
	for left := range values {
		for right := left + 1; right < len(values); right++ {
			if values[right] < values[left] {
				values[left], values[right] = values[right], values[left]
			}
		}
	}
}

func TestNativeSessionStaleTokenDisconnectReconnectAndIdempotentClose(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	var opens atomic.Int32
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		opens.Add(1)
		session := fakeNativeSession(locator, nil)
		if opens.Load() == 1 {
			session.listFiles = func(uint32, uint32) (nativeDirectoryListing, error) {
				return nativeDirectoryListing{}, errNativeDisconnected
			}
		}
		return session, nil
	})
	if err := registry.withSession("never-issued", func(*nativeDeviceSession) error { return nil }); !errors.Is(err, errUnknownSessionToken) {
		t.Fatalf("expected unknown token error, got %v", err)
	}

	first, _ := registry.open(locator)
	err := registry.withSession(first, func(session *nativeDeviceSession) error {
		_, err := session.listFiles(1, 0xffffffff)
		return err
	})
	if !errors.Is(err, errNativeDisconnected) {
		t.Fatalf("expected disconnect, got %v", err)
	}
	if err := registry.withSession(first, func(*nativeDeviceSession) error { return nil }); !errors.Is(err, errStaleSessionToken) {
		t.Fatalf("expected stale token, got %v", err)
	}
	if err := registry.close(first); err != nil {
		t.Fatalf("close disconnected token must be idempotent: %v", err)
	}

	second, err := registry.open(locator)
	if err != nil {
		t.Fatalf("reopen same topology: %v", err)
	}
	if first == second {
		t.Fatal("reconnect must create a new opaque token")
	}
	if err := registry.close(second); err != nil {
		t.Fatalf("close: %v", err)
	}
	if err := registry.close(second); err != nil {
		t.Fatalf("second close: %v", err)
	}
}

func TestNativeSessionCleanupAndOperationRaceDisposesOnce(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	started := make(chan struct{})
	release := make(chan struct{})
	var disposeCount atomic.Int32
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		session := fakeNativeSession(locator, nil)
		session.dispose = func() { disposeCount.Add(1) }
		return session, nil
	})
	token, _ := registry.open(locator)

	operationDone := make(chan error, 1)
	go func() {
		operationDone <- registry.withSession(token, func(*nativeDeviceSession) error {
			close(started)
			<-release
			return nil
		})
	}()
	<-started

	cleanupDone := make(chan struct{})
	go func() {
		registry.cleanup()
		close(cleanupDone)
	}()
	close(release)
	if err := <-operationDone; err != nil {
		t.Fatalf("in-flight operation failed: %v", err)
	}
	<-cleanupDone

	if disposeCount.Load() != 1 {
		t.Fatalf("expected one dispose, got %d", disposeCount.Load())
	}
	if _, err := registry.open(locator); !errors.Is(err, errBridgeShuttingDown) {
		t.Fatalf("open after cleanup must fail closed: %v", err)
	}
}

func TestLegacyTransferCompatibilityRequiresExactlyOneActiveSession(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		return fakeNativeSession(locator, nil), nil
	})

	if err := registry.withLegacySession(func(*nativeDeviceSession) error { return nil }); !errors.Is(err, errAmbiguousLegacySession) {
		t.Fatalf("zero sessions must fail closed: %v", err)
	}
	tokenA, _ := registry.open(a)
	if err := registry.withLegacySession(func(*nativeDeviceSession) error { return nil }); err != nil {
		t.Fatalf("one active exact session should be reusable: %v", err)
	}
	tokenB, _ := registry.open(b)
	if err := registry.withLegacySession(func(*nativeDeviceSession) error { return nil }); !errors.Is(err, errAmbiguousLegacySession) {
		t.Fatalf("multiple sessions must fail closed: %v", err)
	}
	_ = registry.close(tokenA)
	_ = registry.close(tokenB)
}

func TestOnlyInvalidObjectHandleIsRecoverableDuringListing(t *testing.T) {
	invalidHandle := fmt.Errorf(
		"GetObjectInfo failed: %w",
		mtp.RCError(mtp.RC_InvalidObjectHandle),
	)
	if !isInvalidObjectHandleError(invalidHandle) {
		t.Fatal("invalid object handle should be recoverable")
	}
	if isInvalidObjectHandleError(mtp.RCError(mtp.RC_GeneralError)) {
		t.Fatal("other MTP response errors must terminate the listing")
	}
	if isInvalidObjectHandleError(errNativeDisconnected) {
		t.Fatal("disconnect must terminate the listing")
	}
}

func fakeNativeSession(
	locator usbDeviceLocator,
	record func(operation string),
) *nativeDeviceSession {
	if record == nil {
		record = func(string) {}
	}
	return &nativeDeviceSession{
		locator: locator,
		listFiles: func(uint32, uint32) (nativeDirectoryListing, error) {
			record("list")
			return nativeDirectoryListing{Files: []FileJSON{}}, nil
		},
		createFolder: func(uint32, uint32, string) (uint32, error) {
			record("create")
			return 7, nil
		},
		deleteObject: func(uint32) error {
			record("delete")
			return nil
		},
		refreshStorage: func(uint32) (StorageJSON, error) {
			record("refresh")
			return StorageJSON{ID: 1}, nil
		},
		dispose: func() {},
	}
}
