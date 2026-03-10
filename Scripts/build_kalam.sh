#!/bin/bash
set -e

# Ensure Go is in part of the PATH for Xcode builds
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# Directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${SCRIPT_DIR}/.."
NATIVE_DIR="${PROJECT_ROOT}/Native"
TARGET_DIR="${PROJECT_ROOT}/SwiftMTP"
BUILD_DIR="${PROJECT_ROOT}/build"

# Deployment target - read from environment or extract from Xcode project
if [ -z "${MACOSX_DEPLOYMENT_TARGET}" ]; then
    PROJECT_FILE="${PROJECT_ROOT}/SwiftMTP.xcodeproj/project.pbxproj"
    if [ -f "${PROJECT_FILE}" ]; then
        MACOSX_DEPLOYMENT_TARGET=$(grep -m1 "MACOSX_DEPLOYMENT_TARGET = " "${PROJECT_FILE}" | sed 's/.*MACOSX_DEPLOYMENT_TARGET = \([0-9.]*\);.*/\1/')
    fi
    if [ -z "${MACOSX_DEPLOYMENT_TARGET}" ]; then
        MACOSX_DEPLOYMENT_TARGET=15.6
    fi
fi
export MACOSX_DEPLOYMENT_TARGET

echo "Building Kalam Kernel Bridge with bundled libusb..."

# Check for Go
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install it with 'brew install go'."
    exit 1
fi

# Build libusb from source for compatibility
echo "Building libusb from source for macOS ${MACOSX_DEPLOYMENT_TARGET}..."
LIBUSB_VERSION="1.0.27"
LIBUSB_SRC_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2"
LIBUSB_BUILD_DIR="${BUILD_DIR}/libusb-${LIBUSB_VERSION}"

mkdir -p "${BUILD_DIR}"

if [ ! -d "${LIBUSB_BUILD_DIR}" ]; then
    echo "Downloading libusb ${LIBUSB_VERSION}..."
    curl -L "${LIBUSB_SRC_URL}" | tar -xjf - -C "${BUILD_DIR}"
fi

cd "${LIBUSB_BUILD_DIR}"

# Configure and build libusb with the correct deployment target
echo "Configuring libusb..."
./configure --prefix="${BUILD_DIR}/libusb-install" \
    --disable-static \
    --enable-shared \
    CFLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}" \
    LDFLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

echo "Building libusb..."
make -j$(sysctl -n hw.ncpu)
make install

# Copy the built libusb to target
echo "📦 Copying libusb to target directory..."
cp -f "${BUILD_DIR}/libusb-install/lib/libusb-1.0.dylib" "${TARGET_DIR}/libusb-1.0.dylib"

# Set install name for libusb.dylib
install_name_tool -id "@rpath/libusb-1.0.dylib" "${TARGET_DIR}/libusb-1.0.dylib"

echo "✅ libusb built for macOS ${MACOSX_DEPLOYMENT_TARGET}"

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

# Build libkalam.dylib
echo "Compiling libkalam.dylib..."
export CGO_LDFLAGS="-L${BUILD_DIR}/libusb-install/lib -lusb-1.0 -framework CoreFoundation -framework IOKit -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export CGO_CFLAGS="-I${BUILD_DIR}/libusb-install/include/libusb-1.0 -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

go build -o "${TARGET_DIR}/libkalam.dylib" -buildmode=c-shared .

# Check outputs
if [ -f "${TARGET_DIR}/libkalam.dylib" ] && [ -f "${TARGET_DIR}/libkalam.h" ]; then
    echo "✅ Build successful!"
    echo "   Library: ${TARGET_DIR}/libkalam.dylib"
    echo "   Header:  ${TARGET_DIR}/libkalam.h"

    # Set install name for libkalam.dylib to be relative to @rpath
    echo "🔧 Setting install name for libkalam.dylib..."
    install_name_tool -id "@rpath/libkalam.dylib" "${TARGET_DIR}/libkalam.dylib"

    # Change libusb reference in libkalam.dylib to use @rpath
    echo "🔧 Updating libusb reference in libkalam.dylib..."
    install_name_tool -change "${BUILD_DIR}/libusb-install/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.dylib" "${TARGET_DIR}/libkalam.dylib" 2>/dev/null || true
    install_name_tool -change "${BUILD_DIR}/libusb-install/lib/libusb-1.0.dylib" "@rpath/libusb-1.0.dylib" "${TARGET_DIR}/libkalam.dylib" 2>/dev/null || true

    # Display library dependencies
    echo "📦 Library dependencies:"
    otool -L "${TARGET_DIR}/libkalam.dylib"
    echo ""
    echo "📦 libusb dependencies:"
    otool -L "${TARGET_DIR}/libusb-1.0.dylib"
    
    echo ""
    echo "📊 Deployment target info:"
    echo "libkalam.dylib:"
    otool -l "${TARGET_DIR}/libkalam.dylib" | grep -A 5 "LC_BUILD_VERSION" | head -6
    echo "libusb-1.0.dylib:"
    otool -l "${TARGET_DIR}/libusb-1.0.dylib" | grep -A 5 "LC_BUILD_VERSION" | head -6

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
