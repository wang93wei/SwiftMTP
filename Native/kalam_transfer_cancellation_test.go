package main

import (
	"errors"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

func TestTransferCancellationRegistryPreparePreCancelClaimAndTaskIDReuse(t *testing.T) {
	registry := newTransferCancellationRegistry()

	if err := registry.prepare("pre"); err != nil {
		t.Fatal(err)
	}
	if !registry.cancel("pre") {
		t.Fatal("cancel must apply to a prepared task")
	}
	pre, err := registry.claim("pre")
	if err != nil {
		t.Fatal(err)
	}
	if !pre.isCancelled() {
		t.Fatal("pre-cancelled operation must observe cancellation")
	}
	pre.finish()

	if registry.cancel("pre") {
		t.Fatal("late cancel after terminal cleanup must be a no-op")
	}
	if len(registry.states) != 0 {
		t.Fatalf("late cancel retained registry states: %d", len(registry.states))
	}
	if err := registry.prepare("pre"); err != nil {
		t.Fatal(err)
	}
	reused, err := registry.claim("pre")
	if err != nil {
		t.Fatal(err)
	}
	if reused.isCancelled() {
		t.Fatal("completed task ID must be reusable without stale cancellation")
	}
	reused.finish()

	if err := registry.prepare("mid"); err != nil {
		t.Fatal(err)
	}
	mid, err := registry.claim("mid")
	if err != nil {
		t.Fatal(err)
	}
	if !registry.cancel("mid") || !registry.cancel("mid") {
		t.Fatal("running task cancellation must remain idempotently applicable")
	}
	if !mid.isCancelled() {
		t.Fatal("running operation must observe idempotent cancellation")
	}
	mid.finish()

	if err := registry.prepare("mid"); err != nil {
		t.Fatal(err)
	}
	fresh, err := registry.claim("mid")
	if err != nil {
		t.Fatal(err)
	}
	if fresh.isCancelled() {
		t.Fatal("terminal cleanup must clear cancellation before task ID reuse")
	}
	fresh.finish()
}

func TestTransferCancellationRegistryTerminalCleanupIsIdempotent(t *testing.T) {
	registry := newTransferCancellationRegistry()
	if err := registry.prepare("terminal"); err != nil {
		t.Fatal(err)
	}
	operation, err := registry.claim("terminal")
	if err != nil {
		t.Fatal(err)
	}
	registry.cancel("terminal")

	operation.finish()
	operation.finish()

	registry.mu.Lock()
	_, retained := registry.states["terminal"]
	registry.mu.Unlock()
	if retained {
		t.Fatal("terminal cleanup must remove the registry entry")
	}
}

func TestTransferCancellationRegistryRejectsDuplicatePrepareAndClaim(t *testing.T) {
	registry := newTransferCancellationRegistry()
	if err := registry.prepare(""); err == nil {
		t.Fatal("empty task ID must be rejected")
	}
	if _, err := registry.claim(""); err == nil {
		t.Fatal("empty task ID claim must be rejected")
	}
	if err := registry.prepare("same"); err != nil {
		t.Fatal(err)
	}
	if err := registry.prepare("same"); err == nil || !strings.Contains(err.Error(), "already prepared") {
		t.Fatalf("duplicate prepare error = %v", err)
	}
	operation, err := registry.claim("same")
	if err != nil {
		t.Fatal(err)
	}
	defer operation.finish()
	if _, err := registry.claim("same"); err == nil || !strings.Contains(err.Error(), "already claimed") {
		t.Fatalf("duplicate claim error = %v", err)
	}
}

func TestTransferCancellationRegistryAbortPreparedTaskExactlyOnce(t *testing.T) {
	registry := newTransferCancellationRegistry()
	if err := registry.prepare("aborted"); err != nil {
		t.Fatal(err)
	}
	if !registry.abort("aborted") {
		t.Fatal("first abort must clean a prepared task")
	}
	if registry.abort("aborted") {
		t.Fatal("duplicate abort must be a no-op")
	}
	if registry.cancel("aborted") {
		t.Fatal("cancel after abort must be a no-op")
	}
	if _, err := registry.claim("aborted"); err == nil {
		t.Fatal("aborted task must not be claimable")
	}
	if len(registry.states) != 0 {
		t.Fatalf("abort retained registry states: %d", len(registry.states))
	}
}

func TestTransferCancellationRegistryFinishCancelRaceAlwaysCleansState(t *testing.T) {
	for iteration := 0; iteration < 1_000; iteration++ {
		registry := newTransferCancellationRegistry()
		if err := registry.prepare("race"); err != nil {
			t.Fatal(err)
		}
		operation, err := registry.claim("race")
		if err != nil {
			t.Fatal(err)
		}

		start := make(chan struct{})
		var workers sync.WaitGroup
		workers.Add(2)
		go func() {
			defer workers.Done()
			<-start
			operation.finish()
		}()
		go func() {
			defer workers.Done()
			<-start
			registry.cancel("race")
		}()
		close(start)
		workers.Wait()

		if registry.cancel("race") {
			t.Fatalf("iteration %d: terminal late cancel must be a no-op", iteration)
		}
		if len(registry.states) != 0 {
			t.Fatalf("iteration %d: terminal race retained state", iteration)
		}
	}
}

func TestTransferCancellationRegistryLegacyBeginSupportsActiveCancelAndReuse(t *testing.T) {
	registry := newTransferCancellationRegistry()
	operation, err := registry.begin("legacy")
	if err != nil {
		t.Fatal(err)
	}
	if !registry.cancel("legacy") || !operation.isCancelled() {
		t.Fatal("legacy active operation must observe cancellation")
	}
	operation.finish()

	reused, err := registry.begin("legacy")
	if err != nil {
		t.Fatal(err)
	}
	if reused.isCancelled() {
		t.Fatal("legacy task ID reuse must start from clean state")
	}
	reused.finish()
	if registry.cancel("legacy") {
		t.Fatal("legacy late cancellation must not recreate terminal state")
	}
}

func TestUploadObservesMidTransferCancellationAndCleansAllocatedObject(t *testing.T) {
	sourcePath := filepath.Join(t.TempDir(), "payload.bin")
	if err := os.WriteFile(sourcePath, []byte("payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	registry := newTransferCancellationRegistry()
	if err := registry.prepare("mid-upload"); err != nil {
		t.Fatal(err)
	}
	operation, err := registry.claim("mid-upload")
	if err != nil {
		t.Fatal(err)
	}
	defer operation.finish()

	device := &fakeUploadDevice{
		objectID: 91,
		duringSend: func(progress mtp.ProgressFunc) error {
			registry.cancel(operation.taskID)
			return progress(3)
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
	if len(device.deletedObjects) != 1 || device.deletedObjects[0] != 91 {
		t.Fatalf("deleted objects = %v, want [91]", device.deletedObjects)
	}
}

func TestUploadPreCancellationDoesNotMutateDevice(t *testing.T) {
	registry := newTransferCancellationRegistry()
	if err := registry.prepare("pre-upload"); err != nil {
		t.Fatal(err)
	}
	registry.cancel("pre-upload")
	operation, err := registry.claim("pre-upload")
	if err != nil {
		t.Fatal(err)
	}
	defer operation.finish()

	device := &fakeUploadDevice{objectID: 92}
	_, err = uploadToMTPDevice(device, nativeUploadRequest{
		storageID:  1,
		parentID:   math.MaxUint32,
		sourcePath: filepath.Join(t.TempDir(), "not-opened"),
		name:       "not-opened",
		operation:  operation,
	})

	var cancelled *cancelError
	if !errors.As(err, &cancelled) {
		t.Fatalf("upload error = %v, want cancelError", err)
	}
	if device.objectInfoCalls != 0 || device.sendObjectCalls != 0 || len(device.deletedObjects) != 0 {
		t.Fatalf(
			"pre-cancelled mutation calls = info:%d send:%d delete:%v",
			device.objectInfoCalls,
			device.sendObjectCalls,
			device.deletedObjects,
		)
	}
}
