#!/bin/bash

# SwiftMTP Test Runner Script
# Runs all unit tests and generates coverage reports

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${SCRIPT_DIR}/.."

echo "======================================"
echo "SwiftMTP Test Runner"
echo "======================================"
echo ""

# Parse command line arguments
RUN_SWIFT=true
RUN_GO=true
GENERATE_COVERAGE=false
RUN_ALL=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --swift-only)
            RUN_SWIFT=true
            RUN_GO=false
            RUN_ALL=false
            shift
            ;;
        --go-only)
            RUN_SWIFT=false
            RUN_GO=true
            RUN_ALL=false
            shift
            ;;
        --coverage)
            GENERATE_COVERAGE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --swift-only     Run Swift tests only"
            echo "  --go-only        Run Go tests only"
            echo "  --coverage       Generate code coverage reports"
            echo "  --help           Show this help message"
            echo ""
            echo "If no options are provided, all tests will be run."
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Function to print section header
print_header() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo ""
}

# Function to print success message
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error message
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print warning message
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Run Swift tests
if [ "$RUN_SWIFT" = true ]; then
    print_header "Running Swift Tests"

    # Check if xcodebuild is available
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild is not installed. Please install Xcode Command Line Tools."
        exit 1
    fi

    # Build and run Swift tests
    cd "${PROJECT_ROOT}"

    if [ "$GENERATE_COVERAGE" = true ]; then
        print_warning "Generating code coverage report..."
        
        # Create coverage output directory
        COVERAGE_DIR="${PROJECT_ROOT}/build/coverage"
        mkdir -p "${COVERAGE_DIR}"

        # Run tests with coverage
        xcodebuild test \
            -project SwiftMTP.xcodeproj \
            -scheme SwiftMTP \
            -destination 'platform=macOS' \
            -enableCodeCoverage YES \
            -resultBundlePath "${COVERAGE_DIR}/TestResults.xcresult" \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO || {
            print_error "Swift tests failed"
            exit 1
        }

        # Generate coverage report
        if command -v xcrun &> /dev/null; then
            print_success "Generating coverage report..."
            xcrun xccov view --report --json "${COVERAGE_DIR}/TestResults.xcresult" > "${COVERAGE_DIR}/coverage.json"
            xcrun xccov view --report "${COVERAGE_DIR}/TestResults.xcresult" > "${COVERAGE_DIR}/coverage.txt"
            print_success "Coverage report generated: ${COVERAGE_DIR}/coverage.txt"
        else
            print_warning "xcrun not available, skipping coverage report generation"
        fi
    else
        # Run tests without coverage
        xcodebuild test \
            -project SwiftMTP.xcodeproj \
            -scheme SwiftMTP \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO || {
            print_error "Swift tests failed"
            exit 1
        }
    fi

    print_success "Swift tests passed"
fi

# Run Go tests
if [ "$RUN_GO" = true ]; then
    print_header "Running Go Tests"

    # Check if go is available
    if ! command -v go &> /dev/null; then
        print_error "Go is not installed. Please install Go."
        exit 1
    fi

    cd "${PROJECT_ROOT}/Native"

    if [ "$GENERATE_COVERAGE" = true ]; then
        print_warning "Generating Go code coverage report..."

        # Create coverage output directory
        COVERAGE_DIR="${PROJECT_ROOT}/build/coverage"
        mkdir -p "${COVERAGE_DIR}"

        # Run tests with coverage
        go test -v -coverprofile="${COVERAGE_DIR}/go_coverage.out" -covermode=atomic ./... || {
            print_error "Go tests failed"
            exit 1
        }

        # Generate coverage report
        go tool cover -html="${COVERAGE_DIR}/go_coverage.out" -o "${COVERAGE_DIR}/go_coverage.html"
        go tool cover -func="${COVERAGE_DIR}/go_coverage.out" > "${COVERAGE_DIR}/go_coverage.txt"
        print_success "Go coverage report generated: ${COVERAGE_DIR}/go_coverage.html"
    else
        # Run tests without coverage
        go test -v ./... || {
            print_error "Go tests failed"
            exit 1
        }
    fi

    print_success "Go tests passed"
fi

# Summary
print_header "Test Summary"

if [ "$RUN_SWIFT" = true ]; then
    print_success "Swift tests completed"
fi

if [ "$RUN_GO" = true ]; then
    print_success "Go tests completed"
fi

if [ "$GENERATE_COVERAGE" = true ]; then
    print_success "Coverage reports generated in build/coverage/"
fi

echo ""
echo -e "${GREEN}All tests passed!${NC}"
echo ""