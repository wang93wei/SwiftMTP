package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Config holds all configuration settings as a single source of truth
type Config struct {
	// Timeout settings (milliseconds)
	Timeouts struct {
		QuickScan         time.Duration
		NormalOperation   time.Duration
		LargeFileDownload time.Duration
	}

	// Retry settings
	Retries struct {
		QuickScan       int
		NormalOperation int
		Download        int
	}

	// Backoff settings
	Backoff struct {
		QuickScanDuration time.Duration
		MaxDuration       time.Duration
	}

	// Security settings
	Security struct {
		MaxPathLength       int
		MaxCStringSize      int
		MaxFolderNameLength int
	}

	// Pool settings
	Pool struct {
		MaxSize     int
		EntryTTL    time.Duration
		CleanupTick time.Duration
	}

	// File size limits
	FileSize struct {
		LargeThreshold int64
		MaxSize        int64
	}

	// Download settings
	Download struct {
		DefaultDir string
	}

	// Retry settings
	Retry struct {
		MaxConsecutiveFailures int
	}
}

// DefaultConfig returns the default configuration
func DefaultConfig() *Config {
	cfg := &Config{}

	// Timeout settings
	cfg.Timeouts.QuickScan = 5 * time.Second
	cfg.Timeouts.NormalOperation = 45 * time.Second
	cfg.Timeouts.LargeFileDownload = 5 * time.Minute

	// Retry settings
	cfg.Retries.QuickScan = 1
	cfg.Retries.NormalOperation = 3
	cfg.Retries.Download = 3

	// Backoff settings
	cfg.Backoff.QuickScanDuration = 200 * time.Millisecond
	cfg.Backoff.MaxDuration = 2 * time.Second

	// Security settings
	cfg.Security.MaxPathLength = 4096
	cfg.Security.MaxCStringSize = 1024 * 1024
	cfg.Security.MaxFolderNameLength = 255

	// Pool settings
	cfg.Pool.MaxSize = 3
	cfg.Pool.EntryTTL = 2 * time.Minute
	cfg.Pool.CleanupTick = 1 * time.Minute

	// File size limits
	cfg.FileSize.LargeThreshold = 100 * 1024 * 1024 // 100MB
	cfg.FileSize.MaxSize = 10 * 1024 * 1024 * 1024  // 10GB

	// Download settings
	cfg.Download.DefaultDir = getDefaultDownloadDir()

	// Retry settings
	cfg.Retry.MaxConsecutiveFailures = 3

	return cfg
}

// LoadConfig loads configuration from environment variables
func LoadConfig() *Config {
	cfg := DefaultConfig()

	// Override with environment variables if present
	if dir := os.Getenv("DOWNLOAD_DIR"); dir != "" {
		cfg.Download.DefaultDir = dir
	}

	return cfg
}

// Global configuration instance
var cfg = LoadConfig()

// getDefaultDownloadDir returns the default download directory for the current user
func getDefaultDownloadDir() string {
	// Try from environment variable first
	if dir := os.Getenv("DOWNLOAD_DIR"); dir != "" {
		return dir
	}

	// Get user's home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		fmt.Printf("getDefaultDownloadDir: Failed to get home directory: %v\n", err)
		return "/tmp"
	}

	// Return Downloads directory
	return filepath.Join(homeDir, "Downloads")
}

// MARK: - Path Security Validation

// validateAndCleanPath validates and cleans the path to prevent path traversal attacks
func validateAndCleanPath(path string, allowedBaseDir string) (string, error) {
	// 1. Validate path length
	if len(path) == 0 {
		return "", fmt.Errorf("path cannot be empty")
	}

	if len(path) > cfg.Security.MaxPathLength {
		return "", fmt.Errorf("path exceeds maximum length of %d", cfg.Security.MaxPathLength)
	}

	// 2. Check for dangerous characters
	dangerousChars := []string{"\x00", "\n", "\r", "\t"}
	for _, char := range dangerousChars {
		if strings.Contains(path, char) {
			return "", fmt.Errorf("path contains invalid character")
		}
	}

	// 3. Clean the path
	cleanPath := filepath.Clean(path)

	// 4. Resolve to absolute path
	absPath, err := filepath.Abs(cleanPath)
	if err != nil {
		return "", fmt.Errorf("failed to get absolute path: %w", err)
	}

	// 5. Check if path is within allowed directory
	allowedAbs, err := filepath.Abs(allowedBaseDir)
	if err != nil {
		return "", fmt.Errorf("failed to get allowed base dir: %w", err)
	}

	relPath, err := filepath.Rel(allowedAbs, absPath)
	if err != nil {
		return "", fmt.Errorf("path is not relative to allowed dir: %w", err)
	}

	// 6. Check if path contains ".."
	if strings.Contains(relPath, "..") {
		return "", fmt.Errorf("path contains parent directory references")
	}

	// 7. Check if path starts with ".."
	if strings.HasPrefix(relPath, "..") {
		return "", fmt.Errorf("path starts with parent directory reference")
	}

	return absPath, nil
}

// MTP object formats
const (
	// Folder format
	ObjectFormatFolder = 0x3001
	// Generic file format
	ObjectFormatGenericFile = 0x3000
)

// Helper function
func containsIgnoreCase(s, substr string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(substr))
}
