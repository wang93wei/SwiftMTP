package main

/*
#include <stdlib.h>
#include <stdint.h>

typedef void (*KalamTransferProgressCallback)(uint64_t, uintptr_t);

static inline void KalamInvokeTransferProgress(
	uintptr_t callback,
	uintptr_t context,
	uint64_t bytes
) {
	if (callback != 0) {
		((KalamTransferProgressCallback)callback)(bytes, context);
	}
}
*/
import "C"

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

type transferProgressReporter func(uint64)

type nativeDownloadRequest struct {
	objectID        uint32
	destinationPath string
	operation       *transferCancellationOperation
	progress        transferProgressReporter
}

type nativeUploadRequest struct {
	storageID  uint32
	parentID   uint32
	sourcePath string
	name       string
	size       uint64
	operation  *transferCancellationOperation
	progress   transferProgressReporter
}

type transferErrorKind string

const (
	transferErrorInvalidInput transferErrorKind = "invalid_input"
	transferErrorLocalIO      transferErrorKind = "local_io"
	transferErrorTimeout      transferErrorKind = "timeout"
)

type nativeTransferError struct {
	kind transferErrorKind
	err  error
}

func (e *nativeTransferError) Error() string {
	return e.err.Error()
}

func (e *nativeTransferError) Unwrap() error {
	return e.err
}

func newTransferError(kind transferErrorKind, err error) error {
	return &nativeTransferError{kind: kind, err: err}
}

type bridgeTransferResponse struct {
	OK           bool   `json:"ok"`
	Bytes        uint64 `json:"bytes"`
	Error        string `json:"error,omitempty"`
	ResponseCode uint16 `json:"responseCode,omitempty"`
}

func nativeTransferErrorCode(err error) string {
	if err == nil {
		return ""
	}
	var typed *nativeTransferError
	if errors.As(err, &typed) {
		return string(typed.kind)
	}
	var cancelled *cancelError
	if errors.As(err, &cancelled) {
		return "cancelled"
	}
	if isDisconnectedNativeError(err) {
		return "disconnected"
	}
	var response mtp.RCError
	if errors.As(err, &response) {
		return "mtp_response"
	}
	var pathError *os.PathError
	if errors.As(err, &pathError) {
		return string(transferErrorLocalIO)
	}
	message := strings.ToLower(err.Error())
	if strings.Contains(message, "timeout") {
		return "timeout"
	}
	return nativeBridgeErrorCode(err)
}

func nativeTransferResponseCode(err error) uint16 {
	var response mtp.RCError
	if errors.As(err, &response) {
		return uint16(response)
	}
	return 0
}

func transferProgressCallback(
	callback C.uintptr_t,
	context C.uintptr_t,
) transferProgressReporter {
	return func(bytes uint64) {
		C.KalamInvokeTransferProgress(callback, context, C.uint64_t(bytes))
	}
}

func transferResponse(bytes uint64, err error) *C.char {
	if err != nil {
		return bridgeJSON(bridgeTransferResponse{
			Error:        nativeTransferErrorCode(err),
			ResponseCode: nativeTransferResponseCode(err),
		})
	}
	return bridgeJSON(bridgeTransferResponse{OK: true, Bytes: bytes})
}

//export Kalam_SetProgressCallback
func Kalam_SetProgressCallback(cb C.uintptr_t) {
	fmt.Printf("Kalam_SetProgressCallback: Progress callbacks disabled for stability\n")
}

//export Kalam_PrepareTransferTask
func Kalam_PrepareTransferTask(taskID *C.char) int32 {
	if taskID == nil {
		fmt.Printf("Kalam_PrepareTransferTask: taskID is nil\n")
		return 0
	}
	id := C.GoString(taskID)
	if err := transferCancellations.prepare(id); err != nil {
		fmt.Printf("Kalam_PrepareTransferTask: %v\n", err)
		return 0
	}
	return 1
}

//export Kalam_AbortTransferTask
func Kalam_AbortTransferTask(taskID *C.char) int32 {
	if taskID == nil {
		fmt.Printf("Kalam_AbortTransferTask: taskID is nil\n")
		return 0
	}
	if transferCancellations.abort(C.GoString(taskID)) {
		return 1
	}
	return 0
}

//export Kalam_DownloadFileSession
func Kalam_DownloadFileSession(
	token *C.char,
	objectID uint32,
	destinationPath *C.char,
	taskID *C.char,
	progressCallback C.uintptr_t,
	progressContext C.uintptr_t,
) *C.char {
	if token == nil || destinationPath == nil || taskID == nil {
		return transferResponse(0, newTransferError(
			transferErrorInvalidInput,
			fmt.Errorf("download session arguments must not be nil"),
		))
	}
	task := C.GoString(taskID)
	operation, err := transferCancellations.claim(task)
	if err != nil {
		return transferResponse(0, newTransferError(transferErrorInvalidInput, err))
	}
	defer operation.finish()
	bytes, err := nativeSessions.download(C.GoString(token), nativeDownloadRequest{
		objectID:        objectID,
		destinationPath: C.GoString(destinationPath),
		operation:       operation,
		progress:        transferProgressCallback(progressCallback, progressContext),
	})
	return transferResponse(bytes, err)
}

type cancelError struct {
	taskID string
}

func (e *cancelError) Error() string {
	return fmt.Sprintf("task %s cancelled", e.taskID)
}

//export Kalam_CancelTask
func Kalam_CancelTask(taskID *C.char) {
	if taskID == nil {
		fmt.Printf("Kalam_CancelTask: taskID is nil\n")
		return
	}

	id := C.GoString(taskID)
	if id == "" {
		fmt.Printf("Kalam_CancelTask: taskID is empty\n")
		return
	}

	if transferCancellations.cancel(id) {
		fmt.Printf("Kalam_CancelTask: Task %s marked for cancellation\n", id)
	}
}

//export Kalam_UploadFileSession
func Kalam_UploadFileSession(
	token *C.char,
	storageID uint32,
	parentID uint32,
	sourcePath *C.char,
	name *C.char,
	size uint64,
	taskID *C.char,
	progressCallback C.uintptr_t,
	progressContext C.uintptr_t,
) *C.char {
	if token == nil || sourcePath == nil || name == nil || taskID == nil {
		return transferResponse(0, newTransferError(
			transferErrorInvalidInput,
			fmt.Errorf("upload session arguments must not be nil"),
		))
	}
	task := C.GoString(taskID)
	operation, err := transferCancellations.claim(task)
	if err != nil {
		return transferResponse(0, newTransferError(transferErrorInvalidInput, err))
	}
	defer operation.finish()
	bytes, err := nativeSessions.upload(C.GoString(token), nativeUploadRequest{
		storageID:  storageID,
		parentID:   parentID,
		sourcePath: C.GoString(sourcePath),
		name:       C.GoString(name),
		size:       size,
		operation:  operation,
		progress:   transferProgressCallback(progressCallback, progressContext),
	})
	return transferResponse(bytes, err)
}
