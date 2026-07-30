package main

import (
	"fmt"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

func (r *nativeSessionRegistry) download(
	token string,
	request nativeDownloadRequest,
) (uint64, error) {
	var transferred uint64
	err := r.withSession(token, func(session *nativeDeviceSession) error {
		if session.downloadFile == nil {
			return newTransferError(
				transferErrorInvalidInput,
				fmt.Errorf("exact session does not support download"),
			)
		}
		var operationErr error
		transferred, operationErr = session.downloadFile(request)
		return operationErr
	})
	return transferred, err
}

func (r *nativeSessionRegistry) upload(
	token string,
	request nativeUploadRequest,
) (uint64, error) {
	var transferred uint64
	err := r.withSession(token, func(session *nativeDeviceSession) error {
		if session.uploadFile == nil {
			return newTransferError(
				transferErrorInvalidInput,
				fmt.Errorf("exact session does not support upload"),
			)
		}
		var operationErr error
		transferred, operationErr = session.uploadFile(request)
		return operationErr
	})
	return transferred, err
}

func withLegacyMTPDevice(operation func(*mtp.Device) error) error {
	return nativeSessions.withLegacySession(func(session *nativeDeviceSession) error {
		if session.device == nil {
			return fmt.Errorf("active exact session has no live MTP device")
		}
		return operation(session.device)
	})
}
