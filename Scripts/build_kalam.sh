#!/bin/bash
set -e

# Ensure Go is in part of the PATH for Xcode builds
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# Directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${SCRIPT_DIR}/.."
NATIVE_DIR="${PROJECT_ROOT}/Native"
TARGET_DIR="${PROJECT_ROOT}/SwiftMTP"

echo "Building Kalam Kernel Bridge with bundled libusb..."

# Check for Go
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install it with 'brew install go'."
    exit 1
fi

# Check for the repository-pinned libusb runtime and headers.
if [ ! -f "${TARGET_DIR}/libusb-1.0.dylib" ] ||
   [ ! -f "${TARGET_DIR}/Support/CLibUSB/include/libusb.h" ]; then
    echo "Error: bundled libusb runtime or headers are missing."
    exit 1
fi

cd "${NATIVE_DIR}"

if [ ! -f go.mod ] || [ ! -d vendor ]; then
    echo "Error: pinned Go module metadata or vendored dependencies are missing."
    exit 1
fi

echo "Using vendored Go dependencies..."

# Build libkalam.dylib
echo "Compiling libkalam.dylib..."
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
export CGO_LDFLAGS="-L${TARGET_DIR} -framework CoreFoundation -framework IOKit -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export CGO_CFLAGS="-I${TARGET_DIR}/Support/CLibUSB/include -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

go build -mod=vendor -o "${TARGET_DIR}/libkalam.dylib" -buildmode=c-shared .

# Check outputs
if [ -f "${TARGET_DIR}/libkalam.dylib" ] && [ -f "${TARGET_DIR}/libkalam.h" ]; then
    echo "✅ Build successful!"
    echo "   Library: ${TARGET_DIR}/libkalam.dylib"
    echo "   Header:  ${TARGET_DIR}/libkalam.h"

    echo "📦 Using repository-pinned libusb.dylib..."

    # Set install name for libkalam.dylib to be relative to @rpath
    echo "🔧 Setting install name for libkalam.dylib..."
    install_name_tool -id "@rpath/libkalam.dylib" "${TARGET_DIR}/libkalam.dylib"

    # Change libusb reference in libkalam.dylib to use @rpath
    echo "🔧 Updating libusb reference in libkalam.dylib..."
    install_name_tool -change "/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.dylib" "${TARGET_DIR}/libkalam.dylib"
    install_name_tool -change "/opt/homebrew/opt/libusb/lib/libusb-1.0.dylib" "@rpath/libusb-1.0.dylib" "${TARGET_DIR}/libkalam.dylib" 2>/dev/null || true

    # install_name_tool invalidates Go's generated ad-hoc signature.
    echo "🔐 Re-signing libkalam.dylib after Mach-O updates..."
    codesign --force --sign - --timestamp=none "${TARGET_DIR}/libkalam.dylib"
    codesign --verify --strict "${TARGET_DIR}/libkalam.dylib"

    # Keep the checked-in Native ABI header identical to the Swift target header.
    echo "🔄 Synchronizing generated ABI headers..."
    cp -f "${TARGET_DIR}/libkalam.h" "${NATIVE_DIR}/libkalam.h"
    cmp "${NATIVE_DIR}/libkalam.h" "${TARGET_DIR}/libkalam.h"

    # Display library dependencies
    echo "📦 Library dependencies:"
    otool -L "${TARGET_DIR}/libkalam.dylib"
    echo ""
    echo "📦 libusb dependencies:"
    otool -L "${TARGET_DIR}/libusb-1.0.dylib"

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
        cp -f "${TARGET_DIR}/libusb-1.0.dylib" "${DEST_DIR}/"
        echo "   ✅ Copied libkalam.dylib to Frameworks"
        echo "   ✅ Copied libusb-1.0.dylib to Frameworks"

        if [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
            echo "🔐 Signing libraries with identity: ${EXPANDED_CODE_SIGN_IDENTITY}"
            codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_DIR}/libkalam.dylib"
            codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST_DIR}/libusb-1.0.dylib"
            echo "   ✅ Signed libkalam.dylib"
            echo "   ✅ Signed libusb-1.0.dylib"
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
