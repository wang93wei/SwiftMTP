package main

import (
	"fmt"
	"sync"
	"sync/atomic"
)

type transferCancellationState struct {
	cancelled atomic.Bool
	phase     transferCancellationPhase
}

type transferCancellationPhase uint8

const (
	transferCancellationPrepared transferCancellationPhase = iota + 1
	transferCancellationClaimed
)

type transferCancellationRegistry struct {
	mu     sync.Mutex
	states map[string]*transferCancellationState
}

type transferCancellationOperation struct {
	taskID   string
	registry *transferCancellationRegistry
	state    *transferCancellationState
	finishMu sync.Once
}

func newTransferCancellationRegistry() *transferCancellationRegistry {
	return &transferCancellationRegistry{
		states: make(map[string]*transferCancellationState),
	}
}

func (r *transferCancellationRegistry) prepare(taskID string) error {
	if taskID == "" {
		return fmt.Errorf("transfer task ID cannot be empty")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.states[taskID] != nil {
		return fmt.Errorf("transfer task %s is already prepared", taskID)
	}
	r.states[taskID] = &transferCancellationState{
		phase: transferCancellationPrepared,
	}
	return nil
}

func (r *transferCancellationRegistry) claim(
	taskID string,
) (*transferCancellationOperation, error) {
	if taskID == "" {
		return nil, fmt.Errorf("transfer task ID cannot be empty")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	state := r.states[taskID]
	if state == nil {
		return nil, fmt.Errorf("transfer task %s is not prepared", taskID)
	}
	switch state.phase {
	case transferCancellationPrepared:
		state.phase = transferCancellationClaimed
	case transferCancellationClaimed:
		return nil, fmt.Errorf("transfer task %s is already claimed", taskID)
	default:
		return nil, fmt.Errorf("transfer task %s has invalid lifecycle state", taskID)
	}
	return &transferCancellationOperation{
		taskID:   taskID,
		registry: r,
		state:    state,
	}, nil
}

// begin preserves the legacy transfer ABI: entering the transfer function
// atomically registers and claims a task. New adapters prepare before calling
// the session transfer ABI so cancellation can be observed before claim.
func (r *transferCancellationRegistry) begin(
	taskID string,
) (*transferCancellationOperation, error) {
	if taskID == "" {
		return nil, fmt.Errorf("transfer task ID cannot be empty")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.states[taskID] != nil {
		return nil, fmt.Errorf("transfer task %s is already prepared", taskID)
	}
	state := &transferCancellationState{phase: transferCancellationClaimed}
	r.states[taskID] = state
	return &transferCancellationOperation{
		taskID:   taskID,
		registry: r,
		state:    state,
	}, nil
}

func (r *transferCancellationRegistry) cancel(taskID string) bool {
	if taskID == "" {
		return false
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	state := r.states[taskID]
	if state == nil {
		return false
	}
	state.cancelled.Store(true)
	return true
}

func (r *transferCancellationRegistry) abort(taskID string) bool {
	if taskID == "" {
		return false
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	state := r.states[taskID]
	if state == nil || state.phase != transferCancellationPrepared {
		return false
	}
	delete(r.states, taskID)
	return true
}

func (o *transferCancellationOperation) isCancelled() bool {
	return o != nil && o.state.cancelled.Load()
}

func (o *transferCancellationOperation) finish() {
	if o == nil {
		return
	}
	o.finishMu.Do(func() {
		o.registry.mu.Lock()
		if o.registry.states[o.taskID] == o.state {
			delete(o.registry.states, o.taskID)
		}
		o.registry.mu.Unlock()
	})
}

var transferCancellations = newTransferCancellationRegistry()
