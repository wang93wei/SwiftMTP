package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
)

var (
	errAmbiguousLegacySession = errors.New("legacy transfer requires exactly one active exact session")
	errBridgeShuttingDown     = errors.New("bridge is shutting down")
	errNativeDisconnected     = errors.New("native device disconnected")
	errStaleSessionToken      = errors.New("stale native session token")
	errUnknownSessionToken    = errors.New("unknown native session token")
)

type nativeSessionEntry struct {
	mu       sync.Mutex
	session  *nativeDeviceSession
	closed   bool
	disposed bool
}

func (e *nativeSessionEntry) disposeLocked() {
	if e.disposed {
		return
	}
	e.disposed = true
	e.closed = true
	if e.session != nil && e.session.dispose != nil {
		e.session.dispose()
	}
}

type nativeSessionOpener func(usbDeviceLocator) (*nativeDeviceSession, error)

type nativeSessionRegistry struct {
	openMu       sync.Mutex
	mu           sync.Mutex
	opener       nativeSessionOpener
	sessions     map[string]*nativeSessionEntry
	closedTokens map[string]struct{}
	shuttingDown bool
}

func newNativeSessionRegistry(opener nativeSessionOpener) *nativeSessionRegistry {
	return &nativeSessionRegistry{
		opener:       opener,
		sessions:     make(map[string]*nativeSessionEntry),
		closedTokens: make(map[string]struct{}),
	}
}

func newInactiveNativeSessionRegistry(opener nativeSessionOpener) *nativeSessionRegistry {
	registry := newNativeSessionRegistry(opener)
	registry.shuttingDown = true
	return registry
}

func (r *nativeSessionRegistry) initialize() {
	r.openMu.Lock()
	defer r.openMu.Unlock()
	r.mu.Lock()
	r.shuttingDown = false
	r.mu.Unlock()
}

func (r *nativeSessionRegistry) open(locator usbDeviceLocator) (string, error) {
	r.openMu.Lock()
	defer r.openMu.Unlock()
	if _, err := locator.canonicalID(); err != nil {
		return "", err
	}
	r.mu.Lock()
	if r.shuttingDown {
		r.mu.Unlock()
		return "", errBridgeShuttingDown
	}
	for _, entry := range r.sessions {
		if entry.session != nil && sameUSBLocator(entry.session.locator, locator) {
			r.mu.Unlock()
			return "", fmt.Errorf("exact MTP device already has an active session")
		}
	}
	r.mu.Unlock()

	session, err := r.opener(locator)
	if err != nil {
		return "", err
	}
	if session == nil {
		return "", fmt.Errorf("exact MTP opener returned no session")
	}
	token, err := makeNativeSessionToken()
	if err != nil {
		session.dispose()
		return "", err
	}
	entry := &nativeSessionEntry{session: session}

	r.mu.Lock()
	if r.shuttingDown {
		r.mu.Unlock()
		entry.mu.Lock()
		entry.disposeLocked()
		entry.mu.Unlock()
		return "", errBridgeShuttingDown
	}
	r.sessions[token] = entry
	r.mu.Unlock()
	return token, nil
}

func (r *nativeSessionRegistry) inspectLocator(
	locator usbDeviceLocator,
	operation func(*nativeDeviceSession) error,
) error {
	r.openMu.Lock()
	defer r.openMu.Unlock()
	r.mu.Lock()
	if r.shuttingDown {
		r.mu.Unlock()
		return errBridgeShuttingDown
	}
	var activeToken string
	for token, entry := range r.sessions {
		if entry.session != nil && sameUSBLocator(entry.session.locator, locator) {
			if activeToken != "" {
				r.mu.Unlock()
				return fmt.Errorf("multiple active sessions share one physical locator")
			}
			activeToken = token
		}
	}
	r.mu.Unlock()
	if activeToken != "" {
		return r.withSession(activeToken, operation)
	}

	session, err := r.opener(locator)
	if err != nil {
		return err
	}
	defer session.dispose()
	return operation(session)
}

func makeNativeSessionToken() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate native session token: %w", err)
	}
	return hex.EncodeToString(bytes), nil
}

func (r *nativeSessionRegistry) withSession(
	token string,
	operation func(*nativeDeviceSession) error,
) error {
	r.mu.Lock()
	entry := r.sessions[token]
	_, wasClosed := r.closedTokens[token]
	shuttingDown := r.shuttingDown
	r.mu.Unlock()
	if shuttingDown {
		return errBridgeShuttingDown
	}
	if entry == nil {
		if wasClosed {
			return errStaleSessionToken
		}
		return errUnknownSessionToken
	}

	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.closed {
		return errStaleSessionToken
	}
	err := operation(entry.session)
	if isDisconnectedNativeError(err) {
		entry.disposeLocked()
		r.mu.Lock()
		delete(r.sessions, token)
		r.closedTokens[token] = struct{}{}
		r.mu.Unlock()
		return errNativeDisconnected
	}
	return err
}

func (r *nativeSessionRegistry) withLegacySession(
	operation func(*nativeDeviceSession) error,
) error {
	r.mu.Lock()
	if r.shuttingDown || len(r.sessions) != 1 {
		r.mu.Unlock()
		if r.shuttingDown {
			return errBridgeShuttingDown
		}
		return errAmbiguousLegacySession
	}
	var token string
	for candidate := range r.sessions {
		token = candidate
	}
	r.mu.Unlock()
	return r.withSession(token, operation)
}

func (r *nativeSessionRegistry) close(token string) error {
	r.mu.Lock()
	entry := r.sessions[token]
	if entry != nil {
		delete(r.sessions, token)
		r.closedTokens[token] = struct{}{}
	}
	_, wasClosed := r.closedTokens[token]
	r.mu.Unlock()
	if entry == nil {
		if wasClosed {
			return nil
		}
		return errUnknownSessionToken
	}

	entry.mu.Lock()
	entry.disposeLocked()
	entry.mu.Unlock()
	return nil
}

func (r *nativeSessionRegistry) cleanup() {
	r.openMu.Lock()
	defer r.openMu.Unlock()
	r.mu.Lock()
	r.shuttingDown = true
	entries := make([]*nativeSessionEntry, 0, len(r.sessions))
	for token, entry := range r.sessions {
		entries = append(entries, entry)
		r.closedTokens[token] = struct{}{}
		delete(r.sessions, token)
	}
	r.mu.Unlock()

	for _, entry := range entries {
		entry.mu.Lock()
		entry.disposeLocked()
		entry.mu.Unlock()
	}
}

func isDisconnectedNativeError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, errNativeDisconnected) {
		return true
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "no device") ||
		strings.Contains(message, "device is not open") ||
		strings.Contains(message, "device disconnected") ||
		strings.Contains(message, "libusb_error_no_device")
}

var nativeSessions = newInactiveNativeSessionRegistry(openLiveNativeSession)
