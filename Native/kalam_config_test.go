package main

import (
	"path/filepath"
	"testing"
)

func TestContainsIgnoreCase(t *testing.T) {
	if !containsIgnoreCase("Samsung Galaxy", "samsung") {
		t.Fatalf("expected case-insensitive match")
	}
	if containsIgnoreCase("Pixel", "iphone") {
		t.Fatalf("unexpected match")
	}
}

func TestValidateAndCleanPath(t *testing.T) {
	baseDir := t.TempDir()
	validPath := filepath.Join(baseDir, "sub", "file.txt")

	got, err := validateAndCleanPath(validPath, baseDir)
	if err != nil {
		t.Fatalf("validateAndCleanPath(valid) returned error: %v", err)
	}
	expected, err := filepath.Abs(validPath)
	if err != nil {
		t.Fatalf("filepath.Abs failed: %v", err)
	}
	if got != expected {
		t.Fatalf("validateAndCleanPath(valid) = %q, want %q", got, expected)
	}

	if _, err := validateAndCleanPath(filepath.Join(baseDir, "..", "etc", "passwd"), baseDir); err == nil {
		t.Fatalf("expected traversal path to be rejected")
	}

	if _, err := validateAndCleanPath("bad\npath", baseDir); err == nil {
		t.Fatalf("expected dangerous characters to be rejected")
	}

	if _, err := validateAndCleanPath("", baseDir); err == nil {
		t.Fatalf("expected empty path to be rejected")
	}
}
