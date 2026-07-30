package main

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestInspectUploadSourceAcceptsRegularAndEmptyFiles(t *testing.T) {
	for _, fixture := range []struct {
		name    string
		content []byte
	}{
		{name: "regular", content: []byte("payload")},
		{name: "empty", content: nil},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "合法..文件.txt")
			if err := os.WriteFile(path, fixture.content, 0o600); err != nil {
				t.Fatal(err)
			}

			source, err := inspectUploadSource(path, int64(math.MaxUint32)+1)
			if err != nil {
				t.Fatalf("inspectUploadSource() error = %v", err)
			}
			defer source.file.Close()
			if source.name != "合法..文件.txt" {
				t.Fatalf("name = %q", source.name)
			}
			if source.size != int64(len(fixture.content)) {
				t.Fatalf("size = %d, want %d", source.size, len(fixture.content))
			}
		})
	}
}

func TestInspectUploadSourceRejectsUnsupportedFilesystemEntries(t *testing.T) {
	root := t.TempDir()
	missing := filepath.Join(root, "missing")
	directory := filepath.Join(root, "directory")
	if err := os.Mkdir(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	regular := filepath.Join(root, "regular")
	if err := os.WriteFile(regular, []byte("payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	symlink := filepath.Join(root, "symlink")
	if err := os.Symlink(regular, symlink); err != nil {
		t.Fatal(err)
	}
	fifo := filepath.Join(root, "fifo")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}

	for _, path := range []string{missing, directory, symlink, fifo} {
		t.Run(filepath.Base(path), func(t *testing.T) {
			if source, err := inspectUploadSource(path, math.MaxInt64); err == nil {
				source.file.Close()
				t.Fatalf("inspectUploadSource(%q) unexpectedly succeeded", path)
			}
		})
	}
}

func TestValidateUploadSourcePathPolicy(t *testing.T) {
	info := uploadFileInfo{name: "ignored", size: 1, mode: 0o600, modTime: time.Unix(1, 0)}
	absolute := filepath.Join(t.TempDir(), "合法..文件.txt")

	for _, test := range []struct {
		name      string
		path      string
		maxLength int
		wantError bool
	}{
		{name: "absolute standardized Unicode path with dot-dot basename", path: absolute, maxLength: 4096},
		{name: "relative path", path: "relative.txt", maxLength: 4096, wantError: true},
		{name: "non-standard path", path: filepath.Dir(absolute) + "/folder/../" + filepath.Base(absolute), maxLength: 4096, wantError: true},
		{name: "path at configured maximum", path: absolute, maxLength: len(absolute)},
		{name: "path above configured maximum", path: absolute, maxLength: len(absolute) - 1, wantError: true},
		{name: "invalid configured maximum", path: absolute, maxLength: 0, wantError: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, err := validateUploadSource(test.path, info, uploadSourcePolicy{
				maxPathLength: test.maxLength,
				maxFileSize:   math.MaxInt64,
			})
			if (err != nil) != test.wantError {
				t.Fatalf("validateUploadSource() error = %v, wantError = %v", err, test.wantError)
			}
		})
	}
}

func TestConfiguredUploadSourcePolicyUsesRuntimeLimits(t *testing.T) {
	policy := configuredUploadSourcePolicy()
	if policy.maxPathLength != cfg.Security.MaxPathLength {
		t.Fatalf("maxPathLength = %d, want %d", policy.maxPathLength, cfg.Security.MaxPathLength)
	}
	if policy.maxNameLength != cfg.Security.MaxFolderNameLength {
		t.Fatalf("maxNameLength = %d, want %d", policy.maxNameLength, cfg.Security.MaxFolderNameLength)
	}
	if policy.maxFileSize != cfg.FileSize.MaxSize {
		t.Fatalf("maxFileSize = %d, want %d", policy.maxFileSize, cfg.FileSize.MaxSize)
	}
}

func TestValidateUploadSourceUsesMTPUTF16FilenameLimit(t *testing.T) {
	info := uploadFileInfo{name: "ignored", size: 1, mode: 0o600, modTime: time.Unix(1, 0)}
	policy := uploadSourcePolicy{maxPathLength: 4096, maxNameLength: 255, maxFileSize: 1}

	if _, err := validateUploadSource("/tmp/"+strings.Repeat("😀", 127), info, policy); err != nil {
		t.Fatalf("254 UTF-16 code units should be accepted: %v", err)
	}
	if _, err := validateUploadSource("/tmp/"+strings.Repeat("😀", 128), info, policy); err == nil {
		t.Fatal("256 UTF-16 code units must be rejected")
	}
}

func TestValidateUploadSourceSizePolicyAndWireBoundary(t *testing.T) {
	for _, test := range []struct {
		name           string
		size           int64
		maxSize        int64
		wantCompressed uint32
		wantError      bool
	}{
		{name: "configured maximum accepted", size: 10, maxSize: 10, wantCompressed: 10},
		{name: "configured maximum exceeded", size: 11, maxSize: 10, wantError: true},
		{name: "largest exact UInt32 size", size: int64(math.MaxUint32) - 1, maxSize: math.MaxInt64, wantCompressed: math.MaxUint32 - 1},
		{name: "UInt32 max uses sentinel", size: int64(math.MaxUint32), maxSize: math.MaxInt64, wantCompressed: math.MaxUint32},
		{name: "above UInt32 max uses sentinel without truncation", size: int64(math.MaxUint32) + 1, maxSize: math.MaxInt64, wantCompressed: math.MaxUint32},
	} {
		t.Run(test.name, func(t *testing.T) {
			info := uploadFileInfo{name: "file", size: test.size, mode: 0o600, modTime: time.Unix(1, 0)}
			source, err := validateUploadSource("/tmp/file", info, uploadSourcePolicy{
				maxPathLength: 4096,
				maxFileSize:   test.maxSize,
			})
			if (err != nil) != test.wantError {
				t.Fatalf("validateUploadSource() error = %v, wantError = %v", err, test.wantError)
			}
			if err == nil && source.compressedSize != test.wantCompressed {
				t.Fatalf("compressedSize = %#x, want %#x", source.compressedSize, test.wantCompressed)
			}
		})
	}
}

type uploadFileInfo struct {
	name    string
	size    int64
	mode    os.FileMode
	modTime time.Time
}

func (i uploadFileInfo) Name() string       { return i.name }
func (i uploadFileInfo) Size() int64        { return i.size }
func (i uploadFileInfo) Mode() os.FileMode  { return i.mode }
func (i uploadFileInfo) ModTime() time.Time { return i.modTime }
func (i uploadFileInfo) IsDir() bool        { return i.mode.IsDir() }
func (i uploadFileInfo) Sys() any           { return nil }
