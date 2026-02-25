package main

import (
	"strings"
	"testing"
	"time"
)

func TestSafeCStringRejectsOversizeInput(t *testing.T) {
	tooLarge := strings.Repeat("a", cfg.Security.MaxCStringSize+1)
	if got := safeCString(tooLarge); got != nil {
		t.Fatalf("expected nil for oversize C string")
	}
}

func TestSafeCStringAndFreeString(t *testing.T) {
	ptr := safeCString("hello")
	if ptr == nil {
		t.Fatalf("expected non-nil C string")
	}
	Kalam_FreeString(ptr)
	Kalam_FreeString(nil)
}

func TestCleanupLeakedStringsRemovesExpiredEntry(t *testing.T) {
	ptr := safeCString("leak")
	if ptr == nil {
		t.Fatalf("expected non-nil C string")
	}

	stringMu.Lock()
	allocatedStrings[ptr] = time.Now().Add(-10 * time.Minute)
	stringMu.Unlock()

	cleanupLeakedStrings()

	stringMu.Lock()
	_, exists := allocatedStrings[ptr]
	stringMu.Unlock()
	if exists {
		t.Fatalf("expected leaked string to be removed")
	}
}

func TestCleanupEntrypointsDoNotPanic(t *testing.T) {
	Kalam_Init()
	Kalam_CleanupLeakedStrings()
}
