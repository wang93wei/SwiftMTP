package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

const uploadCompressedSizeSentinel = ^uint32(0)
const maxMTPFilenameUTF16Units = 254

type uploadSourcePolicy struct {
	maxPathLength int
	maxNameLength int
	maxFileSize   int64
}

type uploadSource struct {
	file           *os.File
	name           string
	size           int64
	compressedSize uint32
	modification   int64
}

func configuredUploadSourcePolicy() uploadSourcePolicy {
	return uploadSourcePolicy{
		maxPathLength: cfg.Security.MaxPathLength,
		maxNameLength: cfg.Security.MaxFolderNameLength,
		maxFileSize:   cfg.FileSize.MaxSize,
	}
}

func inspectUploadSource(path string, maxFileSize int64) (*uploadSource, error) {
	policy := configuredUploadSourcePolicy()
	policy.maxFileSize = maxFileSize

	info, err := os.Lstat(path)
	if err != nil {
		return nil, fmt.Errorf("inspect upload source: %w", err)
	}
	source, err := validateUploadSource(path, info, policy)
	if err != nil {
		return nil, err
	}

	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open upload source: %w", err)
	}
	openedInfo, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, fmt.Errorf("inspect opened upload source: %w", err)
	}
	if !openedInfo.Mode().IsRegular() || !os.SameFile(info, openedInfo) || openedInfo.Size() != source.size {
		file.Close()
		return nil, fmt.Errorf("upload source changed during inspection")
	}

	source.file = file
	return source, nil
}

func validateUploadSource(
	path string,
	info os.FileInfo,
	policy uploadSourcePolicy,
) (*uploadSource, error) {
	if path == "" {
		return nil, fmt.Errorf("upload source path cannot be empty")
	}
	if policy.maxPathLength <= 0 {
		return nil, fmt.Errorf("invalid upload path length policy")
	}
	if len(path) > policy.maxPathLength {
		return nil, fmt.Errorf("upload source path exceeds maximum length of %d", policy.maxPathLength)
	}
	if !utf8.ValidString(path) {
		return nil, fmt.Errorf("upload source path is not valid UTF-8")
	}
	if !filepath.IsAbs(path) {
		return nil, fmt.Errorf("upload source path must be absolute")
	}
	if filepath.Clean(path) != path {
		return nil, fmt.Errorf("upload source path must be standardized")
	}
	if info == nil {
		return nil, fmt.Errorf("upload source metadata is missing")
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("upload source must not be a symbolic link")
	}
	if info.IsDir() {
		return nil, fmt.Errorf("upload source must not be a directory")
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("upload source must be a regular file")
	}

	name := filepath.Base(path)
	if name == "." || name == string(filepath.Separator) || name == "" {
		return nil, fmt.Errorf("upload source filename is invalid")
	}
	if strings.IndexFunc(name, func(r rune) bool { return r < 0x20 || r == 0x7f }) >= 0 {
		return nil, fmt.Errorf("upload source filename contains control characters")
	}
	nameLimit := policy.maxNameLength
	if nameLimit <= 0 || nameLimit > maxMTPFilenameUTF16Units {
		nameLimit = maxMTPFilenameUTF16Units
	}
	if len(utf16.Encode([]rune(name))) > nameLimit {
		return nil, fmt.Errorf("upload source filename exceeds maximum length of %d UTF-16 code units", nameLimit)
	}

	size := info.Size()
	if size < 0 {
		return nil, fmt.Errorf("upload source size cannot be negative")
	}
	if policy.maxFileSize < 0 {
		return nil, fmt.Errorf("invalid upload file size policy")
	}
	if size > policy.maxFileSize {
		return nil, fmt.Errorf("upload source exceeds maximum size of %d bytes", policy.maxFileSize)
	}

	compressedSize := uploadCompressedSizeSentinel
	if size < int64(uploadCompressedSizeSentinel) {
		compressedSize = uint32(size)
	}
	return &uploadSource{
		name:           name,
		size:           size,
		compressedSize: compressedSize,
		modification:   info.ModTime().Unix(),
	}, nil
}
