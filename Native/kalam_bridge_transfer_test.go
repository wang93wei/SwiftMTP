package main

import (
	"errors"
	"io"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

func TestUploadDeletesAllocatedObjectWhenCancelledAfterObjectInfo(t *testing.T) {
	sourcePath := filepath.Join(t.TempDir(), "payload.bin")
	if err := os.WriteFile(sourcePath, []byte("payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	registry := newTransferCancellationRegistry()
	if err := registry.prepare("cancel-after-info"); err != nil {
		t.Fatal(err)
	}
	operation, err := registry.claim("cancel-after-info")
	if err != nil {
		t.Fatal(err)
	}
	defer operation.finish()
	device := &fakeUploadDevice{
		objectID: 42,
		afterObjectInfo: func() {
			registry.cancel(operation.taskID)
		},
	}

	_, err = uploadToMTPDevice(device, nativeUploadRequest{
		storageID:  1,
		parentID:   math.MaxUint32,
		sourcePath: sourcePath,
		name:       "payload.bin",
		size:       7,
		operation:  operation,
	})

	var cancelled *cancelError
	if !errors.As(err, &cancelled) {
		t.Fatalf("upload error = %v, want cancelError", err)
	}
	if device.sentObject {
		t.Fatal("cancelled upload must not send object bytes")
	}
	if len(device.deletedObjects) != 1 || device.deletedObjects[0] != 42 {
		t.Fatalf("deleted objects = %v, want [42]", device.deletedObjects)
	}
}

func TestUploadCleanupFailurePreservesPrimarySendError(t *testing.T) {
	sourcePath := filepath.Join(t.TempDir(), "payload.bin")
	if err := os.WriteFile(sourcePath, []byte("payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	sendErr := errors.New("send failed")
	device := &fakeUploadDevice{
		objectID:  73,
		sendErr:   sendErr,
		deleteErr: errors.New("delete failed"),
	}

	_, err := uploadToMTPDevice(device, nativeUploadRequest{
		storageID:  1,
		parentID:   math.MaxUint32,
		sourcePath: sourcePath,
		name:       "payload.bin",
		size:       7,
	})

	if !errors.Is(err, sendErr) {
		t.Fatalf("upload error = %v, want wrapped primary send error", err)
	}
	if len(device.deletedObjects) != 1 || device.deletedObjects[0] != 73 {
		t.Fatalf("deleted objects = %v, want [73]", device.deletedObjects)
	}
	if !strings.Contains(err.Error(), "cleanup failed") {
		t.Fatalf("upload error = %v, want cleanup diagnostic", err)
	}
	if device.objectInfoCalls != 1 || device.sendObjectCalls != 1 {
		t.Fatalf(
			"mutation calls = info:%d send:%d, want exactly one each",
			device.objectInfoCalls,
			device.sendObjectCalls,
		)
	}
}

func TestSetProgressCallbackNoop(t *testing.T) {
	Kalam_SetProgressCallback(0)
}

type fakeUploadDevice struct {
	objectID        uint32
	sendErr         error
	deleteErr       error
	afterObjectInfo func()
	duringSend      func(mtp.ProgressFunc) error
	sentObject      bool
	objectInfoCalls int
	sendObjectCalls int
	deletedObjects  []uint32
}

func (d *fakeUploadDevice) SendObjectInfo(
	_ uint32,
	_ uint32,
	_ *mtp.ObjectInfo,
) (uint32, uint32, uint32, error) {
	d.objectInfoCalls++
	if d.afterObjectInfo != nil {
		d.afterObjectInfo()
	}
	return 1, math.MaxUint32, d.objectID, nil
}

func (d *fakeUploadDevice) SendObject(
	_ io.Reader,
	_ int64,
	progress mtp.ProgressFunc,
) error {
	d.sentObject = true
	d.sendObjectCalls++
	if d.duringSend != nil {
		return d.duringSend(progress)
	}
	return d.sendErr
}

func (d *fakeUploadDevice) DeleteObject(objectID uint32) error {
	d.deletedObjects = append(d.deletedObjects, objectID)
	return d.deleteErr
}
