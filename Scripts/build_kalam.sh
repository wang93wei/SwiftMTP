#!/bin/bash
set -e

# Ensure Go is in part of the PATH for Xcode builds
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# Directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${SCRIPT_DIR}/.."
NATIVE_DIR="${PROJECT_ROOT}/Native"
TARGET_DIR="${PROJECT_ROOT}/SwiftMTP"

echo "Building Kalam Kernel Bridge..."

# Check for Go
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install it with 'brew install go'."
    exit 1
fi

cd "${NATIVE_DIR}"

# Initialize module if needed
if [ ! -f go.mod ]; then
    echo "Initializing Go module..."
    go mod init kalam-bridge
fi

# Fetch dependencies
echo "Fetching dependencies..."
go get github.com/ganeshrvel/go-mtpx
go mod tidy

# Build
echo "Compiling libkalam.dylib..."
go build -o "${TARGET_DIR}/libkalam.dylib" -buildmode=c-shared kalam_bridge.go

# Check outputs
if [ -f "${TARGET_DIR}/libkalam.dylib" ] && [ -f "${TARGET_DIR}/libkalam.h" ]; then
    echo "✅ Build successful!"
    echo "   Library: ${TARGET_DIR}/libkalam.dylib"
    echo "   Header:  ${TARGET_DIR}/libkalam.h"

    # Set install name to be relative to @rpath
    echo "🔧 Setting install name to @rpath/libkalam.dylib..."
    install_name_tool -id "@rpath/libkalam.dylib" "${TARGET_DIR}/libkalam.dylib"

    # Xcode Integration
    # If running in Xcode, copy to Frameworks and sign
    LOG_FILE="/tmp/build_kalam.log"
    echo "--- Build started at $(date) ---" >> "${LOG_FILE}"
    echo "BUILT_PRODUCTS_DIR: ${BUILT_PRODUCTS_DIR}" >> "${LOG_FILE}"
    echo "FRAMEWORKS_FOLDER_PATH: ${FRAMEWORKS_FOLDER_PATH}" >> "${LOG_FILE}"

    if [ -n "${BUILT_PRODUCTS_DIR}" ] && [ -n "${FRAMEWORKS_FOLDER_PATH}" ]; then
        DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
        echo "📂 Xcode Environment detected."
        echo "   Target Destination: ${DEST_DIR}"
        
        mkdir -p "${DEST_DIR}"
        cp -f "${TARGET_DIR}/libkalam.dylib" "${DEST_DIR}/"
        echo "   ✅ Copied libkalam.dylib to Frameworks"

        if [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
            echo "🔐 Signing library with identity: ${EXPANDED_CODE_SIGN_IDENTITY}"
            codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_DIR}/libkalam.dylib"
            echo "   ✅ Signed libkalam.dylib"
        else
            echo "⚠️ No code sign identity found, skipping signing."
            echo "   (This is normal for Simulator builds or if signing is disabled)"
        fi
    else
        echo "ℹ️ Not running in Xcode build environment or variables missing."
        echo "   Skipping auto-copy to Frameworks."
        echo "   Ensure you have added the 'Run Script' phase if you want auto-copying."
    fi
else
    echo "❌ Build failed: Output files missing."
    exit 1
fi
