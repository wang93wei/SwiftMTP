package main

import (
	"errors"
	"testing"
)

func TestExactTransferRoutesOnlyThroughRequestedOpaqueSessionToken(t *testing.T) {
	a := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	b := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 4}, VendorID: 0x18d1, ProductID: 0x4ee1}
	var calls []string
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		id, _ := locator.canonicalID()
		session := fakeNativeSession(locator, nil)
		session.downloadFile = func(request nativeDownloadRequest) (uint64, error) {
			calls = append(calls, id+":download")
			request.progress(4)
			return 4, nil
		}
		session.uploadFile = func(request nativeUploadRequest) (uint64, error) {
			calls = append(calls, id+":upload")
			request.progress(5)
			return 5, nil
		}
		return session, nil
	})
	tokenA, err := registry.open(a)
	if err != nil {
		t.Fatal(err)
	}
	tokenB, err := registry.open(b)
	if err != nil {
		t.Fatal(err)
	}
	defer registry.close(tokenA)
	defer registry.close(tokenB)

	var progress []uint64
	if _, err := registry.download(tokenA, nativeDownloadRequest{
		objectID:        9,
		destinationPath: "/tmp/a",
		progress:        func(bytes uint64) { progress = append(progress, bytes) },
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := registry.upload(tokenB, nativeUploadRequest{
		storageID:  1,
		parentID:   ^uint32(0),
		sourcePath: "/tmp/b",
		name:       "b",
		size:       5,
		progress:   func(bytes uint64) { progress = append(progress, bytes) },
	}); err != nil {
		t.Fatal(err)
	}

	aID, _ := a.canonicalID()
	bID, _ := b.canonicalID()
	if len(calls) != 2 || calls[0] != aID+":download" || calls[1] != bID+":upload" {
		t.Fatalf("exact transfer crossed sessions: %v", calls)
	}
	if len(progress) != 2 || progress[0] != 4 || progress[1] != 5 {
		t.Fatalf("progress = %v", progress)
	}
}

func TestExactTransferRejectsUnknownAndStaleTokensWithoutCallingSession(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	callCount := 0
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		session := fakeNativeSession(locator, nil)
		session.downloadFile = func(nativeDownloadRequest) (uint64, error) {
			callCount++
			return 0, nil
		}
		return session, nil
	})

	if _, err := registry.download("unknown", nativeDownloadRequest{}); !errors.Is(err, errUnknownSessionToken) {
		t.Fatalf("unknown token error = %v", err)
	}
	token, err := registry.open(locator)
	if err != nil {
		t.Fatal(err)
	}
	if err := registry.close(token); err != nil {
		t.Fatal(err)
	}
	if _, err := registry.download(token, nativeDownloadRequest{}); !errors.Is(err, errStaleSessionToken) {
		t.Fatalf("stale token error = %v", err)
	}
	if callCount != 0 {
		t.Fatalf("rejected token called transfer %d times", callCount)
	}
}

func TestExactUploadFailureIsNotReplayed(t *testing.T) {
	locator := usbDeviceLocator{Bus: 1, PortPath: []uint8{2, 3}, VendorID: 0x18d1, ProductID: 0x4ee1}
	callCount := 0
	uploadErr := newTransferError(transferErrorLocalIO, errors.New("source read failed"))
	registry := newNativeSessionRegistry(func(locator usbDeviceLocator) (*nativeDeviceSession, error) {
		session := fakeNativeSession(locator, nil)
		session.uploadFile = func(nativeUploadRequest) (uint64, error) {
			callCount++
			return 0, uploadErr
		}
		return session, nil
	})
	token, err := registry.open(locator)
	if err != nil {
		t.Fatal(err)
	}
	defer registry.close(token)

	if _, err := registry.upload(token, nativeUploadRequest{}); !errors.Is(err, uploadErr) {
		t.Fatalf("upload error = %v", err)
	}
	if callCount != 1 {
		t.Fatalf("failed upload was executed %d times", callCount)
	}
}

func TestTransferBridgeErrorCodesRemainStructured(t *testing.T) {
	for _, test := range []struct {
		err  error
		code string
	}{
		{err: &cancelError{taskID: "task"}, code: "cancelled"},
		{err: newTransferError(transferErrorInvalidInput, errors.New("bad request")), code: "invalid_input"},
		{err: newTransferError(transferErrorLocalIO, errors.New("disk")), code: "local_io"},
		{err: newTransferError(transferErrorTimeout, errors.New("timeout")), code: "timeout"},
		{err: errNativeDisconnected, code: "disconnected"},
	} {
		if got := nativeTransferErrorCode(test.err); got != test.code {
			t.Fatalf("nativeTransferErrorCode(%v) = %q, want %q", test.err, got, test.code)
		}
	}
}
