package main

import (
	"sync"
	"sync/atomic"
	"time"
)

var bridgeShutdownFlag = newBridgeShutdownFlag()

func newBridgeShutdownFlag() *atomic.Bool {
	flag := &atomic.Bool{}
	flag.Store(true)
	return flag
}

type poolCleanupWorker struct {
	cancel   chan struct{}
	done     chan struct{}
	stopOnce sync.Once
}

func startPoolCleanupWorker(
	interval time.Duration,
	cleanup func(),
) *poolCleanupWorker {
	worker := &poolCleanupWorker{
		cancel: make(chan struct{}),
		done:   make(chan struct{}),
	}
	go func() {
		defer close(worker.done)
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				cleanup()
			case <-worker.cancel:
				return
			}
		}
	}()
	return worker
}

func (w *poolCleanupWorker) stopAndWait() {
	if w == nil {
		return
	}
	w.stopOnce.Do(func() {
		close(w.cancel)
	})
	<-w.done
}

type bridgeRuntimeSnapshot struct {
	initialized bool
	generation  uint64
	worker      *poolCleanupWorker
}

type bridgeRuntimeLifecycle struct {
	mu          sync.Mutex
	initialized bool
	generation  uint64
	worker      *poolCleanupWorker
}

func (r *bridgeRuntimeLifecycle) initialize() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.initialized {
		return
	}

	cfg = LoadConfig()
	nativeSessions.initialize()
	r.worker = startPoolCleanupWorker(cfg.Pool.CleanupTick, cleanupDevicePool)
	r.generation++
	r.initialized = true
	bridgeShutdownFlag.Store(false)
}

func (r *bridgeRuntimeLifecycle) cleanup() {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Reject new work before waiting for active worker/session/pool operations.
	bridgeShutdownFlag.Store(true)
	if r.worker != nil {
		r.worker.stopAndWait()
		r.worker = nil
	}
	nativeSessions.cleanup()

	// Legacy pooled operations hold deviceMu for their complete device use.
	deviceMu.Lock()
	disposeDevicePool()
	deviceMu.Unlock()
	r.initialized = false
}

func (r *bridgeRuntimeLifecycle) snapshot() bridgeRuntimeSnapshot {
	r.mu.Lock()
	defer r.mu.Unlock()
	return bridgeRuntimeSnapshot{
		initialized: r.initialized,
		generation:  r.generation,
		worker:      r.worker,
	}
}

var bridgeRuntime bridgeRuntimeLifecycle
