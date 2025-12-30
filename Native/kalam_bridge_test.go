package main

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

// MARK: - Constants Tests

func TestConstants(t *testing.T) {
	// Test timeout constants
	if QuickScanTimeout != 5000 {
		t.Errorf("QuickScanTimeout = %d, want 5000", QuickScanTimeout)
	}
	if NormalOperationTimeout != 45000 {
		t.Errorf("NormalOperationTimeout = %d, want 45000", NormalOperationTimeout)
	}
	if LargeFileDownloadTimeout != 300000 {
		t.Errorf("LargeFileDownloadTimeout = %d, want 300000", LargeFileDownloadTimeout)
	}

	// Test retry constants
	if QuickScanMaxRetries != 1 {
		t.Errorf("QuickScanMaxRetries = %d, want 1", QuickScanMaxRetries)
	}
	if NormalOperationMaxRetries != 3 {
		t.Errorf("NormalOperationMaxRetries = %d, want 3", NormalOperationMaxRetries)
	}
	if DownloadMaxRetries != 3 {
		t.Errorf("DownloadMaxRetries = %d, want 3", DownloadMaxRetries)
	}

	// Test backoff constants
	if QuickScanBackoffDuration != 200 {
		t.Errorf("QuickScanBackoffDuration = %d, want 200", QuickScanBackoffDuration)
	}
	if MaxBackoffDuration != 2000 {
		t.Errorf("MaxBackoffDuration = %d, want 2000", MaxBackoffDuration)
	}
	if MaxConsecutiveFailures != 3 {
		t.Errorf("MaxConsecutiveFailures = %d, want 3", MaxConsecutiveFailures)
	}

	// Test file size constants
	if LargeFileThreshold != 100*1024*1024 {
		t.Errorf("LargeFileThreshold = %d, want %d", LargeFileThreshold, 100*1024*1024)
	}
	if MaxFileSize != 10*1024*1024*1024 {
		t.Errorf("MaxFileSize = %d, want %d", MaxFileSize, 10*1024*1024*1024)
	}

	// Test MTP object format constants
	if ObjectFormatFolder != 0x3001 {
		t.Errorf("ObjectFormatFolder = %x, want 0x3001", ObjectFormatFolder)
	}
	if ObjectFormatGenericFile != 0x3000 {
		t.Errorf("ObjectFormatGenericFile = %x, want 0x3000", ObjectFormatGenericFile)
	}
}

// MARK: - Mutex Tests

func testMutexLock(t *testing.T) {
	// Test that mutexes can be locked and unlocked
	deviceMu.Lock()
	deviceMu.Unlock()

	cancelMu.Lock()
	cancelMu.Unlock()
}

func TestConcurrentMutexAccess(t *testing.T) {
	done := make(chan bool)

	// Test concurrent access to deviceMu
	for i := 0; i < 10; i++ {
		go func() {
			deviceMu.Lock()
			time.Sleep(1 * time.Millisecond)
			deviceMu.Unlock()
			done <- true
		}()
	}

	// Test concurrent access to cancelMu
	for i := 0; i < 10; i++ {
		go func() {
			cancelMu.Lock()
			time.Sleep(1 * time.Millisecond)
			cancelMu.Unlock()
			done <- true
		}()
	}

	// Wait for all goroutines to complete
	for i := 0; i < 20; i++ {
		<-done
	}
}

// MARK: - Cancelled Tasks Tests

func TestCancelledTasksMap(t *testing.T) {
	// Test that cancelledTasks map can be used
	taskID := "test-task-123"

	cancelMu.Lock()
	cancelledTasks[taskID] = true
	cancelMu.Unlock()

	cancelMu.Lock()
	_, exists := cancelledTasks[taskID]
	cancelMu.Unlock()

	if !exists {
		t.Errorf("Task %s should exist in cancelledTasks", taskID)
	}

	// Clean up
	cancelMu.Lock()
	delete(cancelledTasks, taskID)
	cancelMu.Unlock()
}

func TestCancelledTasksConcurrentAccess(t *testing.T) {
	done := make(chan bool)

	// Test concurrent access to cancelledTasks
	for i := 0; i < 100; i++ {
		go func(id int) {
			taskID := "task-" + string(rune(id))
			cancelMu.Lock()
			cancelledTasks[taskID] = true
			cancelMu.Unlock()
			done <- true
		}(i)
	}

	// Wait for all goroutines to complete
	for i := 0; i < 100; i++ {
		<-done
	}

	// Clean up
	cancelMu.Lock()
	cancelledTasks = make(map[string]bool)
	cancelMu.Unlock()
}

// MARK: - JSON Encoding/Decoding Tests

func TestJSONEncoding(t *testing.T) {
	// Test that JSON encoding works
	type TestStruct struct {
		Name  string `json:"name"`
		Value int    `json:"value"`
	}

	test := TestStruct{Name: "test", Value: 42}
	data, err := json.Marshal(test)
	if err != nil {
		t.Errorf("JSON encoding failed: %v", err)
	}

	if string(data) != `{"name":"test","value":42}` {
		t.Errorf("JSON encoding result = %s, want %s", string(data), `{"name":"test","value":42}`)
	}
}

func TestJSONDecoding(t *testing.T) {
	// Test that JSON decoding works
	type TestStruct struct {
		Name  string `json:"name"`
		Value int    `json:"value"`
	}

	jsonStr := `{"name":"test","value":42}`
	var test TestStruct
	err := json.Unmarshal([]byte(jsonStr), &test)
	if err != nil {
		t.Errorf("JSON decoding failed: %v", err)
	}

	if test.Name != "test" {
		t.Errorf("Name = %s, want test", test.Name)
	}
	if test.Value != 42 {
		t.Errorf("Value = %d, want 42", test.Value)
	}
}

// MARK: - Backoff Calculation Tests

func calculateBackoff(failures int) time.Duration {
	backoff := QuickScanBackoffDuration * (1 << uint(failures-1))
	if backoff > MaxBackoffDuration {
		backoff = MaxBackoffDuration
	}
	return time.Duration(backoff) * time.Millisecond
}

func TestBackoffCalculation(t *testing.T) {
	tests := []struct {
		name          string
		failures      int
		expectedDelay time.Duration
	}{
		{"First failure", 1, 200 * time.Millisecond},
		{"Second failure", 2, 400 * time.Millisecond},
		{"Third failure", 3, 800 * time.Millisecond},
		{"Fourth failure", 4, 1600 * time.Millisecond},
		{"Fifth failure", 5, 2000 * time.Millisecond}, // Capped at MaxBackoffDuration
		{"Tenth failure", 10, 2000 * time.Millisecond}, // Capped at MaxBackoffDuration
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			delay := calculateBackoff(tt.failures)
			if delay != tt.expectedDelay {
				t.Errorf("Backoff for %d failures = %v, want %v", tt.failures, delay, tt.expectedDelay)
			}
		})
	}
}

// MARK: - File Size Validation Tests

func TestFileSizeValidation(t *testing.T) {
	tests := []struct {
		name     string
		size     uint64
		valid    bool
		reason   string
	}{
		{"Zero size", 0, true, "Zero size should be valid"},
		{"Small file", 1024, true, "Small file should be valid"},
		{"Medium file", 10 * 1024 * 1024, true, "Medium file should be valid"},
		{"Large file threshold", LargeFileThreshold, true, "Large file threshold should be valid"},
		{"Below max size", MaxFileSize - 1, true, "Below max size should be valid"},
		{"Exactly max size", MaxFileSize, true, "Exactly max size should be valid"},
		{"Above max size", MaxFileSize + 1, false, "Above max size should be invalid"},
		{"Very large file", uint64(100) * 1024 * 1024 * 1024, false, "Very large file should be invalid"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			valid := tt.size <= MaxFileSize
			if valid != tt.valid {
				t.Errorf("%s: valid = %v, want %v (%s)", tt.name, valid, tt.valid, tt.reason)
			}
		})
	}
}

// MARK: - Timeout Calculation Tests

func TestTimeoutSelection(t *testing.T) {
	tests := []struct {
		name          string
		fileSize      uint64
		expectedTimeout int
	}{
		{"Small file", 1024, NormalOperationTimeout},
		{"Large file threshold", LargeFileThreshold, LargeFileDownloadTimeout},
		{"Very large file", 5 * 1024 * 1024 * 1024, LargeFileDownloadTimeout},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var timeout int
			if tt.fileSize >= LargeFileThreshold {
				timeout = LargeFileDownloadTimeout
			} else {
				timeout = NormalOperationTimeout
			}

			if timeout != tt.expectedTimeout {
				t.Errorf("%s: timeout = %d, want %d", tt.name, timeout, tt.expectedTimeout)
			}
		})
	}
}

// MARK: - Retry Count Tests

func TestRetryCountValidation(t *testing.T) {
	tests := []struct {
		name       string
		operation  string
		maxRetries int
	}{
		{"Quick scan", "quickScan", QuickScanMaxRetries},
		{"Normal operation", "normalOperation", NormalOperationMaxRetries},
		{"Download", "download", DownloadMaxRetries},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.maxRetries <= 0 {
				t.Errorf("%s: maxRetries = %d, want > 0", tt.name, tt.maxRetries)
			}
		})
	}
}

// MARK: - MTP Object Format Tests

func TestMTPObjectFormat(t *testing.T) {
	tests := []struct {
		name     string
		format   uint32
		expected string
	}{
		{"Folder format", ObjectFormatFolder, "0x3001"},
		{"Generic file format", ObjectFormatGenericFile, "0x3000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			formatStr := fmt.Sprintf("0x%x", tt.format)
			if formatStr != tt.expected {
				t.Errorf("%s: format = %s, want %s", tt.name, formatStr, tt.expected)
			}
		})
	}
}

// MARK: - Concurrency Safety Tests

func TestConcurrentStateAccess(t *testing.T) {
	done := make(chan bool)
	iterations := 100

	// Test concurrent access to all shared state
	for i := 0; i < iterations; i++ {
		go func(id int) {
			// Access deviceMu
			deviceMu.Lock()
			time.Sleep(1 * time.Millisecond)
			deviceMu.Unlock()

			// Access cancelMu
			cancelMu.Lock()
			taskID := fmt.Sprintf("task-%d", id)
			cancelledTasks[taskID] = true
			cancelMu.Unlock()

			done <- true
		}(i)
	}

	// Wait for all goroutines to complete
	for i := 0; i < iterations; i++ {
		<-done
	}

	// Clean up
	cancelMu.Lock()
	cancelledTasks = make(map[string]bool)
	cancelMu.Unlock()
}

// MARK: - Edge Cases Tests

func TestZeroValues(t *testing.T) {
	// Test that zero values are handled correctly
	if QuickScanTimeout == 0 {
		t.Error("QuickScanTimeout should not be zero")
	}
	if NormalOperationTimeout == 0 {
		t.Error("NormalOperationTimeout should not be zero")
	}
	if LargeFileDownloadTimeout == 0 {
		t.Error("LargeFileDownloadTimeout should not be zero")
	}
	if MaxFileSize == 0 {
		t.Error("MaxFileSize should not be zero")
	}
}

func TestMaximumValues(t *testing.T) {
	// Test that maximum values are reasonable
	if QuickScanTimeout > 10000 {
		t.Errorf("QuickScanTimeout = %d, seems too large", QuickScanTimeout)
	}
	if NormalOperationTimeout > 120000 {
		t.Errorf("NormalOperationTimeout = %d, seems too large", NormalOperationTimeout)
	}
	if LargeFileDownloadTimeout > 600000 {
		t.Errorf("LargeFileDownloadTimeout = %d, seems too large", LargeFileDownloadTimeout)
	}
	if MaxFileSize > 100*1024*1024*1024 {
		t.Errorf("MaxFileSize = %d, seems too large (>100GB)", MaxFileSize)
	}
}

// MARK: - Benchmark Tests

func BenchmarkMutexLock(b *testing.B) {
	for i := 0; i < b.N; i++ {
		deviceMu.Lock()
		deviceMu.Unlock()
	}
}

func BenchmarkCancelledTasksAccess(b *testing.B) {
	taskID := "benchmark-task"
	cancelMu.Lock()
	cancelledTasks[taskID] = true
	cancelMu.Unlock()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		cancelMu.Lock()
		_ = cancelledTasks[taskID]
		cancelMu.Unlock()
	}

	// Clean up
	cancelMu.Lock()
	delete(cancelledTasks, taskID)
	cancelMu.Unlock()
}

func BenchmarkJSONEncoding(b *testing.B) {
	type TestStruct struct {
		Name  string `json:"name"`
		Value int    `json:"value"`
	}
	test := TestStruct{Name: "benchmark", Value: 42}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = json.Marshal(test)
	}
}

func BenchmarkJSONDecoding(b *testing.B) {
	type TestStruct struct {
		Name  string `json:"name"`
		Value int    `json:"value"`
	}
	jsonStr := `{"name":"benchmark","value":42}`

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		var test TestStruct
		_ = json.Unmarshal([]byte(jsonStr), &test)
	}
}

func BenchmarkBackoffCalculation(b *testing.B) {
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = calculateBackoff(i % 10)
	}
}