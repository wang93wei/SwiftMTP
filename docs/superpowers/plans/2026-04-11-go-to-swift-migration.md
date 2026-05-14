# Go-to-Swift Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Go/CGO MTP backend with a native Swift + libusb stack without changing the app's user-facing behavior.

**Architecture:** Build a new `MTPCore` layer under `SwiftMTP/Services/` with three slices: `USBTransport`, `MTPProtocol`, and `MTPDevice`. Land it under tests first, then switch `DeviceManager`, `FileSystemManager`, and `FileTransferManager` to the new layer, and only then remove the bridge, build script, and `Native/` tree.

**Tech Stack:** Swift 6, SwiftUI, XCTest, libusb-1.0 static library, Xcode project settings, and Go source used as the migration reference only.

***

## Scope Check

This spec spans four dependent subsystems:

1. Project/build wiring
2. Protocol and USB core
3. High-level file/device operations
4. App service-layer cutover and cleanup

They are not independent enough to deserve separate plans, so this plan keeps them together but enforces phase gates. Do not start a later task until the verification command in the current task is green.

## Execution Rules

- Execute in a dedicated worktree before touching code.
- Use TDD throughout: add the failing test first, then land the minimum code to make it pass.
- Keep `SwiftMTP/Services/MTP/FileTransferManager.swift` and `SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift` on `DispatchQueue` + `NSLock`. Do not migrate those files to actors or `@MainActor`.
- Until Task 10 is complete, keep the current Go-backed app build working while the new Swift stack is added beside it. Task 11 removes the now-unused bridge artifacts and docs.
- Run the real-device smoke check at the end of Tasks 5, 8, and 11 with an Android phone attached.
- Task 5 introduces per-device USB identities and can enumerate more than one attached MTP device. That is an intentional transport-layer expansion relative to the current Go bridge, which effectively selects a single opened device. Do not silently collapse back to single-device assumptions later in the plan.

### Task Dependency Graph

Tasks 1–4 each produce independent build artifacts but have a soft ordering dependency: each task's tests build on types/fixtures from the prior task. Tasks 5+ form a strict chain:

```mermaid
graph LR
    T1[Task 1: CLibUSB Wiring] --> T5[Task 5: USB Transport]
    T2[Task 2: Fixture Loading] --> T3[Task 3: Protocol Primitives]
    T3 --> T4[Task 4: Types & Decoding]
    T4 --> T5
    T5 --> T6[Task 6: Device Sessions]
    T6 --> T7[Task 7: High-Level Ops]
    T6 --> T8[Task 8: Pool & Retry]
    T7 --> T9[Task 9: Service Cutover]
    T8 --> T9
    T9 --> T10[Task 10: Transfer Cutover]
    T10 --> T11[Task 11: Cleanup & Verify]
```

- Tasks 1–4 are build-independent (no shared Xcode targets beyond the test host) but must execute in order because each task's tests reference types/fixtures from the prior task.
- **Task 7和Task 8并行执行的协调机制**：
  1. **输出接口预定义**：Task 7的输出（`MTPFileOperations`）和Task 8的输出（`MTPDevicePool`）必须在Task 6中定义明确的接口协议
  2. **集成测试策略**：Task 9（Service Cutover）需要同时集成这两个模块，因此：
     - Task 7和Task 8完成后，必须各自运行完整的单元测试
     - Task 9开始前，需要运行集成测试验证两个模块的交互
     - 如果集成测试失败，优先修复Task 8（连接池）的问题，因为它是底层基础设施
  3. **代码审查要求**：Task 7和Task 8的代码必须经过交叉审查，确保接口一致性
- Task 9 requires both Task 7 and Task 8.
- Task 11 is the final cleanup gate.

## File Map

### New Build and Interop Files

- Create: `SwiftMTP/CLibUSB/module.modulemap`
- Create: `SwiftMTP/CLibUSB/libusb.h`
- Create: `lib/libusb-1.0.a`
- Modify: `SwiftMTP.xcodeproj/project.pbxproj`

### New MTPCore Source Files

- Create: `SwiftMTP/Services/MTPCore/USBTransport/USBDevice.swift`
- Create: `SwiftMTP/Services/MTPCore/USBTransport/USBDebugLogger.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPConstants.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPDebugLogger.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Operations.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Download.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceScanner.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceManager.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDataStructures.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPUtilities.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevicePool.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevicePool+Sync.swift`
- Create: `SwiftMTPTests/MTPCore/Support/MockMTPDevice.swift`

### New Test Files

- Create: `SwiftMTPTests/MTPCore/CLibUSBSmokeTests.swift`
- Create: `SwiftMTPTests/MTPCore/FixtureSmokeTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPConstantsTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPContainerTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPEncodingTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPTypeDecodingTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPDeviceScannerTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPDeviceTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPDeviceManagerTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPFileOperationsTests.swift`
- Create: `SwiftMTPTests/MTPCore/MTPDevicePoolTests.swift`
- Create: `SwiftMTPTests/MTPCore/ErrorPathTests.swift`
- Create: `SwiftMTPTests/MTPCore/ServiceComparisonTests.swift`
- Create: `SwiftMTPTests/MTPCore/ManualRealDeviceSmokeTests.swift`
- Create: `SwiftMTPTests/MTPCore/Support/FixtureLoader.swift`
- Create: `SwiftMTPTests/MTPCore/Support/MockUSBTransport.swift`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/container_command.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/container_response_ok.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/device_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/storage_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/object_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/object_handles.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_access_denied.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_store_full.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_invalid_handle.bin`
- Create: `SwiftMTPTests/MTPCore/Snapshots/constants_reference.json` (temporary — deleted after Task 3 Step 5)

### Existing App Files to Modify

- Modify: `SwiftMTP/Models/Device.swift`
- Modify: `SwiftMTP/Config/AppConfiguration.swift`
- Modify: `SwiftMTP/App/SwiftMTPApp.swift`
- Modify: `SwiftMTP/Services/MTP/DeviceManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileSystemManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileTransferManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift`
- Modify: `SwiftMTP/Views/FileBrowserView+Actions.swift`
- Modify: `SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift`
- Modify: `SwiftMTP/Views/FileBrowserView.swift`
- Modify: `SwiftMTP/Services/Protocols/DeviceManaging.swift`
- Modify: `SwiftMTP/Services/Protocols/FileSystemManaging.swift`
- Modify: `SwiftMTP/Services/Protocols/FileTransferManaging.swift`

### Temporary Migration Files

- None. Do not add one-off fixture capture tools unless they are actually exercised by the task steps.

### Final Cleanup Targets

- Delete: `SwiftMTP/SwiftMTP-Bridging-Header.h`
- Delete: `SwiftMTP/libkalam.dylib`
- Delete: `SwiftMTP/libkalam.h`
- Delete: `SwiftMTP/libusb-1.0.dylib`
- Delete: `Scripts/build_kalam.sh`
- Delete: `Scripts/record_mtp_fixtures.go` (migration-phase-only tool, per spec Section 1 Go Tool Policy)
- Delete: `Native/`

### Docs and Tooling to Update at the End

- Modify: `Scripts/run_tests.sh`
- Modify: `setup-check.sh`
- Modify: `SwiftMTP/Resources/Base.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/en.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ja.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ko.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ru.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/fr.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/de.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `docs/README.zh-CN.md`
- Modify: `docs/README.ja.md`
- Modify: `docs/README.ko.md`
- Modify: `docs/README.ru.md`
- Modify: `docs/README.fr.md`
- Modify: `docs/README.de.md`
- Modify: `docs/SwiftMTP.wiki/API.md`
- Modify: `docs/SwiftMTP.wiki/Architecture.md`
- Modify: `docs/SwiftMTP.wiki/Build-and-Deploy.md`
- Modify: `docs/SwiftMTP.wiki/Development-Setup.md`
- Modify: `docs/SwiftMTP.wiki/Home.md`
- Modify: `docs/SwiftMTP.wiki/Modules.md`
- Modify: `docs/SwiftMTP.wiki/FAQ.md`
- Modify: `docs/SwiftMTP.wiki/Testing.md`
- Modify: `docs/SwiftMTP.wiki/Troubleshooting.md`
- Modify: `docs/TESTING.md`
- Modify: `docs/sequence-diagrams.md`
- Modify: `docs/architecture-diagrams.md`
- Modify: `docs/WIKI.md`
- Modify: `CLAUDE.md`

## Acceptance Map

- Behaviors 1-4 are proved by Tasks 5, 6, 8, and 9.
- Behaviors 5-12 and 16-17 are proved by Tasks 7, 8, 9, and 10.
- Behaviors 13-15 are proved by Tasks 8 and 11.
- The build, cleanup, and "no Go artifacts remain" criteria are proved by Tasks 1 and 11.

### Success Criteria Coverage (all 20 covered)

| #  | Behavior                       | Task                                                   | Test Coverage                                                                                          |
| -- | ------------------------------ | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| 1  | Detect USB MTP device          | Task 5 (scanner), Task 9 (DeviceManager)               | MTPDeviceScannerTests, ManualRealDeviceSmokeTests                                                      |
| 2  | Display device info            | Task 7, Task 9 (mapping with MTPSupportInfo)           | MTPDeviceManagerTests, ServiceComparisonTests                                                          |
| 3  | Display storage info           | Task 7, Task 9                                         | MTPDeviceManagerTests                                                                                  |
| 4  | Browse filesystem              | Task 7 (listFiles), Task 9                             | MTPFileOperationsTests.listFiles                                                                       |
| 5  | Download file (chunked stream) | Task 10                                                | MTPFileOperationsTests.downloadEmptyFile, downloadWithProgress                                         |
| 6  | Upload file (chunked stream)   | Task 10                                                | MTPFileOperationsTests.uploadLargeFile                                                                 |
| 7  | Delete file                    | Task 10 (FileSystemManager + view cutover)             | MTPFileOperationsTests.deleteObject                                                                    |
| 8  | Create folder                  | Task 10 (FileSystemManager + view cutover)             | MTPFileOperationsTests.createFolder                                                                    |
| 9  | Directory upload               | Task 10 (DirectoryUpload)                              | manual real-device verification in Task 11 step 4 item 9; do not claim pre-existing automated coverage |
| 10 | Cancel transfer (isCancelled)  | Task 10                                                | MTPFileOperationsTests.uploadCancelledMidTransfer                                                      |
| 11 | Storage refresh after upload   | Task 10 (`DeviceManager.scanDevices()` after success)  | verified in real-device smoke                                                                          |
| 12 | Device cache reset             | Task 10 (`FileSystemManager.clearCache` after success) | verified in real-device smoke                                                                          |
| 13 | Pool reuse                     | Task 8 (continuation-based pool)                       | MTPDevicePoolTests.testSecondOperationReusesPooledDevice                                               |
| 14 | Retry on transient error       | Task 8                                                 | MTPDevicePoolTests.testRecoverableErrorRetriesOnce                                                     |
| 15 | Clean shutdown                 | Task 11 (shutdown with waiter resume)                  | pool disposes entries + waiters                                                                        |
| 16 | Download empty file            | Task 10 (explicitly fix current Go bridge zero-byte false failure) | MTPFileOperationsTests.downloadEmptyFile                                                               |
| 17 | Large file download (>=100MB)  | Task 10 (streaming via `GetObject` parity path)        | ManualRealDeviceSmokeTests                                                                             |
| 18 | Two devices scanned distinctly | Task 5 + Task 9 (`transportIdentity`)                  | manual real-device verification in Task 11 step 4 item 18                                              |
| 19 | Duplicate serial continuity    | Task 9 (duplicate serial fallback to `transportIdentity`) | manual real-device verification in Task 11 step 4 item 19                                           |
| 20 | Empty serial continuity        | Task 9 (empty serial fallback to `transportIdentity`)  | manual real-device verification in Task 11 step 4 item 20                                              |

### Task 1: Add CLibUSB Project Wiring

**Files:**

- Create: `SwiftMTP/CLibUSB/module.modulemap`
- Create: `SwiftMTP/CLibUSB/libusb.h`
- Create: `lib/libusb-1.0.a`
- Modify: `SwiftMTP.xcodeproj/project.pbxproj`
- Test: `SwiftMTPTests/MTPCore/CLibUSBSmokeTests.swift`
- [ ] **Step 1: Write the failing compile smoke test**

```swift
import XCTest
import CLibUSB

final class CLibUSBSmokeTests: XCTestCase {
    func testLibUSBModuleResolvesErrorName() {
        XCTAssertEqual(String(cString: libusb_error_name(0)), "LIBUSB_SUCCESS")
    }
}
```

- [ ] **Step 2: Run the single test to prove the module is missing**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/CLibUSBSmokeTests
```

Expected: build fails with `no such module 'CLibUSB'`.

- [ ] **Step 3: Add the module map, vendored header, static library, and linker settings**

`SwiftMTP/CLibUSB/module.modulemap`

```text
module CLibUSB {
    header "libusb.h"
    export *
}
```

Copy the header and static library:

```bash
mkdir -p SwiftMTP/CLibUSB lib
cp "$(brew --prefix libusb)/include/libusb-1.0/libusb.h" SwiftMTP/CLibUSB/libusb.h
cp "$(brew --prefix libusb)/lib/libusb-1.0.a" lib/libusb-1.0.a
```

**完整的Xcode项目配置步骤：**

1. **添加模块映射文件**：
   - 在Xcode项目中，右键点击`SwiftMTP`组
   - 选择"Add Files to SwiftMTP..."
   - 选择`SwiftMTP/CLibUSB/module.modulemap`
   - 确保"Copy items if needed"未勾选（文件已在正确位置）

2. **配置构建设置**：
   - 选择项目根节点`SwiftMTP`
   - 选择`SwiftMTP` target
   - 转到"Build Settings"标签
   - 搜索并设置以下设置：

   **Header Search Paths**（添加）：
   ```
   $(SRCROOT)/SwiftMTP/CLibUSB
   $(SRCROOT)/SwiftMTP/Services/MTP/**
   ```
   - 设置为"recursive"（对于MTP路径）

   **Library Search Paths**（添加）：
   ```
   $(SRCROOT)/lib
   ```

   **Other Linker Flags**（添加）：
   ```
   $(SRCROOT)/lib/libusb-1.0.a
   -framework
   CoreFoundation
   -framework
   IOKit
   ```

   **Import Paths**（添加）：
   ```
   $(SRCROOT)/SwiftMTP/CLibUSB
   ```

3. **验证静态库架构**：
   ```bash
   # 检查libusb-1.0.a的架构
   file lib/libusb-1.0.a
   
   # 应该显示：Mach-O universal binary with 1 architecture
   # 或者：current ar archive random library (如果只是arm64)
   
   # 如果是universal binary，检查是否包含arm64
   lipo -info lib/libusb-1.0.a
   ```

4. **验证头文件路径**：
   ```bash
   # 确保libusb.h在正确位置
   ls -la SwiftMTP/CLibUSB/libusb.h
   
   # 检查头文件内容，确认版本
   head -20 SwiftMTP/CLibUSB/libusb.h | grep -i version
   ```

Relevant `project.pbxproj` build settings block:

```text
HEADER_SEARCH_PATHS = (
    "$(SRCROOT)/SwiftMTP/CLibUSB",
    "$(SRCROOT)/SwiftMTP/Services/MTP/**",
);
LIBRARY_SEARCH_PATHS = (
    "$(SRCROOT)/lib",
);
OTHER_LDFLAGS = (
    "$(SRCROOT)/lib/libusb-1.0.a",
    "-framework",
    "CoreFoundation",
    "-framework",
    "IOKit",
);
IMPORT_PATHS = (
    "$(SRCROOT)/SwiftMTP/CLibUSB",
);
```

- [ ] **Step 4: Re-run the smoke test**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/CLibUSBSmokeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTP/CLibUSB/module.modulemap SwiftMTP/CLibUSB/libusb.h lib/libusb-1.0.a SwiftMTP.xcodeproj/project.pbxproj SwiftMTPTests/MTPCore/CLibUSBSmokeTests.swift
git commit -m "build(mtpcore): add libusb module wiring"
```

### Task 2: Add Fixture Loading and Seed Protocol Fixtures

**Files:**

- Create: `SwiftMTPTests/MTPCore/Support/FixtureLoader.swift`
- Create: `SwiftMTPTests/MTPCore/FixtureSmokeTests.swift`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/container_command.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/container_response_ok.bin`
- Create: `SwiftMTPTests/MTPCore/Snapshots/constants_reference.json`
- [ ] **Step 1: Write the failing fixture smoke test**

```swift
import XCTest

final class FixtureSmokeTests: XCTestCase {
    func testContainerCommandFixtureExistsAndHasExpectedLength() throws {
        let data = try FixtureLoader.data(named: "container_command.bin")
        XCTAssertEqual(data.count, 16)
    }
}
```

- [ ] **Step 2: Run the test to prove the loader and fixture do not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/FixtureSmokeTests
```

Expected: build fails because `FixtureLoader` is undefined.

- [ ] **Step 3: Add the loader and first committed fixtures**

`SwiftMTPTests/MTPCore/Support/FixtureLoader.swift`

```swift
import Foundation

enum FixtureLoader {
    static func data(named name: String, subdirectory: String = "Fixtures/Protocol", file: StaticString = #filePath) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = testsDirectory.appendingPathComponent(subdirectory).appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
```

Seed the first binary fixtures and constant snapshot:

```bash
mkdir -p SwiftMTPTests/MTPCore/Fixtures/Protocol SwiftMTPTests/MTPCore/Snapshots
printf '10000000010002100000000001000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/container_command.bin
printf '0c0000000300012000000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/container_response_ok.bin
cat > SwiftMTPTests/MTPCore/Snapshots/constants_reference.json <<'EOF'
{
  "OC_GetDeviceInfo": 4097,
  "OC_OpenSession": 4098,
  "OC_GetStorageIDs": 4100,
  "RC_OK": 8193
}
EOF
```

These fixtures intentionally encode the first `OpenSession` round-trip (`transactionID == 0`).
Later session and sync-loss tests should generate their own response containers instead of
reusing `container_response_ok.bin` for every transaction.

**`constants_reference.json` usage:** This file is a one-time migration aid extracted from Go's `const.go`. During Task 3 implementation, manually compare its values against the hardcoded spec-derived assertions in `MTPConstantsTests` (e.g., `XCTAssertEqual(MTPConstants.OC_OpenSession, 0x1002)`). If the Go reference disagrees with the MTP spec, **the spec wins**. After Task 3 is complete, delete this file — it is not used by any automated test.

- [ ] **Step 4: Re-run the smoke test**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/FixtureSmokeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTPTests/MTPCore/Support/FixtureLoader.swift SwiftMTPTests/MTPCore/FixtureSmokeTests.swift SwiftMTPTests/MTPCore/Fixtures/Protocol/container_command.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/container_response_ok.bin SwiftMTPTests/MTPCore/Snapshots/constants_reference.json
git commit -m "test(mtpcore): add fixture loading scaffold"
```

### Task 3: Implement Protocol Constants, Containers, and Primitive Encoding

**Files:**

- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPConstants.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift`
- Test: `SwiftMTPTests/MTPCore/MTPConstantsTests.swift`
- Test: `SwiftMTPTests/MTPCore/MTPContainerTests.swift`
- Test: `SwiftMTPTests/MTPCore/MTPEncodingTests.swift`
- [ ] **Step 1: Write the first failing protocol tests**

```swift
import XCTest
@testable import SwiftMTP

final class MTPConstantsTests: XCTestCase {
    func testCoreOperationCodesMatchSpec() {
        XCTAssertEqual(MTPConstants.OC_GetDeviceInfo, 0x1001)
        XCTAssertEqual(MTPConstants.OC_OpenSession, 0x1002)
        XCTAssertEqual(MTPConstants.RC_OK, 0x2001)
    }
}

final class MTPContainerTests: XCTestCase {
    func testDecodeCommandContainerFixture() throws {
        let data = try FixtureLoader.data(named: "container_command.bin")
        var reader = MTPDataReader(data: data)
        let container = try MTPContainer(from: &reader)
        XCTAssertEqual(container.code, MTPConstants.OC_OpenSession)
        XCTAssertEqual(container.transactionID, 0)
        XCTAssertEqual(container.parameters, [1])
    }
}
```

- [ ] **Step 2: Run the tests to prove the protocol layer is missing**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPConstantsTests -only-testing:SwiftMTPTests/MTPContainerTests
```

Expected: build fails because `MTPConstants`, `MTPDataReader`, and `MTPContainer` are undefined.

- [ ] **Step 3: Add the minimum constants, container types, and little-endian reader/writer**

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPConstants.swift`

```swift
enum MTPConstants {
    static let OC_GetDeviceInfo: UInt16 = 0x1001
    static let OC_OpenSession: UInt16 = 0x1002
    static let OC_CloseSession: UInt16 = 0x1003
    static let OC_GetStorageIDs: UInt16 = 0x1004
    static let OC_GetStorageInfo: UInt16 = 0x1005
    static let OC_GetObjectHandles: UInt16 = 0x1007
    static let OC_GetObjectInfo: UInt16 = 0x1008
    static let OC_GetObject: UInt16 = 0x1009
    static let OC_GetObjectPropValue: UInt16 = 0x9803
    static let OC_DeleteObject: UInt16 = 0x100B
    static let OC_SendObjectInfo: UInt16 = 0x100C
    static let OC_SendObject: UInt16 = 0x100D
    // Android extension: optional future optimization only, not the migration parity path
    static let OC_GetPartialObject64: UInt16 = 0x95C1
    static let RC_OK: UInt16 = 0x2001
    static let RC_SessionAlreadyOpened: UInt16 = 0x201E
    static let RC_AccessDenied: UInt16 = 0x200F
    static let RC_StoreFull: UInt16 = 0x200C
    static let RC_InvalidObjectHandle: UInt16 = 0x2009
    // Required by Task 7's large-file metadata fallback when ObjectInfo reports 0xffffffff.
    static let OPC_ObjectSize: UInt16 = 0xDC04
}
```

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift`

```swift
enum MTPContainerType: UInt16 {
    case command = 1
    case data = 2
    case response = 3
    case event = 4
}

struct MTPContainer: Equatable {
    let length: UInt32
    let type: MTPContainerType
    let code: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]
}
```

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift`

```swift
import Foundation

struct MTPDataReader {
    private let data: Data
    private(set) var offset: Int = 0

    var remainingBytes: Int { data.count - offset }

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw CocoaError(.coderReadCorrupt) }
        let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        offset += 2
        return value
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw CocoaError(.coderReadCorrupt) }
        let b = data
        let value = UInt32(b[offset])
            | (UInt32(b[offset + 1]) << 8)
            | (UInt32(b[offset + 2]) << 16)
            | (UInt32(b[offset + 3]) << 24)
        offset += 4
        return value
    }
}

struct MTPDataWriter {
    private(set) var data = Data()

    mutating func writeUInt16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt64(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeMTPString(_ string: String) throws {
        let utf16 = Array(string.utf16)
        guard utf16.count + 1 <= UInt8.max else {
            throw MTPError.nonRecoverable("MTP string exceeds 255 UTF-16 code units")
        }
        data.append(UInt8(utf16.count + 1)) // length includes null terminator
        for scalar in utf16 {
            writeUInt16(scalar)
        }
        writeUInt16(0) // null terminator
    }
}

extension MTPContainer {
    init(from reader: inout MTPDataReader) throws {
        let length = try reader.readUInt32()
        guard length >= 12 else { throw CocoaError(.coderReadCorrupt) }
        guard length - 4 <= UInt32(reader.remainingBytes) else { throw CocoaError(.coderReadCorrupt) }
        let typeRaw = try reader.readUInt16()
        let code = try reader.readUInt16()
        let transactionID = try reader.readUInt32()
        let paramCount = Int((length - 12) / 4)
        var parameters: [UInt32] = []
        parameters.reserveCapacity(paramCount)
        for _ in 0..<paramCount {
            parameters.append(try reader.readUInt32())
        }
        guard let type = MTPContainerType(rawValue: typeRaw) else { throw CocoaError(.coderInvalidValue) }
        self.init(length: length, type: type, code: code, transactionID: transactionID, parameters: parameters)
    }
}
```

- [ ] **Step 4: Add the first encoding test and re-run the focused suite**

`SwiftMTPTests/MTPCore/MTPEncodingTests.swift`

```swift
import XCTest
@testable import SwiftMTP

final class MTPEncodingTests: XCTestCase {
    func testWriteUInt32UsesLittleEndian() {
        var writer = MTPDataWriter()
        writer.writeUInt32(0x12345678)
        XCTAssertEqual(writer.data as NSData, Data([0x78, 0x56, 0x34, 0x12]) as NSData)
    }
}
```

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPConstantsTests -only-testing:SwiftMTPTests/MTPContainerTests -only-testing:SwiftMTPTests/MTPEncodingTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Port all remaining MTP/PTP constants from Go's `const.go`**

The `MTPConstants.swift` shown in Step 3 contains only the ~14 constants needed by the initial tests. Before committing, port all remaining operation codes, response codes, object format codes, object property codes, and device property codes from `Native/vendor/go-mtpfs/mtp/const.go` (~1,974 lines). Cross-reference against `constants_reference.json` to catch typos; if Go's value disagrees with the PIMA 15740 spec, **the spec wins**.

Run the extended constants test:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPConstantsTests
```

After verifying, delete the migration-only reference file:

```bash
rm SwiftMTPTests/MTPCore/Snapshots/constants_reference.json
```

- [ ] **Step 6: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPProtocol/MTPConstants.swift SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift SwiftMTPTests/MTPCore/MTPConstantsTests.swift SwiftMTPTests/MTPCore/MTPContainerTests.swift SwiftMTPTests/MTPCore/MTPEncodingTests.swift
git add -u SwiftMTPTests/MTPCore/Snapshots/constants_reference.json
git commit -m "feat(mtpcore): add protocol primitives with full constants"
```

### Task 4: Expand Spec-Derived Types and Fixture Decoding

**Files:**

- Modify: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift`
- Modify: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift`
- Create: `SwiftMTPTests/MTPCore/MTPTypeDecodingTests.swift`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/device_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/storage_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/object_info.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/object_handles.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_access_denied.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_store_full.bin`
- Create: `SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_invalid_handle.bin`
- [ ] **Step 1: Write failing decode tests for the first real structs**

```swift
import XCTest
@testable import SwiftMTP

final class MTPTypeDecodingTests: XCTestCase {
    func testDecodeObjectHandlesFixture() throws {
        let data = try FixtureLoader.data(named: "object_handles.bin")
        var reader = MTPDataReader(data: data)
        let handles = try reader.readUInt32Array()
        XCTAssertEqual(handles, [1, 2, 42])
    }

    func testDecodeDeviceInfoFixture() throws {
        let data = try FixtureLoader.data(named: "device_info.bin")
        var reader = MTPDataReader(data: data)
        let info = try MTPDeviceInfo(from: &reader)
        XCTAssertEqual(info.manufacturer, "SwiftMTP")
        XCTAssertEqual(info.model, "Fixture Phone")
    }

    func testDecodeStorageInfoFixture() throws {
        let data = try FixtureLoader.data(named: "storage_info.bin")
        var reader = MTPDataReader(data: data)
        let info = try MTPStorageInfo(from: &reader)
        XCTAssertEqual(info.maxCapacity, 4096)
        XCTAssertEqual(info.freeSpaceBytes, 2048)
        XCTAssertEqual(info.description, "Internal")
    }

    func testDecodeObjectInfoFixture() throws {
        let data = try FixtureLoader.data(named: "object_info.bin")
        var reader = MTPDataReader(data: data)
        let info = try MTPObjectInfo(from: &reader)
        XCTAssertEqual(info.storageID, 1)
        XCTAssertEqual(info.objectFormat, 0x3801)
        XCTAssertEqual(info.objectCompressedSize, 42)
        XCTAssertEqual(info.parentObject, UInt32.max)
        XCTAssertEqual(info.filename, "IMG_001.jpg")
    }
}
```

- [ ] **Step 2: Run the tests to prove the array and struct decoders do not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPTypeDecodingTests
```

Expected: build fails because the array-decoding helpers and `MTPDeviceInfo` are still undefined.

- [ ] **Step 3: Add array decoding, MTP string decoding, and the core protocol structs**

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift`

```swift
struct MTPDeviceInfo: Equatable {
    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let mtpVersionRaw: UInt16
    let manufacturer: String
    let model: String
    let serialNumber: String
    let deviceVersion: String
    let vendorExtensionDesc: String

    var mtpVersion: String {
        let major = mtpVersionRaw / 100
        let minor = (mtpVersionRaw % 100) / 10
        return "\(major).\(minor)"
    }

    /// Decode from MTP binary data using the same logical layout the current
    /// Go-backed app consumes from `go-mtpfs/mtp.DeviceInfo`.
    ///
    /// Preserve the existing app's user-visible values first. If real-device
    /// smoke tests later prove that the Go layout mapping is incomplete for a
    /// specific device family, fix the decoder with source evidence rather than
    /// inventing an alternate field order ad hoc.
    init(from reader: inout MTPDataReader) throws {
        standardVersion = try reader.readUInt16()
        vendorExtensionID = try reader.readUInt32()
        mtpVersionRaw = try reader.readUInt16()
        vendorExtensionDesc = try reader.readMTPString()
        _ = try reader.readUInt16()                              // functionalMode
        let _supportedOperations = try reader.readUInt16Array()  // operationsSupported
        let _supportedEvents = try reader.readUInt16Array()      // eventsSupported
        let _supportedProperties = try reader.readUInt16Array()  // devicePropertiesSupported
        let _captureFormats = try reader.readUInt16Array()       // captureFormats
        let _playbackFormats = try reader.readUInt16Array()      // playbackFormats
        manufacturer = try reader.readMTPString()
        model = try reader.readMTPString()
        deviceVersion = try reader.readMTPString()
        serialNumber = try reader.readMTPString()
    }
}

struct MTPStorageInfo: Equatable {
    let storageType: UInt16
    let fileSystemType: UInt16
    let accessCapability: UInt16
    let maxCapacity: UInt64
    let freeSpaceBytes: UInt64
    let description: String

    init(from reader: inout MTPDataReader) throws {
        storageType = try reader.readUInt16()
        fileSystemType = try reader.readUInt16()
        accessCapability = try reader.readUInt16()
        maxCapacity = try reader.readUInt64()
        freeSpaceBytes = try reader.readUInt64()
        _ = try reader.readUInt32()
        description = try reader.readMTPString()
        _ = try reader.readMTPString()
    }
}

struct MTPObjectInfo: Equatable {
    /// The object handle assigned by the device. **Not part of the PIMA 15740 ObjectInfo
    /// datasource** — when decoded via `init(from reader:)`, this is always 0. The caller
    /// (e.g., `performSendObjectInfo`) must set it from the MTP response parameters.
    let objectHandle: UInt32
    let storageID: UInt32
    let objectFormat: UInt16
    let parentObject: UInt32
    let objectCompressedSize: UInt64  // Mirrors Go's two-step size semantics: this holds the ObjectInfo field unless `needsObjectSizeLookup` says to fetch OPC_ObjectSize first.
    let needsObjectSizeLookup: Bool   // `true` when ObjectInfo reported 0xffffffff; non-directory callers must resolve the real 64-bit size via GetObjectPropValue(OPC_ObjectSize).
    let filename: String
    let captureDate: String
    let modificationDate: String

    init(objectHandle: UInt32 = 0, storageID: UInt32, objectFormat: UInt16, parentObject: UInt32, objectCompressedSize: UInt64, needsObjectSizeLookup: Bool = false, filename: String, captureDate: String = "", modificationDate: String = "") {
        self.objectHandle = objectHandle
        self.storageID = storageID
        self.objectFormat = objectFormat
        self.parentObject = parentObject
        self.objectCompressedSize = objectCompressedSize
        self.needsObjectSizeLookup = needsObjectSizeLookup
        self.filename = filename
        self.captureDate = captureDate
        self.modificationDate = modificationDate
    }

    func resolvingObjectCompressedSize(_ resolvedSize: UInt64) -> MTPObjectInfo {
        MTPObjectInfo(
            objectHandle: objectHandle,
            storageID: storageID,
            objectFormat: objectFormat,
            parentObject: parentObject,
            objectCompressedSize: resolvedSize,
            needsObjectSizeLookup: false,
            filename: filename,
            captureDate: captureDate,
            modificationDate: modificationDate
        )
    }

    // PIMA 15740 §4.3.2 ObjectInfo Datasource
    init(from reader: inout MTPDataReader) throws {
        storageID = try reader.readUInt32()        // StorageID
        objectFormat = try reader.readUInt16()     // ObjectFormat
        _ = try reader.readUInt16()                // ProtectionStatus
        let rawCompressedSize = try reader.readUInt32()
        objectCompressedSize = UInt64(rawCompressedSize)
        needsObjectSizeLookup = rawCompressedSize == UInt32.max
        _ = try reader.readUInt16()                // ThumbFormat
        _ = try reader.readUInt32()                // ThumbCompressedSize
        _ = try reader.readUInt32()                // ThumbPixWidth
        _ = try reader.readUInt32()                // ThumbPixHeight
        _ = try reader.readUInt32()                // ImagePixWidth
        _ = try reader.readUInt32()                // ImagePixHeight
        _ = try reader.readUInt32()                // ImageBitDepth
        parentObject = try reader.readUInt32()     // ParentObject
        _ = try reader.readUInt16()                // AssociationType
        _ = try reader.readUInt32()                // AssociationDesc
        _ = try reader.readUInt32()                // SequenceNumber
        filename = try reader.readMTPString()      // Filename
        captureDate = try reader.readMTPString()   // CaptureDate
        modificationDate = try reader.readMTPString() // ModificationDate
        _ = try reader.readMTPString()             // Keywords
    }
}
```

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift`

```swift
extension MTPDataReader {
    mutating func readUInt16Array() throws -> [UInt16] {
        let count = Int(try readUInt32())
        return try (0..<count).map { _ in try readUInt16() }
    }

    mutating func readUInt32Array() throws -> [UInt32] {
        let count = Int(try readUInt32())
        return try (0..<count).map { _ in try readUInt32() }
    }

    mutating func readUInt64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw CocoaError(.coderReadCorrupt) }
        // Manual byte assembly avoids `load(as:)` alignment UB on arbitrary Data offsets.
        let b = data
        let value = UInt64(b[offset])
            | (UInt64(b[offset + 1]) << 8)
            | (UInt64(b[offset + 2]) << 16)
            | (UInt64(b[offset + 3]) << 24)
            | (UInt64(b[offset + 4]) << 32)
            | (UInt64(b[offset + 5]) << 40)
            | (UInt64(b[offset + 6]) << 48)
            | (UInt64(b[offset + 7]) << 56)
        offset += 8
        return value
    }

    mutating func readMTPString() throws -> String {
        let count = Int(try readUInt8())
        guard count > 0 else { return "" }
        var scalars: [UInt16] = []
        for _ in 0..<(count - 1) {
            scalars.append(try readUInt16())
        }
        _ = try readUInt16()
        return String(decoding: scalars, as: UTF16.self)
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw CocoaError(.coderReadCorrupt) }
        let value = data[offset]
        offset += 1
        return value
    }
}
```

- [ ] **Step 4: Check in concrete binary fixtures**

Run:

```bash
mkdir -p SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses
printf '0300000001000000020000002a000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/object_handles.bin
printf '640006000000640000000002000000011002100000000000000000000000000000000009530077006900660074004d005400500000000e46006900780074007500720065002000500068006f006e006500000002310000000653004e003100320033000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/device_info.bin
printf '03000200000000100000000000000008000000000000000000000949006e007400650072006e0061006c00000006500068006f006e0065000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/storage_info.bin
printf '01000000013800002a00000000000000000000000000000000000000000000000000ffffffff000000000000000000000c49004d0047005f003000300031002e006a00700067000000000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/object_info.bin
printf '0c00000003000f2001000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_access_denied.bin
printf '0c00000003000c2001000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_store_full.bin
printf '0c0000000300092001000000' | xxd -r -p > SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_invalid_handle.bin
```

**Verify fixture integrity** — confirm the hex decoding produced the expected byte count:

```bash
wc -c SwiftMTPTests/MTPCore/Fixtures/Protocol/object_handles.bin        # expect 16
wc -c SwiftMTPTests/MTPCore/Fixtures/Protocol/device_info.bin           # expect 101
wc -c SwiftMTPTests/MTPCore/Fixtures/Protocol/storage_info.bin          # expect 58
wc -c SwiftMTPTests/MTPCore/Fixtures/Protocol/object_info.bin           # expect 76
wc -c SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/*.bin     # expect 12 each
```

If any byte count is wrong, the shell hex encoding was corrupted — regenerate that fixture.

- [ ] **Step 5: Re-run the type decoding tests**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPTypeDecodingTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPProtocol/MTPTypes.swift SwiftMTP/Services/MTPCore/MTPProtocol/MTPEncoding.swift SwiftMTPTests/MTPCore/MTPTypeDecodingTests.swift SwiftMTPTests/MTPCore/Fixtures/Protocol/device_info.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/storage_info.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/object_info.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/object_handles.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_access_denied.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_store_full.bin SwiftMTPTests/MTPCore/Fixtures/Protocol/error_responses/response_invalid_handle.bin
git commit -m "feat(mtpcore): add protocol struct decoding"
```

### Task 5: Add USB Transport, Debug Logging, and Device Scanning

**Files:**

- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`
- Create: `SwiftMTP/Services/MTPCore/USBTransport/USBDevice.swift`
- Create: `SwiftMTP/Services/MTPCore/USBTransport/USBDebugLogger.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceScanner.swift`
- Create: `SwiftMTPTests/MTPCore/Support/MockUSBTransport.swift`
- Create: `SwiftMTPTests/MTPCore/MTPDeviceScannerTests.swift`
- Create: `SwiftMTPTests/MTPCore/ManualRealDeviceSmokeTests.swift`
- [ ] **Step 0: Add MTPError (required by LibUSBTransport and future tasks)**

`SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`

```swift
import Foundation

enum MTPError: Error, LocalizedError, Equatable {
    case usbTransferFailed(Int32)
    case invalidResponse
    case accessDenied
    case storeFull
    case sessionAlreadyOpened
    case cancelled
    case poolShutdown
    case deviceError(String)
    case connectionError(String)
    case timeout(String)
    case deviceNotFound(String)
    case usbError(String)
    case deviceBusy(String)
    case deviceClosed(String)
    case nonRecoverable(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: return String(localized: "mtp.error.accessDenied", defaultValue: "Access denied")
        case .storeFull: return String(localized: "mtp.error.storeFull", defaultValue: "Storage is full")
        case .sessionAlreadyOpened: return String(localized: "mtp.error.sessionAlreadyOpened", defaultValue: "MTP session already open")
        case .cancelled: return String(localized: "mtp.error.cancelled", defaultValue: "Operation cancelled")
        case .poolShutdown: return String(localized: "mtp.error.poolShutdown", defaultValue: "Connection pool has shut down")
        case .invalidResponse: return String(localized: "mtp.error.invalidResponse", defaultValue: "Invalid device response")
        case let .usbTransferFailed(code): return String(localized: "mtp.error.usbTransferFailed \(code)", defaultValue: "USB transfer failed: \(code)")
        case let .deviceError(message),
             let .connectionError(message),
             let .timeout(message),
             let .deviceNotFound(message),
             let .usbError(message),
             let .deviceBusy(message),
             let .deviceClosed(message),
             let .nonRecoverable(message):
            return message
        }
    }
}
```

- [ ] **Step 1: Write the failing scanner tests**

```swift
import XCTest
@testable import SwiftMTP

final class MTPDeviceScannerTests: XCTestCase {
    func testScannerReturnsOnlyEndpointCompatibleCandidates() throws {
        let transport = MockUSBTransport(
            devices: [
                .fixture(vendorID: 0x18D1, productID: 0x4EE1, interfaceClass: 6, interfaceSubClass: 1, interfaceProtocol: 1),
                USBScannedDevice(
                    identity: USBDeviceIdentity(vendorID: 0x05AC, productID: 0x12A8, busNumber: 1, address: 2),
                    interfaceNumber: 0,
                    interfaceClass: 8,
                    interfaceSubClass: 6,
                    interfaceProtocol: 80,
                    configurationValue: 1,
                    interfaceStringIndex: 4,
                    sendMaxPacketSize: 512,
                    fetchMaxPacketSize: 512,
                    endpoints: USBEndpoints(sendEP: 0x01, fetchEP: 0x81, eventEP: 0x00)
                )
            ]
        )
        let scanner = MTPDeviceScanner(transport: transport)
        let devices = try scanner.scan()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].identity.vendorID, 0x18D1)
    }
}
```

- [ ] **Step 2: Run the scanner test to prove the transport layer does not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceScannerTests
```

Expected: build fails because `MockUSBTransport` and `MTPDeviceScanner` are undefined.

- [ ] **Step 3: Add opaque USB types, the transport protocol, the real transport, and the scanner**

`SwiftMTP/Services/MTPCore/USBTransport/USBDevice.swift`

```swift
import Foundation
import CLibUSB

struct USBDeviceIdentity: Hashable, Sendable {
    let vendorID: UInt16
    let productID: UInt16
    let busNumber: UInt8
    let address: UInt8
}

/// Discovered endpoints from USB interface descriptor.
/// MTP devices expose exactly 3 endpoints (2 bulk + 1 interrupt), discovered dynamically.
struct USBEndpoints: Equatable, Sendable {
    let sendEP: UInt8   // bulk OUT — commands and data TO device
    let fetchEP: UInt8  // bulk IN — responses and data FROM device
    let eventEP: UInt8  // interrupt IN — async events
}

struct USBScannedDevice: Equatable, Sendable {
    let identity: USBDeviceIdentity
    let interfaceNumber: Int32
    let interfaceClass: UInt8
    let interfaceSubClass: UInt8
    let interfaceProtocol: UInt8
    let configurationValue: UInt8
    let interfaceStringIndex: UInt8
    let sendMaxPacketSize: Int
    let fetchMaxPacketSize: Int
    let endpoints: USBEndpoints
}

struct USBHandleRef: @unchecked Sendable {
    let context: OpaquePointer?
    let handle: OpaquePointer?
    let interfaceNumber: Int32
    let configurationValue: UInt8
    let interfaceStringIndex: UInt8
    let sendMaxPacketSize: Int
    let fetchMaxPacketSize: Int
    let endpoints: USBEndpoints

    var sendEP: UInt8 { endpoints.sendEP }
    var fetchEP: UInt8 { endpoints.fetchEP }
    var eventEP: UInt8 { endpoints.eventEP }
}

protocol USBTransport: Sendable {
    func scanDevices() throws -> [USBScannedDevice]
    func open(_ device: USBScannedDevice) throws -> USBHandleRef
    func close(_ handle: USBHandleRef)
    func reset(_ handle: USBHandleRef) throws
    func readStringDescriptor(handle: USBHandleRef, index: UInt8) throws -> String
    func writeBulkPacket(handle: USBHandleRef, endpoint: UInt8, data: Data, timeout: Int) throws
    func readBulkPacket(handle: USBHandleRef, endpoint: UInt8, maxLength: Int, timeout: Int) throws -> Data
}

final class LibUSBTransport: USBTransport {
    /// Design note: libusb context lifecycle
    ///
    /// Each method creates its own `libusb_context` via `libusb_init` / `libusb_exit`.
    /// This is intentional:
    /// 1. `scanDevices()` enumerates all USB devices — it needs a context only during the scan.
    /// 2. `open(_:)` creates a long-lived context stored in `USBHandleRef`, released by `close()`.
    /// 3. The `scanDevices()` context is destroyed before `open()` runs, so `open()` re-enumerates
    ///    devices in its own context and matches by bus number + address (not by stale pointers).
    ///
    /// `libusb_init`/`libusb_exit` are lightweight (~microseconds). Sharing a single context
    /// across all operations would add thread-safety complexity without measurable performance gain
    /// for a desktop app that talks to at most 1-3 USB devices.

    func scanDevices() throws -> [USBScannedDevice] {
        var context: OpaquePointer?
        guard libusb_init(&context) == 0 else { throw MTPError.usbTransferFailed(-1) }
        defer { libusb_exit(context) }

        var deviceList: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(context, &deviceList)
        guard count >= 0, let deviceList else { throw MTPError.usbTransferFailed(Int32(count)) }
        defer { libusb_free_device_list(deviceList, 1) }

        var matches: [USBScannedDevice] = []

        for index in 0..<Int(count) {
            guard let device = deviceList[index] else { continue }

            var descriptor = libusb_device_descriptor()
            guard libusb_get_device_descriptor(device, &descriptor) == 0 else { continue }

            // Match go-mtpfs/select.go: inspect every configuration, not just the active one.
            // Candidate selection is endpoint-topology based, not class-code based.
            // The current Go stack first finds interfaces that expose the expected
            // bulk OUT + bulk IN + interrupt IN shape, then validates MTP compatibility
            // later during `Open()` via interface-string / MTPExtension checks.
            for configIndex in 0..<Int(descriptor.bNumConfigurations) {
                var configPointer: UnsafeMutablePointer<libusb_config_descriptor>?
                guard libusb_get_config_descriptor(device, UInt8(configIndex), &configPointer) == 0, let configPointer else { continue }
                defer { libusb_free_config_descriptor(configPointer) }

                let config = configPointer.pointee
                for interfaceIndex in 0..<Int(config.bNumInterfaces) {
                    let interface = config.interface[interfaceIndex]
                    for altIndex in 0..<Int(interface.num_altsetting) {
                        let alt = interface.altsetting[altIndex]

                        // Discover endpoints from interface descriptor (matches go-mtpfs/mtp/select.go)
                        var sendEP: UInt8 = 0, fetchEP: UInt8 = 0, eventEP: UInt8 = 0
                        var sendMaxPacketSize = 512
                        var fetchMaxPacketSize = 512
                        for epIndex in 0..<Int(alt.bNumEndpoints) {
                            let ep = alt.endpoint[epIndex]
                            let isIn = ep.bEndpointAddress & 0x80 != 0
                            let transferType = ep.bmAttributes & 0x03
                            switch (isIn, transferType) {
                            case (true, 3):
                                eventEP = ep.bEndpointAddress  // interrupt IN
                            case (true, 2):
                                fetchEP = ep.bEndpointAddress  // bulk IN
                                fetchMaxPacketSize = max(Int(ep.wMaxPacketSize), 512)
                            case (false, 2):
                                sendEP = ep.bEndpointAddress   // bulk OUT
                                sendMaxPacketSize = max(Int(ep.wMaxPacketSize), 512)
                            default:
                                break
                            }
                        }
                        guard sendEP > 0, fetchEP > 0, eventEP > 0 else { continue }

                        matches.append(
                            USBScannedDevice(
                                identity: USBDeviceIdentity(
                                    vendorID: descriptor.idVendor,
                                    productID: descriptor.idProduct,
                                    busNumber: libusb_get_bus_number(device),
                                    address: libusb_get_device_address(device)
                                ),
                                interfaceNumber: Int32(alt.bInterfaceNumber),
                                interfaceClass: alt.bInterfaceClass,
                                interfaceSubClass: alt.bInterfaceSubClass,
                                interfaceProtocol: alt.bInterfaceProtocol,
                                configurationValue: config.bConfigurationValue,
                                interfaceStringIndex: alt.iInterface,
                                sendMaxPacketSize: sendMaxPacketSize,
                                fetchMaxPacketSize: fetchMaxPacketSize,
                                endpoints: USBEndpoints(sendEP: sendEP, fetchEP: fetchEP, eventEP: eventEP)
                            )
                        )
                    }
                }
            }
        }

        return matches
    }

    func open(_ device: USBScannedDevice) throws -> USBHandleRef {
        var context: OpaquePointer?
        guard libusb_init(&context) == 0 else { throw MTPError.usbTransferFailed(-1) }

        // Find the exact device by bus number + address (not just VID/PID)
        // This correctly handles multiple identical devices on the same bus.
        var deviceList: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(context, &deviceList)
        guard count >= 0, let deviceList else {
            libusb_exit(context)
            throw MTPError.usbTransferFailed(Int32(count))
        }
        defer { libusb_free_device_list(deviceList, 1) }

        var matchedDevice: OpaquePointer?
        for index in 0..<Int(count) {
            guard let candidate = deviceList[index] else { continue }
            if libusb_get_bus_number(candidate) == device.identity.busNumber &&
               libusb_get_device_address(candidate) == device.identity.address {
                matchedDevice = candidate
                break
            }
        }

        guard let matchedDevice else {
            libusb_exit(context)
            throw MTPError.deviceNotFound("device not found at bus \(device.identity.busNumber) address \(device.identity.address)")
        }

        var rawHandle: OpaquePointer?
        let openResult = libusb_open(matchedDevice, &rawHandle)
        guard openResult == 0, let handle = rawHandle else {
            libusb_exit(context)
            throw MTPError.usbTransferFailed(openResult)
        }

        var currentConfiguration: Int32 = 0
        let getConfigurationResult = libusb_get_configuration(handle, &currentConfiguration)
        guard getConfigurationResult == 0 else {
            libusb_close(handle)
            libusb_exit(context)
            throw MTPError.usbTransferFailed(Int32(getConfigurationResult))
        }
        if UInt8(currentConfiguration) != device.configurationValue {
            let setConfigurationResult = libusb_set_configuration(handle, Int32(device.configurationValue))
            guard setConfigurationResult == 0 else {
                libusb_close(handle)
                libusb_exit(context)
                throw MTPError.usbTransferFailed(Int32(setConfigurationResult))
            }
        }

        let claimResult = libusb_claim_interface(handle, device.interfaceNumber)
        guard claimResult == 0 else {
            libusb_close(handle)
            libusb_exit(context)
            throw MTPError.usbTransferFailed(Int32(claimResult))
        }

        // Match go-mtpfs/Open(): validate the interface string before considering the
        // transport healthy when one is present. If the descriptor omits iInterface,
        // Task 6's MTPDevice transport validation must fall back to MTPExtension from
        // GetDeviceInfo before the session is considered usable.
        let openedHandle = USBHandleRef(
            context: context,
            handle: handle,
            interfaceNumber: device.interfaceNumber,
            configurationValue: device.configurationValue,
            interfaceStringIndex: device.interfaceStringIndex,
            sendMaxPacketSize: device.sendMaxPacketSize,
            fetchMaxPacketSize: device.fetchMaxPacketSize,
            endpoints: device.endpoints
        )
        if device.interfaceStringIndex != 0 {
            let interfaceName = try readStringDescriptor(handle: openedHandle, index: device.interfaceStringIndex)
            let normalized = interfaceName.lowercased()
            guard normalized.contains("mtp") || normalized.contains("cdc") || normalized.contains("acm") else {
                libusb_release_interface(handle, device.interfaceNumber)
                libusb_close(handle)
                libusb_exit(context)
                throw MTPError.usbError("interface string does not advertise MTP compatibility: \(interfaceName)")
            }
        }

        return openedHandle
    }

    func close(_ handle: USBHandleRef) {
        libusb_release_interface(handle.handle, handle.interfaceNumber)
        libusb_close(handle.handle)
        libusb_exit(handle.context)
    }

    func reset(_ handle: USBHandleRef) throws {
        let result = libusb_reset_device(handle.handle)
        guard result == 0 else { throw MTPError.usbTransferFailed(Int32(result)) }
    }

    func readStringDescriptor(handle: USBHandleRef, index: UInt8) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = libusb_get_string_descriptor_ascii(handle.handle, index, &bytes, Int32(bytes.count))
        guard count > 0 else { throw MTPError.usbTransferFailed(Int32(count)) }
        return String(decoding: bytes.prefix(Int(count)), as: UTF8.self)
    }

    func writeBulkPacket(handle: USBHandleRef, endpoint: UInt8, data: Data, timeout: Int) throws {
        var bytes = [UInt8](data)
        var totalTransferred = 0
        while totalTransferred < bytes.count {
            var transferred: Int32 = 0
            let remaining = Array(bytes[totalTransferred...])
            let result = libusb_bulk_transfer(
                handle.handle,
                endpoint,
                UnsafeMutablePointer(mutating: remaining),
                Int32(remaining.count),
                &transferred,
                UInt32(timeout)
            )
            guard result == 0 else { throw MTPError.usbTransferFailed(Int32(result)) }
            totalTransferred += Int(transferred)
        }
    }

    func readBulkPacket(handle: USBHandleRef, endpoint: UInt8, maxLength: Int, timeout: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: maxLength)
        var transferred: Int32 = 0
        let result = libusb_bulk_transfer(
            handle.handle,
            endpoint,
            &bytes,
            Int32(maxLength),
            &transferred,
            UInt32(timeout)
        )
        guard result == 0 else { throw MTPError.usbTransferFailed(Int32(result)) }
        return Data(bytes.prefix(Int(transferred)))
    }
}
```

`SwiftMTP/Services/MTPCore/USBTransport/USBDebugLogger.swift`

```swift
import OSLog

enum USBDebugLogger {
    private static let logger = Logger(subsystem: "com.AlanWang.SwiftMTP", category: "USB")

    static func logScan(vendorID: UInt16, productID: UInt16, interfaceClass: UInt8) {
        logger.debug("scan vid=\(vendorID, format: .hex, privacy: .public) pid=\(productID, format: .hex, privacy: .public) class=\(interfaceClass)")
    }

    static func logTransfer(endpoint: UInt8, length: Int) {
        logger.debug("bulk endpoint=\(endpoint, format: .hex, privacy: .public) length=\(length, privacy: .public)")
    }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceScanner.swift`

```swift
struct MTPDeviceScanner {
    private let transport: any USBTransport

    init(transport: any USBTransport) {
        self.transport = transport
    }

    func scan() throws -> [USBScannedDevice] {
        // Keep the mock-path contract aligned with the real transport:
        // a scan candidate must expose the expected endpoint topology.
        // Do NOT hard-filter on interface class/subclass/protocol here; Go only
        // enforces MTP compatibility later during open/session validation.
        try transport.scanDevices().filter {
            $0.endpoints.sendEP > 0 &&
            $0.endpoints.fetchEP > 0 &&
            $0.endpoints.eventEP > 0
        }
    }
}
```

`SwiftMTPTests/MTPCore/Support/MockUSBTransport.swift`

```swift
import Foundation
@testable import SwiftMTP

final class MockUSBTransport: USBTransport, @unchecked Sendable {
    // @unchecked Sendable: mutable state (responses, writtenPackets, openCount, closeCount)
    // accessed from the test's single-threaded XCTest run. If tests become concurrent,
    // add synchronization here.
    let devices: [USBScannedDevice]
    var responses: [Data]
    private(set) var writtenPackets: [Data] = []
    private(set) var openCount: Int = 0
    private(set) var closeCount: Int = 0
    private(set) var resetCount: Int = 0

    init(devices: [USBScannedDevice] = [], responses: [Data] = []) {
        self.devices = devices
        self.responses = responses
    }

    func scanDevices() throws -> [USBScannedDevice] {
        devices
    }

    func open(_ device: USBScannedDevice) throws -> USBHandleRef {
        openCount += 1
        USBHandleRef(
            context: nil,
            handle: nil,
            interfaceNumber: device.interfaceNumber,
            configurationValue: device.configurationValue,
            interfaceStringIndex: device.interfaceStringIndex,
            sendMaxPacketSize: device.sendMaxPacketSize,
            fetchMaxPacketSize: device.fetchMaxPacketSize,
            endpoints: device.endpoints
        )
    }

    func close(_ handle: USBHandleRef) {
        closeCount += 1
    }

    func reset(_ handle: USBHandleRef) throws {
        resetCount += 1
    }

    func readStringDescriptor(handle: USBHandleRef, index: UInt8) throws -> String {
        "MTP"
    }

    func writeBulkPacket(handle: USBHandleRef, endpoint: UInt8, data: Data, timeout: Int) throws {
        writtenPackets.append(data)
    }

    func readBulkPacket(handle: USBHandleRef, endpoint: UInt8, maxLength: Int, timeout: Int) throws -> Data {
        guard !responses.isEmpty else { return Data() }
        return responses.removeFirst()
    }
}

extension USBScannedDevice {
    static func fixture(vendorID: UInt16, productID: UInt16, busNumber: UInt8 = 1, address: UInt8 = 1, interfaceNumber: Int32 = 0, configurationValue: UInt8 = 1, interfaceStringIndex: UInt8 = 4, sendMaxPacketSize: Int = 512, fetchMaxPacketSize: Int = 512, interfaceClass: UInt8, interfaceSubClass: UInt8, interfaceProtocol: UInt8) -> USBScannedDevice {
        USBScannedDevice(
            identity: USBDeviceIdentity(vendorID: vendorID, productID: productID, busNumber: busNumber, address: address),
            interfaceNumber: interfaceNumber,
            interfaceClass: interfaceClass,
            interfaceSubClass: interfaceSubClass,
            interfaceProtocol: interfaceProtocol,
            configurationValue: configurationValue,
            interfaceStringIndex: interfaceStringIndex,
            sendMaxPacketSize: sendMaxPacketSize,
            fetchMaxPacketSize: fetchMaxPacketSize,
            endpoints: USBEndpoints(sendEP: 0x01, fetchEP: 0x81, eventEP: 0x82)
        )
    }
}
```

- [ ] **Step 4: Add the real-device smoke test and document fixture scope honestly**

`SwiftMTPTests/MTPCore/ManualRealDeviceSmokeTests.swift`

```swift
import XCTest
@testable import SwiftMTP

final class ManualRealDeviceSmokeTests: XCTestCase {
    func testScanDetectsRealDevice() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ENABLE_REAL_DEVICE_TESTS"] == "1")
        let transport = LibUSBTransport()
        let devices = try MTPDeviceScanner(transport: transport).scan()
        XCTAssertFalse(devices.isEmpty)

        let handle = try transport.open(devices[0])
        transport.close(handle)
    }
}
```

Run mock test:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceScannerTests
```

Run real-device smoke test:

```bash
ENABLE_REAL_DEVICE_TESTS=1 xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/ManualRealDeviceSmokeTests
```

Expected: mock suite passes; real-device smoke passes with an Android device attached and fails fast if nothing is connected.

**Fixture scope note (authoritative):** The hand-crafted hex fixtures in Tasks 2-4 are synthetic, spec-derived unit fixtures. They are for deterministic decoding coverage only and are **not** hardware-captured or hardware-validated in this migration plan. Real-device confidence for the migration comes from the smoke checks in Tasks 5, 8, and 11, not from claiming byte-level fixture parity with a phone.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift SwiftMTP/Services/MTPCore/USBTransport/USBDevice.swift SwiftMTP/Services/MTPCore/USBTransport/USBDebugLogger.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceScanner.swift SwiftMTPTests/MTPCore/Support/MockUSBTransport.swift SwiftMTPTests/MTPCore/MTPDeviceScannerTests.swift SwiftMTPTests/MTPCore/ManualRealDeviceSmokeTests.swift
git commit -m "feat(mtpcore): add usb transport and device scan"
```

### Task 6: Implement MTP Device Sessions and Core Transactions

**Files:**

- Modify: `SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Operations.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Download.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPProtocol/MTPDebugLogger.swift`
- Test: `SwiftMTPTests/MTPCore/MTPDeviceTests.swift`
- Test: `SwiftMTPTests/MTPCore/ErrorPathTests.swift`
- [ ] **Step 1: Write the first failing transaction tests**

```swift
import XCTest
@testable import SwiftMTP

final class MTPDeviceTests: XCTestCase {
    func testOpenSessionSendsExpectedCommand() async throws {
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [try FixtureLoader.data(named: "container_response_ok.bin")]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)
        // Command container: length=16, type=1(cmd), code=0x1002, txID=0, param=1
        XCTAssertEqual(transport.writtenPackets.first, Data([0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x10, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
    }
}
```

- [ ] **Step 2: Run the test to prove the device layer does not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceTests
```

Expected: build fails because `MTPDevice` is undefined.

- [ ] **Step 3: Add the minimal transaction engine**

`SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`

```swift
extension MTPError {
    // Task 6 is the first consumer of response-code mapping and retry classification.
    // Task 8 expands this into the full pool/error taxonomy, but these minimal helpers
    // must exist here so MTPDevice.swift does not reference symbols introduced later.
    static func from(responseCode: UInt16) -> MTPError {
        switch responseCode {
        case MTPConstants.RC_AccessDenied: return .accessDenied
        case MTPConstants.RC_StoreFull: return .storeFull
        case MTPConstants.RC_SessionAlreadyOpened: return .sessionAlreadyOpened
        case MTPConstants.RC_InvalidObjectHandle: return .deviceError("Invalid object handle")
        default: return .deviceError("MTP response error: 0x\(String(responseCode, radix: 16))")
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .connectionError, .timeout, .deviceBusy, .deviceClosed, .usbError, .deviceNotFound:
            return true
        default:
            return false
        }
    }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice.swift`

```swift
import Foundation

/// Thread safety: MTPDevice instances are NOT thread-safe. The pool guarantees
/// exclusive access — a given instance is never used concurrently by two operations.
/// Do not call methods on an MTPDevice outside of a `withDevice` / `withDeviceSync` block.
/// `@unchecked Sendable` is safe because `MTPDevicePool` enforces per-device exclusivity
/// via `inUseIdentities` — no two operations ever call methods on the same instance concurrently.
final class MTPDevice: @unchecked Sendable {
    private let transport: any USBTransport
    private let scannedDevice: USBScannedDevice
    private var transactionID: UInt32 = 0
    private var handle: USBHandleRef?
    private var sessionID: UInt32?
    private var transportValidated = false
    private var separateDataHeader = false

    init(transport: any USBTransport, scannedDevice: USBScannedDevice) {
        self.transport = transport
        self.scannedDevice = scannedDevice
    }

    deinit {
        // libusb_release_interface / libusb_close / libusb_exit are safe to call
        // from any thread because MTPDevicePool.evictEntry() calls closeSession()
        // on the actor's serial executor before releasing the last strong reference.
        // When deinit fires, the device is no longer in the pool's entries dict,
        // so no concurrent pool operation can access this instance.
        if let handle {
            transport.close(handle)
        }
    }

    func openSession(sessionID: UInt32) async throws {
        // Match the current Go stack's real semantics: mtpx.Initialize() ends in
        // dev.Configure(), which first tries OpenSession, treats RC_SessionAlreadyOpened
        // as a stale logical session, sends CloseSession, retries OpenSession, and only
        // then falls back to USB reset / close / re-open if bring-up still fails.
        try await ensureTransportValidated()

        do {
            try await openSessionOnce(sessionID: sessionID)
            markSessionOpened(sessionID)
        } catch let error as MTPError where error == .sessionAlreadyOpened {
            try await closeStaleSessionForRecovery()
            do {
                try await openSessionOnce(sessionID: sessionID)
                markSessionOpened(sessionID)
            } catch {
                try await recoverAndReopenSession(sessionID: sessionID, originalError: error)
            }
        } catch let error as MTPError where error.isRecoverable {
            try await recoverAndReopenSession(sessionID: sessionID, originalError: error)
        } catch {
            try await recoverAndReopenSession(sessionID: sessionID, originalError: error)
        }
    }

    func closeSession() async throws {
        guard sessionID != nil else { return }
        var closeError: Error?
        do {
            _ = try await runTransactionRaw(
                code: MTPConstants.OC_CloseSession,
                parameters: []
            )
        } catch {
            closeError = error
            if let handle {
                // Match go-mtpfs Close(): if CloseSession itself fails, reset the USB
                // handle before closing so quick relaunches do not hit "device busy".
                try? transport.reset(handle)
            }
        }
        self.sessionID = nil
        self.transportValidated = false
        if let handle {
            transport.close(handle)
            self.handle = nil
        }
        if let closeError {
            throw closeError
        }
    }

    // MARK: - Transaction Engine (matches go-mtpfs runTransaction flow)

    /// Command-only transaction: CMD → RESP
    func runCommand(code: UInt16, parameters: [UInt32] = []) async throws -> MTPResponse {
        let raw = try await runTransactionRaw(code: code, parameters: parameters)
        return try parseResponse(raw)
    }

    /// Data-returning transaction: CMD → DATA → RESP
    func runCommandReturningData(code: UInt16, parameters: [UInt32] = []) async throws -> Data {
        let currentTxID = nextTransactionID()
        try sendCommandContainer(code: code, parameters: parameters, txID: currentTxID)

        // Read first packet from fetchEP — could be DATA or RESPONSE
        let firstPacket = try transport.readBulkPacket(
            handle: handle!,
            endpoint: handle!.fetchEP,
            maxLength: max(handle!.fetchMaxPacketSize, 512),
            timeout: 5_000
        )
        guard firstPacket.count >= 12 else { throw MTPError.invalidResponse }

        let (length, typeRaw, _, firstTxID) = try parseContainerHeader(firstPacket)
        try validateTransactionIDIfSessionActive(firstTxID, expected: currentTxID)

        if typeRaw == MTPContainerType.data.rawValue {
            // Data phase: extract inline payload, then loop-read until all declared bytes received.
            // A single USB bulk transfer may not return all bytes — the endpoint's max packet size
            // limits per-transfer throughput. Loop until we have `declaredPayload` bytes.
            var payload = firstPacket.count > 12 ? Data(firstPacket[12...]) : Data()
            let declaredPayload = Int(length) - 12
            while payload.count < declaredPayload {
                let remaining = declaredPayload - payload.count
                let bufferSize = min(max(remaining, handle!.fetchMaxPacketSize), 64 * 1024)
                let extra = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: bufferSize, timeout: 5_000)
                guard !extra.isEmpty else { throw MTPError.invalidResponse }
                payload.append(extra)
            }

            // Match go-mtpfs/mtp.go: if the payload length lands exactly on a USB packet
            // boundary, the device may send either a zero-length packet or the response
            // container immediately (Linux + XHCI compatibility path).
            let responsePacket: Data
            let fetchPacketSize = max(handle!.fetchMaxPacketSize, 512)
            if declaredPayload > 0, declaredPayload % fetchPacketSize == 0 {
                let trailer = try transport.readBulkPacket(
                    handle: handle!,
                    endpoint: handle!.fetchEP,
                    maxLength: max(fetchPacketSize, 512),
                    timeout: 5_000
                )
                if trailer.isEmpty {
                    responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: 5_000)
                } else {
                    let (_, trailerType, _, _) = try parseContainerHeader(trailer)
                    guard trailerType == MTPContainerType.response.rawValue else {
                        try failSync("expected response container after data phase, got type \(trailerType)")
                    }
                    responsePacket = trailer
                }
            } else {
                responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: 5_000)
            }
            try validateResponse(responsePacket, expectedTxID: currentTxID)

            return payload
        }

        guard typeRaw == MTPContainerType.response.rawValue else {
            try failSync("expected data or response container, got type \(typeRaw)")
        }
        try validateResponse(firstPacket, expectedTxID: currentTxID)
        return Data()
    }

    /// Streaming data-returning transaction: CMD → DATA(streamed to disk) → RESP
    /// This preserves the current Go bridge's `GetObject` parity path without buffering
    /// the entire object in memory before the first file write.
    func runCommandReturningDataToStream(
        code: UInt16,
        parameters: [UInt32] = [],
        output: FileHandle,
        progress: @Sendable (Int, Int) -> Void = { _, _ in },
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws {
        let currentTxID = nextTransactionID()
        try sendCommandContainer(code: code, parameters: parameters, txID: currentTxID)
        let downloadTimeout = Int(AppConfiguration.mtpDownloadTimeoutSeconds * 1_000)

        let firstPacket = try transport.readBulkPacket(
            handle: handle!,
            endpoint: handle!.fetchEP,
            maxLength: max(handle!.fetchMaxPacketSize, 512),
            timeout: downloadTimeout
        )
        guard firstPacket.count >= 12 else { throw MTPError.invalidResponse }

        let (length, typeRaw, _, firstTxID) = try parseContainerHeader(firstPacket)
        try validateTransactionIDIfSessionActive(firstTxID, expected: currentTxID)
        guard typeRaw == MTPContainerType.data.rawValue else {
            guard typeRaw == MTPContainerType.response.rawValue else {
                try failSync("expected data or response container, got type \(typeRaw)")
            }
            try validateResponse(firstPacket, expectedTxID: currentTxID)
            return
        }

        let declaredPayload = Int(length) - 12
        if firstPacket.count == 12, declaredPayload > 0 {
            // Match go-mtpfs appendix-H compatibility behavior: a device that returns
            // the data header in a standalone packet expects future host writes to
            // tolerate separate header/data packets as well.
            separateDataHeader = true
        }
        var written = 0
        if firstPacket.count > 12 {
            let initialPayload = Data(firstPacket[12...])
            try output.write(contentsOf: initialPayload)
            written += initialPayload.count
            progress(written, declaredPayload)
        }

        while written < declaredPayload {
            guard !isCancelled() else { throw MTPError.cancelled }
            let remaining = declaredPayload - written
            let bufferSize = min(max(remaining, handle!.fetchMaxPacketSize), 64 * 1024)
            let extra = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: bufferSize, timeout: downloadTimeout)
            guard !extra.isEmpty else { throw MTPError.invalidResponse }
            try output.write(contentsOf: extra)
            written += extra.count
            progress(written, declaredPayload)
        }

        // Zero-byte object path: declaredPayload == 0 skips the data-phase loop
        // entirely and reads the trailing response container immediately.
        // Task 10 adds the end-to-end zero-byte regression test.
        let responsePacket: Data
        let fetchPacketSize = max(handle!.fetchMaxPacketSize, 512)
        if declaredPayload > 0, declaredPayload % fetchPacketSize == 0 {
            let trailer = try transport.readBulkPacket(
                handle: handle!,
                endpoint: handle!.fetchEP,
                maxLength: max(fetchPacketSize, 512),
                timeout: downloadTimeout
            )
            if trailer.isEmpty {
                responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: downloadTimeout)
            } else {
                let (_, trailerType, _, _) = try parseContainerHeader(trailer)
                guard trailerType == MTPContainerType.response.rawValue else {
                    try failSync("expected response container after data phase, got type \(trailerType)")
                }
                responsePacket = trailer
            }
        } else {
            responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: downloadTimeout)
        }
        try validateResponse(responsePacket, expectedTxID: currentTxID)
    }

    /// Data-sending transaction: CMD → DATA(from host) → RESP
    /// `progress` is called after each USB chunk with (bytesSent, totalBytes).
    /// `isCancelled` is polled before each chunk; throws `MTPError.cancelled` if true.
    func runCommandSendingData(code: UInt16, parameters: [UInt32] = [], payload: Data, progress: @Sendable (Int, Int) -> Void = { _, _ in }, isCancelled: @Sendable () -> Bool = { false }) async throws -> MTPResponse {
        let currentTxID = nextTransactionID()
        try sendCommandContainer(code: code, parameters: parameters, txID: currentTxID)

        // Send data container in USB-level chunks. Match the current Go stack's two
        // compatibility behaviors:
        // 1. if the device previously split DATA header/body on read, allow separate
        //    header/body writes here as well;
        // 2. if the final USB write lands exactly on a packet boundary, send a short
        //    packet/ZLP so the device sees end-of-transfer correctly.
        var header = MTPDataWriter()
        if UInt32(12 + payload.count) > UInt32.max {
            header.writeUInt32(UInt32.max) // overflow indicator per MTP spec appendix H
        } else {
            header.writeUInt32(UInt32(12 + payload.count))
        }
        header.writeUInt16(MTPContainerType.data.rawValue)
        header.writeUInt16(code)
        header.writeUInt32(currentTxID)

        // Write header + payload in USB-sized chunks on sendEP using the descriptor-derived
        // packet size captured during scan/open. Do not hardcode 512 here.
        let maxPacketSize = max(handle!.sendMaxPacketSize, 512)
        var lastTransferSize = 0
        if separateDataHeader {
            try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: header.data, timeout: 5_000)
            lastTransferSize = header.data.count
            progress(0, payload.count)

            var offset = 0
            while offset < payload.count {
                guard !isCancelled() else { throw MTPError.cancelled }
                let end = min(offset + maxPacketSize, payload.count)
                let chunk = Data(payload[offset..<end])
                try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: chunk, timeout: 45_000)
                lastTransferSize = chunk.count
                offset = end
                progress(offset, payload.count)
            }
        } else {
            var offset = 0
            let allData = header.data + payload
            while offset < allData.count {
                guard !isCancelled() else { throw MTPError.cancelled }
                let end = min(offset + maxPacketSize, allData.count)
                let chunk = Data(allData[offset..<end])
                try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: chunk, timeout: 45_000)
                lastTransferSize = chunk.count
                offset = end
                progress(min(max(offset - header.data.count, 0), payload.count), payload.count)
            }
        }

        if lastTransferSize > 0, lastTransferSize % maxPacketSize == 0 {
            try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: Data(), timeout: 250)
        }

        // Read response
        let responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: 5_000)
        try validateResponse(responsePacket, expectedTxID: currentTxID)
        return try parseResponse(responsePacket)
    }

    /// Stream-sending transaction: CMD → DATA(from disk/stream) → RESP
    /// Sends the MTP data header first, then pulls payload chunks lazily from `nextChunk`.
    /// This preserves constant-memory uploads for large files instead of materializing the
    /// entire payload in RAM before the first USB write.
    func runCommandSendingStream(
        code: UInt16,
        parameters: [UInt32] = [],
        payloadSize: Int,
        nextChunk: @Sendable () throws -> Data?,
        progress: @Sendable (Int, Int) -> Void = { _, _ in },
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws -> MTPResponse {
        let currentTxID = nextTransactionID()
        try sendCommandContainer(code: code, parameters: parameters, txID: currentTxID)

        var header = MTPDataWriter()
        if UInt64(12 + payloadSize) > UInt64(UInt32.max) {
            header.writeUInt32(UInt32.max)
        } else {
            header.writeUInt32(UInt32(12 + payloadSize))
        }
        header.writeUInt16(MTPContainerType.data.rawValue)
        header.writeUInt16(code)
        header.writeUInt32(currentTxID)

        let maxPacketSize = max(handle!.sendMaxPacketSize, 512)
        var lastTransferSize = 0
        if separateDataHeader {
            try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: header.data, timeout: 5_000)
            lastTransferSize = header.data.count
        }
        var sent = 0
        if separateDataHeader {
            while true {
                guard !isCancelled() else { throw MTPError.cancelled }
                guard let chunk = try nextChunk(), !chunk.isEmpty else { break }
                try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: chunk, timeout: 45_000)
                lastTransferSize = chunk.count
                sent += chunk.count
                progress(sent, payloadSize)
            }
        } else {
            var pending = header.data
            var remainingHeaderBytes = header.data.count
            while true {
                guard !isCancelled() else { throw MTPError.cancelled }
                while pending.count < maxPacketSize {
                    guard let next = try nextChunk(), !next.isEmpty else { break }
                    pending.append(next)
                }
                guard !pending.isEmpty else { break }
                let end = min(maxPacketSize, pending.count)
                let chunk = Data(pending.prefix(end))
                try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: chunk, timeout: 45_000)
                lastTransferSize = chunk.count
                pending.removeFirst(end)

                let payloadBytesInChunk = max(chunk.count - remainingHeaderBytes, 0)
                remainingHeaderBytes = max(remainingHeaderBytes - chunk.count, 0)
                sent += payloadBytesInChunk
                progress(sent, payloadSize)
            }
        }

        if lastTransferSize > 0, lastTransferSize % maxPacketSize == 0 {
            try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: Data(), timeout: 250)
        }

        guard sent == payloadSize else {
            throw MTPError.invalidResponse
        }

        let responsePacket = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: 5_000)
        try validateResponse(responsePacket, expectedTxID: currentTxID)
        return try parseResponse(responsePacket)
    }

    // MARK: - Internal helpers

    private func ensureOpen() throws {
        if handle == nil {
            handle = try transport.open(scannedDevice)
        }
    }

    private func ensureTransportValidated() async throws {
        try ensureOpen()
        guard !transportValidated else { return }

        if scannedDevice.interfaceStringIndex != 0 {
            let interfaceName = try transport.readStringDescriptor(handle: handle!, index: scannedDevice.interfaceStringIndex)
            let normalized = interfaceName.lowercased()
            guard normalized.contains("mtp") || normalized.contains("cdc") || normalized.contains("acm") else {
                throw MTPError.usbError("interface string does not advertise MTP compatibility: \(interfaceName)")
            }
        } else {
            // Match go-mtpfs/Open(): if the USB descriptor omits an interface string,
            // fall back to MTPExtension-based validation before treating the device as usable.
            let payload = try await runCommandReturningData(code: MTPConstants.OC_GetDeviceInfo, parameters: [])
            var reader = MTPDataReader(data: payload)
            let info = try MTPDeviceInfo(from: &reader)
            let extensionString = info.vendorExtensionDesc.lowercased()
            guard extensionString.contains("microsoft/windowsphone") ||
                  extensionString.contains("fujifilm.co.jp") else {
                throw MTPError.usbError("descriptor omits interface string and MTPExtension is not in the compatibility allow-list: \(info.vendorExtensionDesc)")
            }
        }

        transportValidated = true
    }

    private func markSessionOpened(_ newSessionID: UInt32) {
        // Match go-mtpfs: OpenSession itself is sent without a live session and
        // therefore uses transaction ID 0. After a successful OpenSession, the
        // first in-session operation starts at transaction ID 1.
        self.sessionID = newSessionID
        self.transactionID = 1
    }

    private func nextTransactionID() -> UInt32 {
        // Match go-mtpfs/mtp.go: runTransaction only assigns and increments
        // TransactionID when d.session != nil. Pre-session commands such as
        // GetDeviceInfo compatibility probing, OpenSession, and stale
        // CloseSession recovery all keep transaction ID 0 and must not advance
        // the post-session counter.
        guard sessionID != nil else { return 0 }
        let current = transactionID
        transactionID += 1
        return current
    }

    private func sendCommandContainer(code: UInt16, parameters: [UInt32], txID: UInt32) throws {
        try ensureOpen()
        var writer = MTPDataWriter()
        writer.writeUInt32(UInt32(12 + parameters.count * 4))
        writer.writeUInt16(MTPContainerType.command.rawValue)
        writer.writeUInt16(code)
        writer.writeUInt32(txID)
        parameters.forEach { writer.writeUInt32($0) }
        MTPDebugLogger.logRequest(code: code, transactionID: txID, payloadLength: writer.data.count)
        try transport.writeBulkPacket(handle: handle!, endpoint: handle!.sendEP, data: writer.data, timeout: 5_000)
    }

    private func parseContainerHeader(_ data: Data) throws -> (length: UInt32, type: UInt16, code: UInt16, txID: UInt32) {
        guard data.count >= 12 else { throw MTPError.invalidResponse }
        var reader = MTPDataReader(data: data)
        let length = try reader.readUInt32()
        let type = try reader.readUInt16()
        let code = try reader.readUInt16()
        let txID = try reader.readUInt32()
        return (length, type, code, txID)
    }

    private func runTransactionRaw(code: UInt16, parameters: [UInt32]) async throws -> Data {
        let currentTxID = nextTransactionID()
        try sendCommandContainer(code: code, parameters: parameters, txID: currentTxID)
        let response = try transport.readBulkPacket(handle: handle!, endpoint: handle!.fetchEP, maxLength: 512, timeout: 5_000)
        let (_, typeRaw, _, txID) = try parseContainerHeader(response)
        guard typeRaw == MTPContainerType.response.rawValue else {
            try failSync("expected response container, got type \(typeRaw)")
        }
        try validateTransactionIDIfSessionActive(txID, expected: currentTxID)
        return response
    }

    private func openSessionOnce(sessionID: UInt32) async throws {
        let response = try await runTransactionRaw(
            code: MTPConstants.OC_OpenSession,
            parameters: [sessionID]
        )
        let (_, _, responseCode, _) = try parseContainerHeader(response)
        if responseCode == MTPConstants.RC_SessionAlreadyOpened {
            throw MTPError.sessionAlreadyOpened
        }
        try validateResponse(response)
    }

    private func closeStaleSessionForRecovery() async throws {
        _ = try? await runTransactionRaw(
            code: MTPConstants.OC_CloseSession,
            parameters: []
        )
        self.sessionID = nil
    }

    private func recoverAndReopenSession(sessionID: UInt32, originalError: Error) async throws {
        if let handle {
            try? transport.reset(handle)
            transport.close(handle)
            self.handle = nil
        }
        self.sessionID = nil
        self.transportValidated = false

        // Match go-mtpfs Configure(): give the device a short rest after reset.
        try await Task.sleep(for: .seconds(1))

        try ensureOpen()
        try await ensureTransportValidated()
        do {
            try await openSessionOnce(sessionID: sessionID)
            markSessionOpened(sessionID)
        } catch {
            throw MTPError.connectionError("OpenSession after reset failed after \(originalError.localizedDescription): \(error.localizedDescription)")
        }
    }

    private func failSync(_ message: String) throws -> Never {
        if let handle {
            transport.close(handle)
            self.handle = nil
        }
        self.sessionID = nil
        self.transportValidated = false
        throw MTPError.connectionError(message)
    }

    private func validateTransactionID(_ actual: UInt32, expected: UInt32) throws {
        guard actual == expected else {
            try failSync("transaction ID mismatch got \(actual) want \(expected)")
        }
    }

    private func validateTransactionIDIfSessionActive(_ actual: UInt32, expected: UInt32) throws {
        // Match go-mtpfs: transaction-ID sanity checks only run after d.session
        // exists. Pre-session GetDeviceInfo probing, OpenSession, and stale
        // CloseSession recovery should not fail solely because a device is loose
        // about transaction IDs before the session is established.
        guard sessionID != nil else { return }
        try validateTransactionID(actual, expected: expected)
    }

    private func validateResponse(_ data: Data, expectedTxID: UInt32? = nil) throws {
        let (_, typeRaw, code, txID) = try parseContainerHeader(data)
        guard typeRaw == MTPContainerType.response.rawValue else {
            try failSync("expected response container, got type \(typeRaw)")
        }
        if let expectedTxID {
            try validateTransactionIDIfSessionActive(txID, expected: expectedTxID)
        }
        if code != MTPConstants.RC_OK {
            throw MTPError.from(responseCode: code)
        }
    }

    private func parseResponse(_ data: Data) throws -> MTPResponse {
        let (length, _, code, txID) = try parseContainerHeader(data)
        let paramBytes = Int(length) - 12
        var params: [UInt32] = []
        if paramBytes > 0, data.count >= 12 + paramBytes {
            var reader = MTPDataReader(data: data[12...])
            for _ in 0..<(paramBytes / 4) {
                params.append(try reader.readUInt32())
            }
        }
        return MTPResponse(code: code, transactionID: txID, parameters: params)
    }
}

struct MTPResponse {
    let code: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]

    var isOK: Bool { code == MTPConstants.RC_OK }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Operations.swift`

```swift
import Foundation

private enum MTPDateEncoding {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

extension MTPDevice {
    // Internal implementation methods — called by MTPDeviceProtocol conformance in MTPUtilities.swift.
    // Prefixed with `perform` to avoid collision with protocol method names.

    func performDelete(objectHandle: UInt32) async throws {
        let response = try await runCommand(code: MTPConstants.OC_DeleteObject, parameters: [objectHandle, 0])
        guard response.isOK else { throw MTPError.from(responseCode: response.code) }
    }

    func performSendObjectInfo(filename: String, size: UInt32, storageID: UInt32, parentID: UInt32) async throws -> UInt32 {
        var writer = MTPDataWriter()
        writer.writeUInt32(storageID)
        writer.writeUInt16(0x3000) // OFC_Undefined — will be set by device
        writer.writeUInt16(0)      // ProtectionStatus
        writer.writeUInt32(size)
        writer.writeUInt16(0)      // ThumbFormat
        writer.writeUInt32(0)      // ThumbCompressedSize
        writer.writeUInt32(0)      // ImagePixWidth
        writer.writeUInt32(0)      // ImagePixHeight
        writer.writeUInt32(0)      // ImageBitDepth
        writer.writeUInt32(parentID)
        writer.writeUInt16(0)      // AssociationType
        writer.writeUInt32(0)      // AssociationDesc
        writer.writeUInt32(0)      // SequenceNumber
        try writer.writeMTPString(filename)
        try writer.writeMTPString("")  // CaptureDate
        // Match Kalam_UploadFile: the current bridge sets ObjectInfo.ModificationDate
        // to time.Now() before SendObjectInfo.
        try writer.writeMTPString(MTPDateEncoding.string(from: Date()))  // ModificationDate
        try writer.writeMTPString("")  // Keywords

        // Match go-mtpfs `SendObjectInfo`: request params are [wantStorageID, wantParent]
        // and the response returns [storageID, parentID, assignedHandle].
        let response = try await runCommandSendingData(
            code: MTPConstants.OC_SendObjectInfo,
            parameters: [storageID, parentID],
            payload: writer.data
        )
        guard response.isOK else { throw MTPError.from(responseCode: response.code) }
        guard response.parameters.count >= 3 else { throw MTPError.invalidResponse }
        return response.parameters[2] // assigned object handle
    }

    /// Streams file bytes from disk into a single MTP SendObject transaction.
    /// This keeps upload memory usage aligned with the Go bridge instead of reading
    /// the entire source file into memory before the first USB write.
    func performSendObjectStream(objectHandle: UInt32, sourceURL: URL,
                                 progress: @Sendable (Int, Int) -> Void,
                                 isCancelled: @Sendable () -> Bool) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        guard let sizeNumber = attributes[.size] as? NSNumber else {
            throw MTPError.nonRecoverable("Unable to determine file size for \(sourceURL.lastPathComponent)")
        }
        let totalBytes = sizeNumber.intValue
        let fileHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? fileHandle.close() }

        // SendObject itself carries no extra parameters; the device already assigned the handle
        // during SendObjectInfo. Keep the objectHandle parameter for API symmetry and logging.
        _ = objectHandle

        try await runCommandSendingStream(
            code: MTPConstants.OC_SendObject,
            parameters: [],
            payloadSize: totalBytes,
            nextChunk: {
                try fileHandle.read(upToCount: 64 * 1024)
            },
            progress: progress,
            isCancelled: isCancelled
        )
    }

    func performCreateFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32 {
        var writer = MTPDataWriter()
        writer.writeUInt32(storageID)
        writer.writeUInt16(0x3001) // OFC_Association
        writer.writeUInt16(0)      // ProtectionStatus
        writer.writeUInt32(0)      // ObjectCompressedSize
        writer.writeUInt16(0)      // ThumbFormat
        writer.writeUInt32(0)      // ThumbCompressedSize
        writer.writeUInt32(0)      // ImagePixWidth
        writer.writeUInt32(0)      // ImagePixHeight
        writer.writeUInt32(0)      // ImageBitDepth
        writer.writeUInt32(parentID)
        // Match the current Kalam_CreateFolder bridge path: ObjectFormat is
        // OFC_Association, but AssociationType is left at the Go zero value.
        writer.writeUInt16(0)      // AssociationType
        writer.writeUInt32(0)      // AssociationDesc
        writer.writeUInt32(0)      // SequenceNumber
        try writer.writeMTPString(name)
        try writer.writeMTPString("")  // CaptureDate
        try writer.writeMTPString("")  // ModificationDate
        try writer.writeMTPString("")  // Keywords

        let response = try await runCommandSendingData(
            code: MTPConstants.OC_SendObjectInfo,
            parameters: [storageID, parentID],
            payload: writer.data
        )
        guard response.isOK else { throw MTPError.from(responseCode: response.code) }
        guard response.parameters.count >= 3 else { throw MTPError.invalidResponse }
        return response.parameters[2] // assigned folder handle
    }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Download.swift`

```swift
extension MTPDevice {
    /// Match the current Go bridge's real download path: use `OC_GetObject`,
    /// but stream the data phase straight to disk so large files do not accumulate
    /// in memory before the write starts. `GetPartialObject64` stays a future
    /// optimization, not a migration prerequisite.
    ///
    /// **Cancellation safety:** The `isCancelled` closure is called from the same Task context
    /// as the pool operation. `FileTransferManager` passes a lock-backed
    /// `TransferCancellationToken.isCancelled` closure here, so Swift 6 never has to read
    /// `TransferTask.isCancelled` from a background `@Sendable` context.
    /// Keep this helper name distinct from the protocol requirement added in Task 7.
    /// The adapter there calls `performDownloadToStream(...)`; reusing
    /// `downloadToStream(...)` here would recurse back into the adapter.
    func performDownloadToStream(handle objectHandle: UInt32, totalSize: Int, output: FileHandle, chunkSize: Int = 64 * 1024, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        _ = chunkSize // Reserved for a future capability-probed GetPartialObject64 optimization.
        try await runCommandReturningDataToStream(
            code: MTPConstants.OC_GetObject,
            parameters: [objectHandle],
            output: output,
            progress: progress,
            isCancelled: isCancelled
        )
    }
}
```

- [ ] **Step 4: Add protocol-level logging and re-run the focused tests**

`SwiftMTP/Services/MTPCore/MTPProtocol/MTPDebugLogger.swift`

```swift
import OSLog

enum MTPDebugLogger {
    private static let logger = Logger(subsystem: "com.AlanWang.SwiftMTP", category: "MTP")

    static func logRequest(code: UInt16, transactionID: UInt32, payloadLength: Int) {
        logger.debug("request code=\(code, format: .hex, privacy: .public) tx=\(transactionID, privacy: .public) bytes=\(payloadLength, privacy: .public)")
    }

    static func logResponse(code: UInt16, transactionID: UInt32, payloadLength: Int) {
        logger.debug("response code=\(code, format: .hex, privacy: .public) tx=\(transactionID, privacy: .public) bytes=\(payloadLength, privacy: .public)")
    }
}
```

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceTests -only-testing:SwiftMTPTests/ErrorPathTests
```

Expected: `MTPDeviceTests` passes; `ErrorPathTests` is still red until the next step adds the recovery and sync-loss cases.

- [ ] **Step 5: Add the error-path tests and make them pass**

`SwiftMTPTests/MTPCore/ErrorPathTests.swift`

```swift
import XCTest
@testable import SwiftMTP

final class ErrorPathTests: XCTestCase {
    private func response(code: UInt16, transactionID: UInt32) -> Data {
        var writer = MTPDataWriter()
        writer.writeUInt32(12)
        writer.writeUInt16(MTPContainerType.response.rawValue)
        writer.writeUInt16(code)
        writer.writeUInt32(transactionID)
        return writer.data
    }

    func testAccessDeniedMapsToFriendlyError() {
        // Error messages use String(localized:) — verify the raw enum case exists
        // and the localization key is consistent
        XCTAssertNotNil(MTPError.accessDenied.errorDescription)
    }

    func testSessionAlreadyOpenedClosesSessionBeforeResetting() async throws {
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_SessionAlreadyOpened, transactionID: 0),
                response(code: MTPConstants.RC_OK, transactionID: 0), // stale CloseSession before a live session
                response(code: MTPConstants.RC_OK, transactionID: 0)  // retried OpenSession
            ]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        XCTAssertEqual(transport.writtenPackets.count, 3)
        var reader = MTPDataReader(data: transport.writtenPackets[1])
        let closeContainer = try MTPContainer(from: &reader)
        XCTAssertEqual(closeContainer.code, MTPConstants.OC_CloseSession)
        XCTAssertEqual(closeContainer.transactionID, 0)
        var retryReader = MTPDataReader(data: transport.writtenPackets[2])
        let retryContainer = try MTPContainer(from: &retryReader)
        XCTAssertEqual(retryContainer.code, MTPConstants.OC_OpenSession)
        XCTAssertEqual(retryContainer.transactionID, 0)
        XCTAssertEqual(transport.resetCount, 0)
        XCTAssertEqual(transport.openCount, 1)
    }

    func testTransactionIDMismatchClosesConnection() async throws {
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession
                response(code: MTPConstants.RC_OK, transactionID: 99)  // wrong txid for GetStorageIDs
            ]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected transaction ID mismatch to throw")
        } catch let error as MTPError {
            if case let .connectionError(message) = error {
                XCTAssertTrue(message.contains("transaction ID mismatch"))
            } else {
                XCTFail("Expected connectionError, got \(error)")
            }
            XCTAssertEqual(transport.closeCount, 1)
        }
    }

    // MARK: - 边界条件测试

    func testUSBDeviceSuddenDisconnect() async throws {
        // 测试USB设备突然断开连接的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
            ],
            // 模拟设备在第二次操作时断开
            errorSequence: [nil, LIBUSB_ERROR_NO_DEVICE]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected device disconnect error")
        } catch let error as MTPError {
            // 验证错误被正确分类为可恢复错误
            XCTAssertTrue(error.isRecoverable)
            // 验证设备被正确关闭
            XCTAssertEqual(transport.closeCount, 1)
        }
    }

    func testUSBDevicePermissionDenied() async throws {
        // 测试USB权限被拒绝的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [],
            // 模拟权限错误
            errorSequence: [LIBUSB_ERROR_ACCESS]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)

        do {
            try await device.openSession(sessionID: 1)
            XCTFail("Expected permission denied error")
        } catch let error as MTPError {
            // 权限错误应该是不可恢复的
            XCTAssertFalse(error.isRecoverable)
            XCTAssertTrue(error.errorDescription?.contains("permission") ?? false)
        }
    }

    func testUSBDeviceBusy() async throws {
        // 测试USB设备忙的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
            ],
            // 模拟设备忙
            errorSequence: [nil, LIBUSB_ERROR_BUSY]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected device busy error")
        } catch let error as MTPError {
            // 设备忙应该是可恢复错误
            XCTAssertTrue(error.isRecoverable)
            if case .deviceBusy = error {
                // 正确
            } else {
                XCTFail("Expected deviceBusy error, got \(error)")
            }
        }
    }

    func testUSBDeviceTimeout() async throws {
        // 测试USB超时的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
            ],
            // 模拟超时
            errorSequence: [nil, LIBUSB_ERROR_TIMEOUT]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected timeout error")
        } catch let error as MTPError {
            // 超时应该是可恢复错误
            XCTAssertTrue(error.isRecoverable)
            if case .timeout = error {
                // 正确
            } else {
                XCTFail("Expected timeout error, got \(error)")
            }
        }
    }

    func testUSBDeviceInvalidResponse() async throws {
        // 测试USB返回无效响应的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        // 创建一个格式错误的响应（长度不匹配）
        var malformedResponse = Data([0x05, 0x00, 0x00, 0x00]) // 声明长度5，但实际数据不足
        malformedResponse.append(contentsOf: [0x01, 0x00]) // 只有2字节，不是完整的MTP容器

        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
                malformedResponse
            ]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected invalid response error")
        } catch let error as MTPError {
            // 无效响应应该是不可恢复错误
            XCTAssertFalse(error.isRecoverable)
            if case .invalidResponse = error {
                // 正确
            } else {
                XCTFail("Expected invalidResponse error, got \(error)")
            }
        }
    }

    func testUSBDeviceEmptyResponse() async throws {
        // 测试USB返回空响应的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
                Data() // 空响应
            ]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected empty response error")
        } catch let error as MTPError {
            // 空响应应该是不可恢复错误
            XCTAssertFalse(error.isRecoverable)
            // 应该是invalidResponse或类似的错误
            XCTAssertTrue(error.errorDescription?.contains("Invalid") ?? false ||
                         error.errorDescription?.contains("empty") ?? false)
        }
    }

    func testUSBDevicePartialResponse() async throws {
        // 测试USB返回不完整响应的情况
        let scannedDevice = USBScannedDevice.fixture(
            vendorID: 0x18D1,
            productID: 0x4EE1,
            interfaceClass: 6,
            interfaceSubClass: 1,
            interfaceProtocol: 1
        )
        // 创建一个不完整的响应（只有头部，没有完整数据）
        var partialResponse = Data([0x0C, 0x00, 0x00, 0x00]) // 长度12
        partialResponse.append(contentsOf: [0x03, 0x00]) // 类型RESPONSE
        partialResponse.append(contentsOf: [0x01, 0x00]) // 代码RC_OK
        // 缺少transactionID和参数

        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                response(code: MTPConstants.RC_OK, transactionID: 0),  // OpenSession成功
                partialResponse
            ]
        )
        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)
        try await device.openSession(sessionID: 1)

        do {
            _ = try await device.runCommand(code: MTPConstants.OC_GetStorageIDs)
            XCTFail("Expected partial response error")
        } catch let error as MTPError {
            // 不完整响应应该是不可恢复错误
            XCTAssertFalse(error.isRecoverable)
            // 应该是invalidResponse
            if case .invalidResponse = error {
                // 正确
            } else {
                XCTFail("Expected invalidResponse error, got \(error)")
            }
        }
    }
}
```

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceTests -only-testing:SwiftMTPTests/ErrorPathTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Operations.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPDevice+Download.swift SwiftMTP/Services/MTPCore/MTPProtocol/MTPDebugLogger.swift SwiftMTPTests/MTPCore/MTPDeviceTests.swift SwiftMTPTests/MTPCore/ErrorPathTests.swift SwiftMTPTests/MTPCore/Support/MockUSBTransport.swift
git commit -m "feat(mtpcore): add device transaction core"
```

### Task 7: Implement High-Level Device and File Operations

**Files:**

- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceManager.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPDataStructures.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevice/MTPUtilities.swift`
- Modify: `SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`
- Test: `SwiftMTPTests/MTPCore/MTPDeviceManagerTests.swift`
- Test: `SwiftMTPTests/MTPCore/MTPFileOperationsTests.swift`
- Test: `SwiftMTPTests/MTPCore/Support/MockMTPDevice.swift`
- [ ] **Step 1: Write failing manager and file-operation tests**

```swift
import XCTest
@testable import SwiftMTP

final class MTPDeviceManagerTests: XCTestCase {
    func testInitializeBuildsDeviceSnapshot() async throws {
        let manager = MTPDeviceManager(
            device: MockMTPDevice(),
            transportIdentity: USBDeviceIdentity(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 3)
        )
        let snapshot = try await manager.initialize()
        XCTAssertEqual(snapshot.name, "Fixture Phone")
        XCTAssertEqual(snapshot.manufacturer, "SwiftMTP")
    }

    func testInitializeKeepsDeviceVisibleWhenStorageFetchFails() async throws {
        let manager = MTPDeviceManager(
            device: StorageFailingMockMTPDevice(),
            transportIdentity: USBDeviceIdentity(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 4)
        )
        let snapshot = try await manager.initialize()
        XCTAssertEqual(snapshot.name, "Fixture Phone")
        XCTAssertTrue(snapshot.storages.isEmpty)
    }
}

final class MTPFileOperationsTests: XCTestCase {
    func testListFilesMapsObjectInfoToFileEntries() async throws {
        let operations = MTPFileOperations(device: MockMTPDevice())
        let files = try await operations.listFiles(storageID: 1, parentID: 0xFFFFFFFF)
        XCTAssertEqual(files.map(\.name), ["IMG_0001.jpg"])
    }

    func testParseMTPDateMatchesGoCompatibilityTrimming() {
        let normal = MTPUtilities.parseMTPDate("20260424T121314")
        XCTAssertNotNil(normal)
        XCTAssertEqual(MTPUtilities.parseMTPDate("20260424T121314."), normal)
        XCTAssertEqual(MTPUtilities.parseMTPDate("20260424T121314Z"), normal)
        XCTAssertNotNil(MTPUtilities.parseMTPDate("20260424T121314+0800"))
    }
}
```

- [ ] **Step 2: Run the tests to prove the high-level API does not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceManagerTests -only-testing:SwiftMTPTests/MTPFileOperationsTests
```

Expected: build fails because `MTPDeviceManager`, `MTPFileOperations`, and the data structures are undefined.

- [ ] **Step 3: Add the first snapshot and file-entry models**

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDataStructures.swift`

```swift
import Foundation

struct MTPDeviceSnapshot: Equatable {
    let transportIdentity: USBDeviceIdentity
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let mtpVersion: String
    let deviceVersion: String
    let vendorExtensionDesc: String
    let storages: [MTPStorageSnapshot]
}

struct MTPStorageSnapshot: Equatable {
    let id: UInt32
    let description: String
    let freeSpace: UInt64
    let maxCapacity: UInt64
}

struct MTPFileEntry: Equatable {
    let objectID: UInt32
    let parentID: UInt32
    let storageID: UInt32
    let name: String
    let size: UInt64
    let isDirectory: Bool
    let modifiedDate: Date?
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceManager.swift`

```swift
import Foundation
import OSLog

final class MTPDeviceManager {
    private let device: MTPDeviceProtocol
    private let transportIdentity: USBDeviceIdentity

    init(device: MTPDeviceProtocol, transportIdentity: USBDeviceIdentity) {
        self.device = device
        self.transportIdentity = transportIdentity
    }

    func initialize() async throws -> MTPDeviceSnapshot {
        let info = try await device.getDeviceInfo()
        let storages: [MTPStorageInfoListItem]
        do {
            storages = try await device.getStorageInfoList()
        } catch {
            Logger(subsystem: "com.AlanWang.SwiftMTP", category: "MTP")
                .error("MTPDeviceManager: storage fetch failed for \(self.transportIdentity.vendorID, format: .hex, privacy: .public):\(self.transportIdentity.productID, format: .hex, privacy: .public) bus=\(self.transportIdentity.busNumber, privacy: .public) addr=\(self.transportIdentity.address, privacy: .public): \(String(describing: error), privacy: .public)")
            // Preserve current Kalam_Scan behavior: a device with readable identity but
            // temporarily unreadable storages still appears in the sidebar with an empty
            // storage list instead of disappearing from the scan result entirely.
            // This is a logged degradation, not a silent failure.
            storages = []
        }
        let displayName: String
        if !info.manufacturer.isEmpty && !info.model.localizedCaseInsensitiveContains(info.manufacturer) {
            displayName = "\(info.manufacturer) \(info.model)"
        } else {
            displayName = info.model
        }

        return MTPDeviceSnapshot(
            transportIdentity: transportIdentity,
            name: displayName,
            manufacturer: info.manufacturer,
            model: info.model,
            serialNumber: info.serialNumber,
            mtpVersion: info.mtpVersion,
            deviceVersion: info.deviceVersion,
            // Preserve current UI output: the Go bridge currently surfaces manufacturer
            // in the sidebar's vendor-extension slot.
            vendorExtensionDesc: info.manufacturer,
            storages: storages.map {
                MTPStorageSnapshot(id: $0.id, description: $0.description, freeSpace: $0.freeSpaceBytes, maxCapacity: $0.maxCapacity)
            }
        )
    }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift`

```swift
import Foundation

final class MTPFileOperations {
    private let device: MTPDeviceProtocol

    init(device: MTPDeviceProtocol) {
        self.device = device
    }

    func listFiles(storageID: UInt32, parentID: UInt32) async throws -> [MTPFileEntry] {
        let handles = try await device.getObjectHandles(storageID: storageID, parentID: parentID)
        var entries: [MTPFileEntry] = []
        for handle in handles {
            // Preserve current Go behavior: one bad object should not blank the whole
            // directory listing. Skip unreadable entries and keep the rest.
            do {
                let info = try await device.getObjectInfo(handle: handle)
                entries.append(MTPFileEntry(
                    objectID: handle,
                    parentID: info.parentObject,
                    storageID: info.storageID,
                    name: info.filename,
                    size: UInt64(info.objectCompressedSize),
                    isDirectory: info.objectFormat == 0x3001,
                    modifiedDate: MTPUtilities.parseMTPDate(info.modificationDate)
                ))
            } catch {
                continue
            }
        }
        return entries
    }
}
```

- [ ] **Step 4: Add the protocol seam for test doubles and re-run the focused suite**

`SwiftMTP/Services/MTPCore/MTPDevice/MTPUtilities.swift`

```swift
import Foundation

protocol MTPDeviceProtocol: AnyObject, Sendable {
    func getDeviceInfo() async throws -> MTPDeviceInfo
    func getStorageInfoList() async throws -> [MTPStorageInfoListItem]
    func getObjectHandles(storageID: UInt32, parentID: UInt32) async throws -> [UInt32]
    func getObjectInfo(handle: UInt32) async throws -> MTPObjectInfo
    /// WARNING: Loads the entire object into memory.
    /// Use `downloadToStream` for files larger than small metadata blobs.
    func getObject(handle: UInt32) async throws -> Data
    func downloadToStream(handle: UInt32, totalSize: Int, output: FileHandle, chunkSize: Int, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws
    func sendObjectInfo(filename: String, size: UInt32, storageID: UInt32, parentID: UInt32) async throws -> MTPObjectInfo
    func sendObjectStream(objectHandle: UInt32, sourceURL: URL, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws
    func deleteObject(handle: UInt32) async throws
    func createFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32
    func openSession(sessionID: UInt32) async throws
    func closeSession() async throws
}

struct MTPStorageInfoListItem: Equatable {
    let id: UInt32
    let description: String
    let freeSpaceBytes: UInt64
    let maxCapacity: UInt64
}

enum MTPUtilities {
    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let zonedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmssZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func parseMTPDate(_ value: String) -> Date? {
        var normalized = value
        while normalized.last == "." { normalized.removeLast() } // Samsung compatibility from go-mtpfs
        while normalized.last == "Z" { normalized.removeLast() } // Sailfish/Jolla compatibility from go-mtpfs
        guard !normalized.isEmpty else { return nil }
        return localFormatter.date(from: normalized) ?? zonedFormatter.date(from: normalized)
    }
}

extension MTPDevice: MTPDeviceProtocol {
    func getDeviceInfo() async throws -> MTPDeviceInfo {
        let payload = try await runCommandReturningData(code: MTPConstants.OC_GetDeviceInfo, parameters: [])
        var reader = MTPDataReader(data: payload)
        return try MTPDeviceInfo(from: &reader)
    }

    func getStorageInfoList() async throws -> [MTPStorageInfoListItem] {
        let idsPayload = try await runCommandReturningData(code: MTPConstants.OC_GetStorageIDs, parameters: [])
        var idsReader = MTPDataReader(data: idsPayload)
        let ids = try idsReader.readUInt32Array()
        var storages: [MTPStorageInfoListItem] = []

        for storageID in ids {
            let infoPayload = try await runCommandReturningData(code: MTPConstants.OC_GetStorageInfo, parameters: [storageID])
            var infoReader = MTPDataReader(data: infoPayload)
            let info = try MTPStorageInfo(from: &infoReader)
            storages.append(
                MTPStorageInfoListItem(
                    id: storageID,
                    description: info.description,
                    freeSpaceBytes: info.freeSpaceBytes,
                    maxCapacity: info.maxCapacity
                )
            )
        }

        return storages
    }

    func getObjectHandles(storageID: UInt32, parentID: UInt32) async throws -> [UInt32] {
        let payload = try await runCommandReturningData(
            code: MTPConstants.OC_GetObjectHandles,
            parameters: [storageID, 0, parentID]
        )
        var reader = MTPDataReader(data: payload)
        return try reader.readUInt32Array()
    }

    func getObjectInfo(handle: UInt32) async throws -> MTPObjectInfo {
        let payload = try await runCommandReturningData(code: MTPConstants.OC_GetObjectInfo, parameters: [handle])
        var reader = MTPDataReader(data: payload)
        let info = try MTPObjectInfo(from: &reader)
        if info.objectFormat == 0x3001 {
            // Match go-mtpx.GetFileSize(): directories are size 0 and do not issue
            // GetObjectPropValue(ObjectSize), even if CompressedSize contains a sentinel.
            return info.resolvingObjectCompressedSize(0)
        }
        guard info.needsObjectSizeLookup else { return info }

        // Match go-mtpx.GetFileSize(): for non-directory objects, when ObjectInfo
        // reports 0xffffffff, fetch the real 64-bit size from ObjectPropValue(ObjectSize)
        // before exposing metadata.
        let sizePayload = try await runCommandReturningData(
            code: MTPConstants.OC_GetObjectPropValue,
            parameters: [handle, UInt32(MTPConstants.OPC_ObjectSize)]
        )
        var sizeReader = MTPDataReader(data: sizePayload)
        let resolvedSize = try sizeReader.readUInt64()
        return info.resolvingObjectCompressedSize(resolvedSize)
    }

    func getObject(handle: UInt32) async throws -> Data {
        return try await runCommandReturningData(code: MTPConstants.OC_GetObject, parameters: [handle])
    }

    func downloadToStream(handle: UInt32, totalSize: Int, output: FileHandle, chunkSize: Int, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        if totalSize == 0 { return }
        // Delegate to MTPDevice+Download.swift's GetObject streaming implementation.
        // The helper is intentionally named `performDownloadToStream(...)`
        // so protocol conformance does not recurse into itself.
        try await performDownloadToStream(handle: handle, totalSize: totalSize, output: output, chunkSize: chunkSize, progress: progress, isCancelled: isCancelled)
    }

    // Protocol conformance — delegate to perform* methods in MTPDevice+Operations.swift
    func deleteObject(handle: UInt32) async throws {
        try await performDelete(objectHandle: handle)
    }

    func sendObjectInfo(filename: String, size: UInt32, storageID: UInt32, parentID: UInt32) async throws -> MTPObjectInfo {
        let assignedHandle = try await performSendObjectInfo(filename: filename, size: size, storageID: storageID, parentID: parentID)
        return MTPObjectInfo(objectHandle: assignedHandle, storageID: storageID, objectFormat: 0x3000, parentObject: parentID, objectCompressedSize: size, filename: filename)
    }

    func sendObjectStream(objectHandle: UInt32, sourceURL: URL, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        try await performSendObjectStream(objectHandle: objectHandle, sourceURL: sourceURL, progress: progress, isCancelled: isCancelled)
    }

    func createFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32 {
        return try await performCreateFolder(name: name, storageID: storageID, parentID: parentID)
    }
}
```

`SwiftMTPTests/MTPCore/Support/MockMTPDevice.swift`

```swift
import Foundation
@testable import SwiftMTP

class MockMTPDevice: MTPDeviceProtocol, @unchecked Sendable {
    func openSession(sessionID: UInt32) async throws {}
    func closeSession() async throws {}
    func getDeviceInfo() async throws -> MTPDeviceInfo {
        var reader = MTPDataReader(data: try FixtureLoader.data(named: "device_info.bin"))
        return try MTPDeviceInfo(from: &reader)
    }

    func getStorageInfoList() async throws -> [MTPStorageInfoListItem] {
        [MTPStorageInfoListItem(id: 1, description: "Internal", freeSpaceBytes: 2048, maxCapacity: 4096)]
    }

    func getObjectHandles(storageID: UInt32, parentID: UInt32) async throws -> [UInt32] {
        [1]
    }

    func getObjectInfo(handle: UInt32) async throws -> MTPObjectInfo {
        MTPObjectInfo(storageID: 1, objectFormat: 0x3801, parentObject: 0xFFFFFFFF, objectCompressedSize: 16, filename: "IMG_0001.jpg")
    }

    func getObject(handle: UInt32) async throws -> Data {
        Data()
    }

    func downloadToStream(handle: UInt32, totalSize: Int, output: FileHandle, chunkSize: Int, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        // no-op for base mock
    }

    func sendObjectInfo(filename: String, size: UInt32, storageID: UInt32, parentID: UInt32) async throws -> MTPObjectInfo {
        MTPObjectInfo(storageID: storageID, objectFormat: 0x3000, parentObject: parentID, objectCompressedSize: size, filename: filename)
    }

    func sendObjectStream(objectHandle: UInt32, sourceURL: URL, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {}

    func deleteObject(handle: UInt32) async throws {}

    func createFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32 { 999 }
}

final class StorageFailingMockMTPDevice: MockMTPDevice {
    override func getStorageInfoList() async throws -> [MTPStorageInfoListItem] {
        throw MTPError.deviceError("fixture storage read failed")
    }
}
```

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDeviceManagerTests -only-testing:SwiftMTPTests/MTPFileOperationsTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPDevice/MTPDeviceManager.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPDataStructures.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPUtilities.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift SwiftMTPTests/MTPCore/MTPDeviceManagerTests.swift SwiftMTPTests/MTPCore/MTPFileOperationsTests.swift SwiftMTPTests/MTPCore/Support/MockMTPDevice.swift
git commit -m "feat(mtpcore): add device snapshots and file operations"
```

### Task 8: Add Device Pooling, Retry Logic, and Error Classification

**Files:**

- Create: `SwiftMTP/Services/MTPCore/MTPDevicePool.swift`
- Create: `SwiftMTP/Services/MTPCore/MTPDevicePool+Sync.swift`
- Modify: `SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`
- Modify: `SwiftMTP/Config/AppConfiguration.swift`
- Test: `SwiftMTPTests/MTPCore/MTPDevicePoolTests.swift`
- Test: `SwiftMTPTests/MTPCore/ErrorPathTests.swift`
- [ ] **Step 1: Write the failing pooling and retry tests**

```swift
import XCTest
@testable import SwiftMTP

final class MTPDevicePoolTests: XCTestCase {
    func testSecondOperationReusesPooledDevice() async throws {
        let scannedDevice = USBScannedDevice.fixture(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 7, interfaceClass: 6, interfaceSubClass: 1, interfaceProtocol: 1)
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [try FixtureLoader.data(named: "container_response_ok.bin")]
        )
        let pool = MTPDevicePool(transport: transport)
        _ = try await pool.withDevice(for: scannedDevice.identity, retries: 1, backoff: { _ in .milliseconds(200) }) { _ in "first" }
        _ = try await pool.withDevice(for: scannedDevice.identity, retries: 1, backoff: { _ in .milliseconds(200) }) { _ in "second" }
        XCTAssertEqual(transport.openCount, 1)
    }

    func testRecoverableErrorRetriesOnce() async throws {
        let scannedDevice = USBScannedDevice.fixture(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 8, interfaceClass: 6, interfaceSubClass: 1, interfaceProtocol: 1)
        let transport = MockUSBTransport(
            devices: [scannedDevice],
            responses: [
                try FixtureLoader.data(named: "container_response_ok.bin"),
                try FixtureLoader.data(named: "container_response_ok.bin"),
                try FixtureLoader.data(named: "container_response_ok.bin")
            ]
        )
        let pool = MTPDevicePool(transport: transport)
        var attempts = 0
        let value = try await pool.withDevice(for: scannedDevice.identity, retries: 1, backoff: { _ in .milliseconds(200) }) { _ in
            attempts += 1
            if attempts == 1 {
                throw MTPError.deviceBusy("fixture busy")
            }
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(transport.openCount, 2)
    }
}
```

- [ ] **Step 2: Run the tests to prove the pool does not exist**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDevicePoolTests -only-testing:SwiftMTPTests/ErrorPathTests
```

Expected: build fails because `MTPDevicePool` is undefined.

- [ ] **Step 3: Add the actor pool and the recoverable error cases**

**Compile-order note:** land the `AppConfiguration` constants from Step 4 in the same changeset before re-running tests. `MTPDevicePool.swift` references them directly, so this task is only compile-complete once both steps are present.

`SwiftMTP/Services/MTPCore/MTPDevicePool.swift`

```swift
import Foundation
import OSLog

actor MTPDevicePool {
    private struct PoolEntry {
        let device: MTPDeviceProtocol
        var lastUsed: Date
    }

    private var entries: [USBDeviceIdentity: PoolEntry] = [:]
    private var inUseIdentities: Set<USBDeviceIdentity> = []  // per-device exclusivity only
    private var isShutdown = false
    private var waitersByIdentity: [USBDeviceIdentity: [CheckedContinuation<Void, Error>]] = [:]
    private let maxPoolSize = AppConfiguration.mtpPoolMaxEntries
    private let transport: any USBTransport
    private var cleanupTask: Task<Void, Never>?
    private var nextSessionID: UInt32 = 1

    static let shared = MTPDevicePool(transport: LibUSBTransport())

    init(transport: any USBTransport) {
        self.transport = transport
        // cleanupTask is started lazily on first withDevice call, not here.
        // This avoids spawning a background Task if the pool is initialized
        // during static let resolution but no device operations follow.
    }

    /// Start periodic cleanup on first actual use. Idempotent.
    private func ensureCleanupStarted() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.cleanupExpiredEntries()
            }
        }
    }

    private func cleanupExpiredEntries() async {
        let cutoff = Date().addingTimeInterval(-AppConfiguration.mtpPoolEntryTTLSeconds)
        let expired = entries.filter { $0.value.lastUsed < cutoff && !inUseIdentities.contains($0.key) }
        for (identity, entry) in expired {
            try? await entry.device.closeSession()
            entries.removeValue(forKey: identity)
        }
        Logger(subsystem: "com.AlanWang.SwiftMTP", category: "MTP").info("MTPDevicePool: cleanup, \(entries.count) entries remaining")
    }

    func withDevice<T>(for identity: USBDeviceIdentity, retries: Int = 3, backoff: @Sendable (Int) -> Duration = { attempt in min(.milliseconds(500 * attempt * attempt), .seconds(2)) }, operation: @Sendable (MTPDeviceProtocol) async throws -> T) async throws -> T {
        guard !isShutdown else { throw MTPError.poolShutdown }
        ensureCleanupStarted()

        // Same-device operations are exclusive; different devices may proceed concurrently.
        while inUseIdentities.contains(identity) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waitersByIdentity[identity, default: []].append(cont)
            }
        }
        guard !isShutdown else { throw MTPError.poolShutdown }

        inUseIdentities.insert(identity)
        defer {
            inUseIdentities.remove(identity)
            if var identityWaiters = waitersByIdentity[identity], !identityWaiters.isEmpty {
                let waiter = identityWaiters.removeFirst()
                if identityWaiters.isEmpty {
                    waitersByIdentity.removeValue(forKey: identity)
                } else {
                    waitersByIdentity[identity] = identityWaiters
                }
                waiter.resume()
            }
        }

        var lastRecoverableError: MTPError?
        for attempt in 0...retries {
            do {
                let device = try await getOrCreateDevice(for: identity)
                let result = try await operation(device)
                // Update lastUsed timestamp on success
                if var entry = entries[identity] {
                    entry.lastUsed = Date()
                    entries[identity] = entry
                }
                return result
            } catch let error as MTPError where error.isRecoverable {
                lastRecoverableError = error
                if attempt < retries {
                    try await Task.sleep(for: backoff(attempt + 1))
                    await evictEntry(identity)
                    continue
                }
                throw error
            } catch let error as MTPError {
                throw error
            } catch {
                throw MTPError.nonRecoverable(error.localizedDescription)
            }
        }

        throw lastRecoverableError ?? MTPError.nonRecoverable("operation exhausted retries")
    }

    func shutdown() async {
        isShutdown = true
        cleanupTask?.cancel()
        for (_, entry) in entries {
            try? await entry.device.closeSession()
        }
        let count = entries.count
        entries.removeAll()
        for (_, identityWaiters) in waitersByIdentity {
            for waiter in identityWaiters {
                waiter.resume(throwing: MTPError.poolShutdown)
            }
        }
        waitersByIdentity.removeAll()
        Logger(subsystem: "com.AlanWang.SwiftMTP", category: "MTP").info("MTPDevicePool: disposed \(count) entries")
    }

    private func getOrCreateDevice(for identity: USBDeviceIdentity) async throws -> MTPDeviceProtocol {
        if let entry = entries[identity], Date().timeIntervalSince(entry.lastUsed) < AppConfiguration.mtpPoolEntryTTLSeconds {
            return entry.device
        }

        // Evict stale entry before creating new one
        await evictEntry(identity)

        guard let scannedDevice = try transport.scanDevices().first(where: { $0.identity == identity }) else {
            throw MTPError.deviceNotFound("device disappeared during acquisition")
        }

        let device = MTPDevice(transport: transport, scannedDevice: scannedDevice)

        // Open MTP session (required for most operations except GetDeviceInfo).
        // If openSession throws, `device` goes out of scope and MTPDevice.deinit
        // calls transport.close(handle), which releases the USB interface
        // (libusb_release_interface + libusb_close + libusb_exit).
        let sid = nextSessionID
        nextSessionID += 1
        try await device.openSession(sessionID: sid)

        entries[identity] = PoolEntry(device: device, lastUsed: Date())

        // LRU eviction: remove oldest entry if pool is full
        if entries.count > maxPoolSize {
            let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })
            if let oldest {
                await evictEntry(oldest.key)
            }
        }

        return device
    }

    private func evictEntry(_ identity: USBDeviceIdentity) async {
        if let entry = entries.removeValue(forKey: identity) {
            try? await entry.device.closeSession()
            // After closeSession(), MTPDevice.deinit fires via ARC since the pool
            // held the last strong reference. deinit calls transport.close(handle)
            // which releases the USB interface (libusb_release_interface + libusb_close + libusb_exit).
            // This chain ensures USB interfaces are always released, even on eviction.
        }
    }
}
```

`SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift`

```swift
extension MTPError {
    static func from(message: String) -> MTPError {
        if message.localizedCaseInsensitiveContains("not found") || message.localizedCaseInsensitiveContains("no device") {
            return .deviceNotFound(message)
        }
        if message.localizedCaseInsensitiveContains("connection") { return .connectionError(message) }
        if message.localizedCaseInsensitiveContains("timeout") { return .timeout(message) }
        if message.localizedCaseInsensitiveContains("busy") { return .deviceBusy(message) }
        if message.localizedCaseInsensitiveContains("device closed") { return .deviceClosed(message) }
        if message.localizedCaseInsensitiveContains("libusb") || message.localizedCaseInsensitiveContains("usb") { return .usbError(message) }
        if message.localizedCaseInsensitiveContains("device") { return .deviceError(message) }
        return .nonRecoverable(message)
    }

    /// Map MTP response codes to typed errors (MTP spec §11.3).
    /// Precondition: `responseCode` must NOT be RC_OK (0x2001). Callers should check
    /// `response.isOK` before calling this; reaching this function with RC_OK indicates
    /// a logic error in the caller, not an MTP error from the device.
    static func from(responseCode: UInt16) -> MTPError {
        switch responseCode {
        case 0x2001:
            assertionFailure("from(responseCode:) called with RC_OK — caller should have checked isOK first")
            return .invalidResponse
        case 0x201E: return .sessionAlreadyOpened
        case 0x2009: return .nonRecoverable("MTP invalid object handle")
        case 0x200C: return .storeFull
        case 0x200F: return .accessDenied
        default: return .nonRecoverable("MTP response code 0x\(String(responseCode, radix: 16))")
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .connectionError, .timeout, .deviceBusy, .deviceClosed, .usbError, .deviceNotFound:
            return true  // transport / enumeration failures are worth one bounded retry
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Add the app constants and re-run the focused tests**

`SwiftMTP/Config/AppConfiguration.swift`

```swift
// MARK: - MTPCore Pool Constants

static let mtpPoolMaxEntries: Int = 3
static let mtpPoolEntryTTLSeconds: TimeInterval = 120
static let mtpPoolCleanupIntervalSeconds: TimeInterval = 60
static let mtpQuickTimeoutSeconds: TimeInterval = 5
static let mtpDefaultTimeoutSeconds: TimeInterval = 45
static let mtpDownloadTimeoutSeconds: TimeInterval = 300
```

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPDevicePoolTests -only-testing:SwiftMTPTests/ErrorPathTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add the synchronous bridge for DispatchQueue-based callers**

`SwiftMTP/Services/MTPCore/MTPDevicePool+Sync.swift`

```swift
import Foundation

extension MTPDevicePool {
    private final class ResultBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?

        func store(_ newValue: T) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func load() -> T? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Synchronous wrapper for use from DispatchQueue-based callers (FileTransferManager).
    ///
    /// **Deadlock prevention:** `DispatchSemaphore.wait()` blocks the calling
    /// `transferQueue` thread, which is a GCD thread — NOT a Swift cooperative pool
    /// thread. Since `transferQueue` threads are not part of the cooperative pool,
    /// blocking them does not reduce the pool's capacity to execute the `Task` that
    /// drives `withDevice`. Multiple concurrent `withDeviceSync` calls each block
    /// their own `transferQueue` thread while the cooperative pool independently
    /// runs the async operations — no starvation, no deadlock.
    static func withDeviceSync<T: Sendable>(
        for identity: USBDeviceIdentity,
        operation: @Sendable (MTPDeviceProtocol) async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<Result<T, Error>>()

        // Task{} runs on Swift's cooperative thread pool, which is independent of
        // the transferQueue threads blocked on semaphore.wait(). As long as the
        // cooperative pool has free threads (guaranteed because we only block GCD
        // threads, not cooperative threads), the async work completes and signals.
        Task {
            defer { semaphore.signal() }
            do {
                let value = try await MTPDevicePool.shared.withDevice(for: identity, operation: operation)
                resultBox.store(.success(value))
            } catch {
                resultBox.store(.failure(error))
            }
        }

        semaphore.wait()
        guard let result = resultBox.load() else {
            throw MTPError.nonRecoverable("sync bridge completed without result")
        }
        return try result.get()
    }
}
```

This file is required by Task 10 Step 4 for `FileTransferManager` integration.

- [ ] **Step 6: Run the real-device smoke test through the pool**

Extend `SwiftMTPTests/MTPCore/ManualRealDeviceSmokeTests.swift` now that Task 8 adds the pool. Keep the original scanner/open smoke test, and add a second test that actually touches `MTPDevicePool.shared.withDevice(...)`:

```swift
func testPoolOpensRealDevice() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ENABLE_REAL_DEVICE_TESTS"] == "1")

    let transport = LibUSBTransport()
    let devices = try MTPDeviceScanner(transport: transport).scan()
    XCTAssertFalse(devices.isEmpty)

    let info = try await MTPDevicePool.shared.withDevice(for: devices[0].identity) { mtpDevice in
        try await mtpDevice.getDeviceInfo()
    }

    XCTAssertFalse(info.manufacturer.isEmpty || info.model.isEmpty)
}
```

Run:

```bash
ENABLE_REAL_DEVICE_TESTS=1 xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/ManualRealDeviceSmokeTests
```

Expected: the existing scanner smoke test still passes, and the new pool-backed open/device-info read passes too.

- [ ] **Step 7: Commit**

```bash
git add SwiftMTP/Services/MTPCore/MTPDevicePool.swift SwiftMTP/Services/MTPCore/MTPDevicePool+Sync.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPError.swift SwiftMTP/Config/AppConfiguration.swift SwiftMTPTests/MTPCore/MTPDevicePoolTests.swift SwiftMTPTests/MTPCore/ErrorPathTests.swift
git commit -m "feat(mtpcore): add pool, retry policy, and sync bridge"
```

### Task 9: Switch DeviceManager and FileSystemManager to MTPCore

**Files:**

- Modify: `SwiftMTP/Models/Device.swift`
- Modify: `SwiftMTP/Services/MTP/DeviceManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileSystemManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift`
- Modify: `SwiftMTP/Services/Protocols/DeviceManaging.swift`
- Modify: `SwiftMTP/Services/Protocols/FileSystemManaging.swift`
- Modify: `SwiftMTP/Views/FileBrowserView.swift`
- Test: `SwiftMTPTests/MTPCore/ServiceComparisonTests.swift`

**Breaking change:** `FileSystemManaging.getFileList` is currently synchronous (`func getFileList(...) -> [FileItem]`). Replacing `Kalam_ListFiles` with `await MTPDevicePool.shared.withDevice` requires changing the method to `func getFileList(...) async throws -> [FileItem]`. All call sites must add `try await`.

Complete call site inventory for the async migration:

| File                                        | Method                      | Current         | Change                       |
| ------------------------------------------- | --------------------------- | --------------- | ---------------------------- |
| `Protocols/FileSystemManaging.swift:21`     | protocol `getFileList`      | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Protocols/FileSystemManaging.swift:26`     | protocol `getRootFiles`     | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Protocols/FileSystemManaging.swift:33`     | protocol `getChildrenFiles` | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Services/MTP/FileSystemManager.swift`      | impl `getFileList`          | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Services/MTP/FileSystemManager.swift`      | impl `getRootFiles`         | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Services/MTP/FileSystemManager.swift`      | impl `getChildrenFiles`     | `-> [FileItem]` | `async throws -> [FileItem]` |
| `Views/FileBrowserView.swift`               | call `getRootFiles`         | `await ...`     | `try await ...`              |
| `Views/FileBrowserView.swift`               | call `getChildrenFiles`     | `await ...`     | `try await ...`              |
| `FileTransferManager+DirectoryUpload.swift` | call `getFileList`          | `await ...`     | `try await ...`              |

**Note:** Because `FileSystemManager` is an `actor`, callers already use `await`. The only change at each call site is adding `try`. The `loadFiles()` method in `FileBrowserView.swift` should also catch errors and display an alert.

**Cache-helper signature rule:** keep the existing cache helpers as actor-isolated synchronous methods:

```swift
func clearCache()
func forceClearCache()
func clearCache(for device: Device)
```

Callers still write `await` at use sites because they cross the `FileSystemManager` actor boundary. Do not redesign these helpers to become `async` just to match the call-site syntax.

- [ ] **Step 1: Write failing service-bridge tests**

```swift
import XCTest
@testable import SwiftMTP

final class ServiceComparisonTests: XCTestCase {
    func testDeviceSnapshotMapsToSidebarDevice() {
        let snapshot = MTPDeviceSnapshot(
            transportIdentity: USBDeviceIdentity(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 1),
            name: "Fixture Phone",
            manufacturer: "SwiftMTP",
            model: "Fixture Phone",
            serialNumber: "SN123",
            mtpVersion: "1.0",
            deviceVersion: "1.0",
            vendorExtensionDesc: "",
            storages: [MTPStorageSnapshot(id: 1, description: "Internal", freeSpace: 2048, maxCapacity: 4096)]
        )
        let device = DeviceManager.makeDevice(from: snapshot, stableID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, deviceIndex: 0)
        XCTAssertEqual(device.name, "Fixture Phone")
        XCTAssertEqual(device.storageInfo.first?.freeSpace, 2048)
    }
}
```

- [ ] **Step 2: Run the service comparison test**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/ServiceComparisonTests
```

Expected: build fails because the mapping helper does not exist.

- [ ] **Step 3: Add pure mapping helpers and replace the JSON bridge calls**

`SwiftMTP/Models/Device.swift`

Add `transportIdentity` field to the `Device` struct. The current init signature is:

```swift
init(id: UUID = UUID(), deviceIndex: Int, name: String, manufacturer: String,
     model: String, serialNumber: String, batteryLevel: Int?,
     storageInfo: [StorageInfo] = [], mtpSupportInfo: MTPSupportInfo? = nil,
     isConnected: Bool = true)
```

Change to:

```swift
struct Device: Identifiable, Hashable, Sendable {
    let id: UUID
    let deviceIndex: Int
    let transportIdentity: USBDeviceIdentity  // NEW: identifies device on USB bus
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let batteryLevel: Int?
    var storageInfo: [StorageInfo]
    var mtpSupportInfo: MTPSupportInfo?
    var isConnected: Bool

    init(id: UUID = UUID(), deviceIndex: Int, transportIdentity: USBDeviceIdentity,
         name: String, manufacturer: String, model: String, serialNumber: String,
         batteryLevel: Int?, storageInfo: [StorageInfo] = [],
         mtpSupportInfo: MTPSupportInfo? = nil, isConnected: Bool = true) {
        self.id = id
        self.deviceIndex = deviceIndex
        self.transportIdentity = transportIdentity
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.batteryLevel = batteryLevel
        self.storageInfo = storageInfo
        self.mtpSupportInfo = mtpSupportInfo
        self.isConnected = isConnected
    }
}
```

Keep the existing `Device` computed properties (`displayName`, `displayModel`, `totalCapacity`, `totalFreeSpace`), `Hashable` implementation, and preview fixture. This edit adds `transportIdentity`; it must not replace the whole model with only the fields shown above.

Complete call site inventory that must add `transportIdentity`:

| File                               | Context                | Migration                                                                                                 |
| ---------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------- |
| `Models/Device.swift:116`          | `static let preview`   | Add `transportIdentity: USBDeviceIdentity(vendorID: 0x18D1, productID: 0x4EE1, busNumber: 1, address: 1)` |
| `Services/MTP/DeviceManager.swift` | `mapToDevice(_:)`      | Replace `KalamDevice.id` → `transportIdentity` from scan result                                           |
| `SwiftMTPTests/**`                 | Any test `Device(...)` | Add `transportIdentity` parameter with fixture values                                                     |

`SwiftMTP/Services/MTP/DeviceManager.swift`

```swift
extension DeviceManager {
    static func makeDevice(from snapshot: MTPDeviceSnapshot, stableID: UUID, deviceIndex: Int) -> Device {
        Device(
            id: stableID,
            deviceIndex: deviceIndex,
            transportIdentity: snapshot.transportIdentity,
            name: snapshot.name,
            manufacturer: snapshot.manufacturer,
            model: snapshot.model,
            serialNumber: snapshot.serialNumber,
            batteryLevel: nil,
            mtpSupportInfo: MTPSupportInfo(
                mtpVersion: snapshot.mtpVersion,
                deviceVersion: snapshot.deviceVersion,
                vendorExtension: snapshot.vendorExtensionDesc
            ),
            storageInfo: snapshot.storages.map {
                StorageInfo(
                    storageId: $0.id,
                    maxCapacity: $0.maxCapacity,
                    freeSpace: $0.freeSpace,
                    description: $0.description
                )
            }
        )
    }
}
```

Remove the startup-only bridge init from `DeviceManager.init()` at the same time you replace scan. `Kalam_Init()` must be deleted in this task, not deferred to cleanup. `LibUSBTransport` owns libusb setup/teardown per operation, so there is no app-wide replacement initializer to add. The `KalamDevice`, `KalamMTPSupport`, `KalamStorage` JSON helper structs at the top of `DeviceManager.swift` should also be deleted here — they are only used by `mapToDevice`, which is replaced by `makeDevice(from:)`.

Replace the detached scan body with MTPCore calls. The current `scanDevices()` is synchronous and launches `Task.detached` internally. The MTPCore scan is also synchronous (libusb calls are blocking), but the pool's `withDevice` for snapshot reads is async. Keep the `Task.detached` wrapper and use the lightweight retry settings from Correction E:

```swift
let transport = LibUSBTransport()
let scannedDevices = try MTPDeviceScanner(transport: transport).scan()
var snapshots: [MTPDeviceSnapshot] = []

for scannedDevice in scannedDevices {
    do {
        let snapshot = try await MTPDevicePool.shared.withDevice(for: scannedDevice.identity, retries: 1, backoff: { _ in .milliseconds(200) }) { device in
            let manager = MTPDeviceManager(device: device, transportIdentity: scannedDevice.identity)
            return try await manager.initialize()
        }
        snapshots.append(snapshot)
    } catch {
        // Match go-mtpfs/select.go candidate handling: one endpoint-shaped
        // candidate can fail open/validation without hiding other usable devices.
        // Log and continue; only an empty final snapshot list means no usable device.
        print("[DeviceManager] Skipping unusable MTP candidate \(scannedDevice.identity): \(error)")
    }
}

guard !snapshots.isEmpty else {
    throw MTPError.deviceNotFound("no usable MTP devices after validation")
}

let devices = await MainActor.run {
    let duplicateSerials = Set(
        Dictionary(grouping: snapshots.compactMap { snapshot -> String? in
            let normalized = snapshot.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        }, by: { $0 })
        .filter { $0.value.count > 1 }
        .keys
    )

    snapshots.enumerated().map { index, snapshot in
        let stableID = self.cachedUUID(
            forSerial: snapshot.serialNumber,
            fallbackIdentity: snapshot.transportIdentity,
            duplicateSerials: duplicateSerials
        )
        return Self.makeDevice(from: snapshot, stableID: stableID, deviceIndex: index)
    }
}
```

**Main-thread rule:** do not call `cachedUUID(...)` from the detached background context. `DeviceManager` is `@MainActor`; collect raw snapshots off-main, then hop back to `MainActor.run` for stable-ID lookup and final `Device` mapping.

**Selection continuity and disconnect migration are part of Task 9 as well.** The current `DeviceManager` does not only cache IDs; it also uses device identity continuity to keep `selectedDevice` alive across rescans and to decide when to emit `DeviceDisconnected`. After adding `transportIdentity`, migrate those rules explicitly so multi-device scans and empty-serial devices stay stable:

```swift
private enum DeviceContinuityKey: Hashable {
    case serial(String)
    case transport(USBDeviceIdentity)
}

private func duplicateSerials(in devices: [Device]) -> Set<String> {
    Dictionary(grouping: devices.compactMap { device -> String? in
        let normalized = device.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }, by: { $0 })
    .filter { $0.value.count > 1 }
    .reduce(into: Set<String>()) { partialResult, element in
        partialResult.insert(element.key)
    }
}

private func continuityKey(serial: String, transportIdentity: USBDeviceIdentity, duplicateSerials: Set<String>) -> DeviceContinuityKey {
    let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty || duplicateSerials.contains(normalized) {
        return .transport(transportIdentity)
    }
    return .serial(normalized)
}

private func updateDevices(_ newDevices: [Device]) {
    let duplicateSerials = duplicateSerials(in: devices + newDevices)

    if let selected = selectedDevice {
        let selectedKey = continuityKey(
            serial: selected.serialNumber,
            transportIdentity: selected.transportIdentity,
            duplicateSerials: duplicateSerials
        )
        if let refreshedSelection = newDevices.first(where: {
            continuityKey(
                serial: $0.serialNumber,
                transportIdentity: $0.transportIdentity,
                duplicateSerials: duplicateSerials
            ) == selectedKey
        }) {
            selectedDevice = refreshedSelection
        } else if newDevices.isEmpty {
            handleDeviceDisconnection()
            return
        } else {
            // Only the selected device disappeared. Keep the remaining devices visible,
            // clear stale file UI state, and require the user to choose a new device.
            selectedDevice = nil
            connectionError = L10n.MainWindow.deviceDisconnected
            Task { await FileSystemManager.shared.clearCache() }
            NotificationCenter.default.post(name: NSNotification.Name("DeviceDisconnected"), object: nil)
        }
    }

    devices = newDevices
    lastDeviceSerials = Set(newDevices.compactMap { device in
        let normalized = device.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !duplicateSerials.contains(normalized) else { return nil }
        return normalized
    })

    if !newDevices.isEmpty {
        consecutiveFailures = 0
        currentScanInterval = userScanInterval
        showManualRefreshButton = false
    }

    if selectedDevice == nil && newDevices.count == 1 {
        selectedDevice = newDevices.first
    }
}
```

Do not keep the old "selected serial missing => clear the entire device list" behavior once Task 5's multi-device scanning is in place. Full disconnect (`newDevices.isEmpty`) and selected-device-only disconnect are separate cases after this migration. Also, once `transportIdentity` exists, empty serials and duplicate serials must both fall back to transport identity for continuity and disconnect decisions.

**UUID cache migration (replaces** **`NSCache<NSNumber, UUIDWrapper>`):**

The current `DeviceManager` uses `NSCache<NSNumber, UUIDWrapper>` keyed by `KalamDevice.id` (an `Int` assigned by the Go bridge). After migration, `KalamDevice.id` no longer exists, so the cache must be keyed by serial number instead. Replace both `deviceIdCache` and `deviceSerialCache` with a single serial-keyed cache:

```swift
// Replace the two NSCache fields:
//   private let deviceIdCache = NSCache<NSNumber, UUIDWrapper>()
//   private let deviceSerialCache = NSCache<NSNumber, NSString>()
// With a single serial-keyed cache:
private let deviceUUIDCache = NSCache<NSString, UUIDWrapper>()

private func cachedUUID(forSerial serial: String, fallbackIdentity: USBDeviceIdentity, duplicateSerials: Set<String>) -> UUID {
    // Prefer the real device serial when available and unique.
    // If the phone reports an empty serial, or if two attached devices report the same
    // serial, fall back to the current transport identity so the cache stays one-device-per-key.
    // This fallback is only stable for the lifetime of the current USB attachment; an
    // empty-serial or duplicate-serial device may receive a new UUID after unplug/replug
    // because bus/address can change.
    let key: NSString
    let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty || duplicateSerials.contains(normalized) {
        key = NSString(
            string: "transport:\(fallbackIdentity.vendorID)-\(fallbackIdentity.productID)-\(fallbackIdentity.busNumber)-\(fallbackIdentity.address)"
        )
    } else {
        key = NSString(string: "serial:\(normalized)")
    }
    if let cached = deviceUUIDCache.object(forKey: key) {
        return cached.uuid
    }
    let newUUID = UUID()
    deviceUUIDCache.setObject(UUIDWrapper(newUUID), forKey: key)
    return newUUID
}
```

Remove the old `deviceIdCache` and `deviceSerialCache` fields and their configuration in `init()`. The `UUIDWrapper` inner class remains unchanged.

Replace `Kalam_ListFiles` in `FileSystemManager`:

```swift
let entries = try await MTPDevicePool.shared.withDevice(for: device.transportIdentity) { device in
    let operations = MTPFileOperations(device: device)
    return try await operations.listFiles(storageID: storageId, parentID: parentId)
}

let items = entries.map {
    FileItem(
        objectId: $0.objectID,
        parentId: $0.parentID,
        storageId: $0.storageID,
        name: $0.name,
        path: $0.name,
        size: $0.size,
        modifiedDate: $0.modifiedDate,
        isDirectory: $0.isDirectory,
        fileType: $0.isDirectory ? "folder" : FileSystemManager.uppercaseString(($0.name as NSString).pathExtension)
    )
}
```

- [ ] **Step 4: Re-run the service comparison test and a full app build**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/ServiceComparisonTests
xcodebuild build -project SwiftMTP.xcodeproj -scheme SwiftMTP
```

Expected: the mapping test passes and the app still builds.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTP/Models/Device.swift SwiftMTP/Services/MTP/DeviceManager.swift SwiftMTP/Services/MTP/FileSystemManager.swift SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift SwiftMTP/Services/Protocols/DeviceManaging.swift SwiftMTP/Services/Protocols/FileSystemManaging.swift SwiftMTP/Views/FileBrowserView.swift SwiftMTPTests/MTPCore/ServiceComparisonTests.swift
git commit -m "refactor(app): switch device scan and file list to mtpcore"
```

### Task 10: Finish App Mutation Cutover to MTPCore

**Files:**

- Modify: `SwiftMTP/Services/MTP/FileSystemManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileTransferManager.swift`
- Modify: `SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift`
- Modify: `SwiftMTP/Services/Protocols/FileSystemManaging.swift`
- Modify: `SwiftMTP/Views/FileBrowserView+Actions.swift`
- Modify: `SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift`
- Test: `SwiftMTPTests/MTPCore/MTPFileOperationsTests.swift`
- Test: `SwiftMTPTests/MTPCore/ErrorPathTests.swift`

Complete remaining call-site inventory for this cutover:

| File                                                         | Method / Path                     | Bridge call to remove                             | Replacement                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------ | --------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Services/MTP/FileTransferManager.swift`                     | `cancelTask(_:)`                  | `Kalam_CancelTask`                                | cancel the per-task `TransferCancellationToken`, then set `task.isCancelled = true` and update status on `@MainActor`                                                                                                                                                       |
| `Services/MTP/FileTransferManager.swift`                     | `cancelAllTasks()`                | `Kalam_CancelTask`                                | cancel each per-task token first, then set `task.isCancelled = true`, update status, and move each active task to completed                                                                                                                                                  |
| `Views/FileBrowserView+Actions.swift`                        | `deleteFile(_:)`                  | `Kalam_DeleteObject`                              | `try await FileSystemManager.shared.deleteObject(...)`                                                                                                                                                                                                                        |
| `Views/FileBrowserView+Actions.swift`                        | `performBatchDelete(files:)`      | `Kalam_DeleteObject`                              | same FileSystemManager API inside the loop                                                                                                                                                                                                                                    |
| `Views/FileBrowserView+ToolbarDrop.swift`                    | `createFolder()`                  | `Kalam_CreateFolder`                              | `_ = try await FileSystemManager.shared.createFolder(...)`; return value is ignored by the UI action                                                                                                                                                                           |
| `Services/MTP/FileTransferManager+DirectoryUpload.swift`     | `getOrCreateFolder(...)`          | `Kalam_CreateFolder`                              | `let newFolderID = try await FileSystemManager.shared.createFolder(...)`; use returned handle as fallback if refreshed listing lags                                                                                                                                           |
| `Services/MTP/FileTransferManager+DirectoryUpload.swift`     | upload completion refresh         | `Kalam_RefreshStorage` + `Kalam_ResetDeviceCache` | clear FileSystemManager cache + trigger `DeviceManager.scanDevices()`                                                                                                                                                                                                         |
| `Services/MTP/FileTransferManager+DirectoryUpload.swift:348` | `performFileUploadWithoutTask`    | `Kalam_UploadFile`                                | use `MTPDevicePool.shared.withDevice` with `MTPFileOperations.uploadFile` (already async, no sync bridge needed)                                                                                                                                                              |
| `Services/MTP/FileTransferManager.swift:372`                 | `performUpload` success refresh   | `Kalam_RefreshStorage`                            | clear FileSystemManager cache, trigger `DeviceManager.scanDevices()`, and post `RefreshFileList` after a successful upload                                                                                                                                                    |
| `Services/MTP/FileTransferManager.swift:377`                 | `performUpload` cache reset       | `Kalam_ResetDeviceCache`                          | remove the standalone bridge reset; the same post-upload cache clear + device rescan path replaces it                                                                                                                                                                        |
| `Services/MTP/FileTransferManager.swift:224`                 | `performDownload` pre-scan        | `Kalam_Scan`                                      | Do not add a separate preflight scan. Let `MTPDevicePool.withDeviceSync` / `getOrCreateDevice` resolve current device presence, then map `MTPError.deviceNotFound`, `.deviceClosed`, and `.poolShutdown` back to the existing disconnect-specific localized error shown to the user. |
| `Services/MTP/FileTransferManager.swift:286`                 | `performDownload` error-path scan | `Kalam_Scan`                                      | Preserve the current user-visible split between disconnect errors and generic download failures, but do it by classifying the pool/device error that already came back instead of issuing another bridge scan after the failure.                                                                                   |
| `Services/MTP/FileTransferManager.swift:364`                 | `performUpload` error-path scan   | `Kalam_Scan`                                      | Same replacement as download: keep the disconnect-vs-generic upload error messaging, but derive it from the returned `MTPError` rather than reintroducing a post-failure `Kalam_Scan`.                                                                                                                            |

**Path-validation rule:** reuse the existing `FileTransferManager.validatePathSecurity(_:)` helper. This task does not introduce a new validator; it keeps the current upload-path security gate in front of the MTPCore call chain.

**Upload-size rule:** keep the enqueue-site preflight aligned with `MTPFileOperations.uploadFile(...)`. Files above `UInt32.max` must fail explicitly with a clear message; do not silently truncate or let the UI promise support that the `SendObjectInfo` wire format cannot honor yet.

**Directory-upload proof rule:** there is no pre-existing automated directory-upload suite in this repo. Treat behavior 9 as manual real-device verification in Task 11 step 4 item 9 unless a dedicated test is added in a later follow-up.

- [ ] **Step 1: Write the failing transfer tests for the remaining behaviors**

```swift
import XCTest
@testable import SwiftMTP

final class MTPFileOperationsTests: XCTestCase {
    func testDownloadEmptyFileCreatesZeroByteOutput() async throws {
        let operations = MTPFileOperations(device: MockDownloadDevice(fileBytes: Data()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty.dat")
        try await operations.downloadFile(objectID: 42, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 0)
    }

    func testUploadLargeFileStreamsFromDisk() async throws {
        let payload = Data(repeating: 0xAB, count: 1_048_576)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video.mp4")
        try payload.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let uploadDevice = MockUploadDevice()
        let operations = MTPFileOperations(device: uploadDevice)
        try await operations.uploadFile(from: url, storageID: 1, parentID: 0xFFFFFFFF)
        XCTAssertTrue(uploadDevice.sendObjectCalled)
        XCTAssertGreaterThan(uploadDevice.streamChunkCount, 1)
        XCTAssertLessThanOrEqual(uploadDevice.largestStreamChunk, 64 * 1024)
    }

    func testDownloadWithProgressReporting() async throws {
        let fileBytes = Data(repeating: 0xFF, count: 128 * 1024)
        let device = MockDownloadDevice(fileBytes: fileBytes)
        let operations = MTPFileOperations(device: device)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress_test.bin")
        var progressCalls: [(Int, Int)] = []
        try await operations.downloadFile(
            objectID: 1,
            to: url,
            progress: { read, total in progressCalls.append((read, total)) }
        )
        XCTAssertFalse(progressCalls.isEmpty)
        let last = progressCalls.last!
        XCTAssertEqual(last.0, last.1) // final call: read == total
    }

    func testUploadCancelledMidTransfer() async throws {
        let payload = Data(repeating: 0xAA, count: 256 * 1024)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cancel.mp4")
        try payload.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let device = MockUploadDevice()
        let operations = MTPFileOperations(device: device)
        var cancelAfterChunk = 0
        do {
            try await operations.uploadFile(
                from: url,
                storageID: 1,
                parentID: 0xFFFFFFFF,
                isCancelled: {
                    cancelAfterChunk += 1
                    return cancelAfterChunk > 2
                }
            )
            XCTFail("Should have thrown cancelled")
        } catch let error as MTPError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testDeleteObjectCallsDevice() async throws {
        let device = MockDeleteDevice()
        let operations = MTPFileOperations(device: device)
        try await operations.deleteObject(handle: 99)
        XCTAssertTrue(device.deleteCalled)
    }

    func testCreateFolderCallsDevice() async throws {
        let device = MockFolderDevice()
        let operations = MTPFileOperations(device: device)
        let handle = try await operations.createFolder(name: "TestFolder", storageID: 1, parentID: 0)
        XCTAssertTrue(device.createFolderCalled)
        XCTAssertEqual(handle, 999)
    }
}

final class MockDownloadDevice: MockMTPDevice {
    private let fileBytes: Data

    init(fileBytes: Data) {
        self.fileBytes = fileBytes
    }

    override func getObject(handle: UInt32) async throws -> Data {
        fileBytes
    }

    override func getObjectInfo(handle: UInt32) async throws -> MTPObjectInfo {
        MTPObjectInfo(storageID: 1, objectFormat: 0x3801, parentObject: 0xFFFFFFFF, objectCompressedSize: UInt64(fileBytes.count), filename: "test.bin")
    }

    override func downloadToStream(handle: UInt32, totalSize: Int, output: FileHandle, chunkSize: Int, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        try output.write(contentsOf: fileBytes)
        progress(fileBytes.count, fileBytes.count)
    }
}

final class MockUploadDevice: MockMTPDevice {
    private(set) var sendObjectCalled = false
    private(set) var streamChunkCount = 0
    private(set) var largestStreamChunk = 0

    override func sendObjectInfo(filename: String, size: UInt32, storageID: UInt32, parentID: UInt32) async throws -> MTPObjectInfo {
        MTPObjectInfo(objectHandle: 42, storageID: storageID, objectFormat: 0x3000, parentObject: parentID, objectCompressedSize: size, filename: filename)
    }

    override func sendObjectStream(objectHandle: UInt32, sourceURL: URL, progress: @Sendable (Int, Int) -> Void, isCancelled: @Sendable () -> Bool) async throws {
        sendObjectCalled = true
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let totalBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }

        var offset = 0
        while true {
            guard !isCancelled() else { throw MTPError.cancelled }
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            streamChunkCount += 1
            largestStreamChunk = max(largestStreamChunk, chunk.count)
            offset += chunk.count
            progress(offset, totalBytes)
        }
    }
}

final class MockDeleteDevice: MockMTPDevice {
    private(set) var deleteCalled = false

    override func deleteObject(handle: UInt32) async throws {
        deleteCalled = true
    }
}

final class MockFolderDevice: MockMTPDevice {
    private(set) var createFolderCalled = false

    override func createFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32 {
        createFolderCalled = true
        return 999
    }
}
```

- [ ] **Step 2: Run the focused transfer tests**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPFileOperationsTests -only-testing:SwiftMTPTests/ErrorPathTests
```

Expected: the new transfer and mutation cases fail.

- [ ] **Step 3: Add the missing MTPCore file operations**

`SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift`

```swift
extension MTPFileOperations {
    func downloadFile(objectID: UInt32, to destinationURL: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }, isCancelled: @Sendable () -> Bool = { false }) async throws {
        // Get object info first to know total size
        let info = try await device.getObjectInfo(handle: objectID)
        // `getObjectInfo` already resolves the 0xffffffff sentinel via OPC_ObjectSize,
        // matching the current Go stack's large-file metadata semantics.
        guard info.objectCompressedSize <= UInt64(Int.max) else {
            throw MTPError.nonRecoverable("File too large for local process accounting.")
        }
        let totalSize = Int(info.objectCompressedSize)

        if totalSize == 0 {
            // Intentional migration fix: zero-byte downloads are treated as success in
            // MTPCore even though the current Go bridge rejects them as invalid output.
            // Success Criteria #16 depends on keeping this behavior change explicit.
            try Data().write(to: destinationURL, options: .atomic)
            progress(0, 0)
            return
        }

        // Stream download: write each chunk to disk immediately via FileHandle.
        // This avoids buffering the entire file in memory (critical for files >100MB).
        // Task 10's higher-level `performDownload(...)` keeps the current replace /
        // do-not-replace decision at the UI boundary, so this helper expects the final
        // destination path to be clear before the atomic rename below.
        let tempURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).download")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)

        do {
            try await device.downloadToStream(
                handle: objectID,
                totalSize: totalSize,
                output: output,
                chunkSize: 64 * 1024,
                progress: progress,
                isCancelled: isCancelled
            )
            try output.close()
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    func uploadFile(from sourceURL: URL, storageID: UInt32, parentID: UInt32, progress: @Sendable (Int, Int) -> Void = { _, _ in }, isCancelled: @Sendable () -> Bool = { false }) async throws {
        guard !isCancelled() else { throw MTPError.cancelled }
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        guard let sizeNumber = attributes[.size] as? NSNumber else {
            throw MTPError.nonRecoverable("Unable to determine file size for \(sourceURL.lastPathComponent).")
        }
        let size = sizeNumber.uint64Value
        // MTP SendObjectInfo uses a UInt32 ObjectCompressedSize field on the wire.
        // The current app's front-end validation allows files up to 10GB, but this
        // MTPCore path must fail explicitly above UInt32.max until a later
        // SetObjectPropList-based follow-up lands. Do not silently truncate.
        guard size <= UInt64(UInt32.max) else { throw MTPError.nonRecoverable("File too large for MTP SendObjectInfo (>\(UInt32.max) bytes). Use SetObjectPropList for files >4GB.") }
        let objectInfo = try await device.sendObjectInfo(filename: sourceURL.lastPathComponent, size: UInt32(size), storageID: storageID, parentID: parentID)
        // Stream from disk so large uploads keep Go-era constant-memory behavior.
        try await device.sendObjectStream(
            objectHandle: objectInfo.objectHandle,
            sourceURL: sourceURL,
            progress: progress,
            isCancelled: isCancelled
        )
        progress(Int(size), Int(size))
    }

    func deleteObject(handle: UInt32) async throws {
        try await device.deleteObject(handle: handle)
    }

    func createFolder(name: String, storageID: UInt32, parentID: UInt32) async throws -> UInt32 {
        try await device.createFolder(name: name, storageID: storageID, parentID: parentID)
    }
}
```

- [ ] **Step 4: Replace the Go calls in the transfer manager, directory-upload helper, and remaining mutating UI actions without changing the queue-based concurrency model**

Use `MTPDevicePool.withDeviceSync` (from Task 8's `MTPDevicePool+Sync.swift`) to bridge async MTPCore calls from `FileTransferManager`'s `DispatchQueue`-based methods. This avoids the cooperative thread pool starvation and deadlock risks of the raw `DispatchSemaphore` + `Task {}` pattern.

Add a lock-backed cancellation token to `FileTransferManager` and use it for every background transfer path. Do not read `TransferTask.isCancelled` from a background `@Sendable` closure; `TransferTask` stays `@MainActor`.

```swift
private final class TransferCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private let cancellationTokensLock = NSLock()
private var cancellationTokens: [UUID: TransferCancellationToken] = [:]

private func makeCancellationToken(for taskID: UUID) -> TransferCancellationToken {
    let token = TransferCancellationToken()
    cancellationTokensLock.lock()
    cancellationTokens[taskID] = token
    cancellationTokensLock.unlock()
    return token
}

private func cancellationToken(for taskID: UUID) -> TransferCancellationToken? {
    cancellationTokensLock.lock()
    defer { cancellationTokensLock.unlock() }
    return cancellationTokens[taskID]
}

private func removeCancellationToken(for taskID: UUID) {
    cancellationTokensLock.lock()
    cancellationTokens.removeValue(forKey: taskID)
    cancellationTokensLock.unlock()
}
```

Wire the token at the enqueue sites too; do not leave this implicit. `downloadFile(from:...)` and `uploadFile(to:...)` should register the token before work is queued, and the queued closure should pass that token into `performDownload` / `performUpload`:

```swift
func downloadFile(from device: Device, fileItem: FileItem, to destinationURL: URL, shouldReplace: Bool = false) {
    let task = TransferTask(
        type: .download,
        fileName: fileItem.name,
        sourceURL: URL(fileURLWithPath: "/device/\(fileItem.objectId)"),
        destinationPath: destinationURL.path,
        totalSize: fileItem.size
    )
    let token = makeCancellationToken(for: task.id)

    DispatchQueue.main.async {
        self.activeTasks.append(task)
    }

    transferQueue.async {
        self.performDownload(
            task: task,
            token: token,
            device: device,
            fileItem: fileItem,
            shouldReplace: shouldReplace
        )
    }
}

func uploadFile(to device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
    guard !sourceURL.path.isEmpty else { return }
    guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
    if isDirectory.boolValue { return }

    guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
          let fileSize = fileAttributes[.size] as? UInt64 else {
        return
    }

    let maxFileSize = min(UInt64(10 * 1024 * 1024 * 1024), UInt64(UInt32.max))
    guard fileSize <= maxFileSize else { return }
    guard validatePathSecurity(sourceURL) else { return }
    guard let storage = device.storageInfo.first(where: { $0.storageId == storageId }) else { return }
    if fileSize > storage.freeSpace { return }

    let task = TransferTask(
        type: .upload,
        fileName: sourceURL.lastPathComponent,
        sourceURL: sourceURL,
        destinationPath: "/device/\(parentId)",
        totalSize: fileSize
    )
    let token = makeCancellationToken(for: task.id)

    DispatchQueue.main.async {
        self.activeTasks.append(task)
    }

    transferQueue.async {
        self.performUpload(
            task: task,
            token: token,
            device: device,
            sourceURL: sourceURL,
            parentId: parentId,
            storageId: storageId
        )
    }
}
```

Update `cancelTask(_:)` and `cancelAllTasks()` so they cancel the token first, then update the `TransferTask` on `@MainActor`:

```swift
func cancelTask(_ task: TransferTask) {
    cancellationToken(for: task.id)?.cancel()
    Task { @MainActor in
        task.isCancelled = true
        task.updateStatus(.cancelled)
        moveTaskToCompleted(task)
    }
}

func cancelAllTasks() {
    let tasksToCancel = activeTasks

    for task in tasksToCancel {
        cancellationToken(for: task.id)?.cancel()
    }

    Task { @MainActor in
        for task in tasksToCancel {
            task.isCancelled = true
            task.updateStatus(.cancelled)
            moveTaskToCompleted(task)
        }
    }
}
```

Inside `FileTransferManager.performDownload`:

**Note on** **`TransferTask`** **API:** The actual `TransferTask.updateProgress` signature is `func updateProgress(transferred: UInt64, speed: Double)`. The progress callback from MTPCore provides `(bytesRead, totalBytes)`. Convert at the call site: compute speed from delta bytes / delta time, or pass `0` for speed if not tracking.

```swift
private func performDownload(task: TransferTask, token: TransferCancellationToken, device: Device, fileItem: FileItem, shouldReplace: Bool) {
    var lastProgressTime = Date()
    var lastProgressBytes: UInt64 = 0

    defer { removeCancellationToken(for: task.id) }
    DispatchQueue.main.async { task.updateStatus(.transferring) }

    let destinationURL = URL(fileURLWithPath: task.destinationPath)
    let destinationDir = destinationURL.deletingLastPathComponent()

    do {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
    } catch {
        DispatchQueue.main.async {
            task.updateStatus(.failed(L10n.FileTransfer.cannotCreateDirectory.localized(error.localizedDescription)))
        }
        moveTaskToCompleted(task)
        return
    }

    if FileManager.default.fileExists(atPath: task.destinationPath) {
        if shouldReplace {
            do {
                try FileManager.default.removeItem(atPath: task.destinationPath)
            } catch {
                DispatchQueue.main.async {
                    task.updateStatus(.failed(L10n.FileTransfer.cannotReplaceExistingFile.localized(error.localizedDescription)))
                }
                moveTaskToCompleted(task)
                return
            }
        } else {
            DispatchQueue.main.async {
                task.updateStatus(.failed(L10n.FileTransfer.fileAlreadyExistsAtDestination))
            }
            moveTaskToCompleted(task)
            return
        }
    }

    do {
        try MTPDevicePool.withDeviceSync(for: device.transportIdentity) { mtpDevice in
            let operations = MTPFileOperations(device: mtpDevice)
            try await operations.downloadFile(
                objectID: fileItem.objectId,
                to: destinationURL,
                progress: { read, total in
                    DispatchQueue.main.async {
                        let now = Date()
                        let elapsed = max(now.timeIntervalSince(lastProgressTime), 0.001)
                        let deltaBytes = UInt64(read) - lastProgressBytes
                        let speed = Double(deltaBytes) / elapsed
                        lastProgressBytes = UInt64(read)
                        lastProgressTime = now
                        task.updateProgress(transferred: UInt64(read), speed: speed)
                    }
                },
                isCancelled: { token.isCancelled() }
            )
        }
        DispatchQueue.main.async { task.updateStatus(.completed) }
    } catch {
        let message: String
        if let mtpError = error as? MTPError {
            switch mtpError {
            case .deviceNotFound, .deviceClosed, .poolShutdown:
                message = L10n.FileTransfer.deviceDisconnectedCheckUSB
            default:
                message = L10n.FileTransfer.checkConnectionAndStorage
            }
        } else {
            message = L10n.FileTransfer.downloadFailed
        }
        DispatchQueue.main.async { task.updateStatus(.failed(message)) }
    }

    moveTaskToCompleted(task)
}
```

Inside `FileTransferManager.performUpload`:

**Required parity note:** do not use `Data(contentsOf: sourceURL)` here. The current Go-backed app streams uploads from disk, and this migration must preserve that behavior. The upload path in this task is expected to read from disk in fixed-size chunks all the way down to the USB write loop.

```swift
private func performUpload(task: TransferTask, token: TransferCancellationToken, device: Device, sourceURL: URL, parentId: UInt32, storageId: UInt32) {
    defer {
        removeCancellationToken(for: task.id)
        moveTaskToCompleted(task)
    }
    DispatchQueue.main.async { task.updateStatus(.transferring) }

    do {
        var lastProgressTime = Date()
        var lastProgressBytes: UInt64 = 0

        try MTPDevicePool.withDeviceSync(for: device.transportIdentity) { mtpDevice in
            let operations = MTPFileOperations(device: mtpDevice)
            try await operations.uploadFile(
                from: sourceURL,
                storageID: storageId,
                parentID: parentId,
                progress: { written, total in
                    DispatchQueue.main.async {
                        let now = Date()
                        let elapsed = max(now.timeIntervalSince(lastProgressTime), 0.001)
                        let deltaBytes = UInt64(written) - lastProgressBytes
                        let speed = Double(deltaBytes) / elapsed
                        lastProgressBytes = UInt64(written)
                        lastProgressTime = now
                        task.updateProgress(transferred: UInt64(written), speed: speed)
                    }
                },
                isCancelled: { token.isCancelled() }
            )
        }
        DispatchQueue.main.async { task.updateStatus(.completed) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                await FileSystemManager.shared.clearCache(for: device)
                await FileSystemManager.shared.forceClearCache()
                DeviceManager.shared.scanDevices()
                NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
            }
        }
    } catch {
        let message: String
        if let mtpError = error as? MTPError {
            switch mtpError {
            case .deviceNotFound, .deviceClosed, .poolShutdown:
                message = L10n.FileTransfer.deviceDisconnectedCheckUSB
            default:
                message = L10n.FileTransfer.uploadFailed
            }
        } else {
            message = L10n.FileTransfer.uploadFailed
        }
        DispatchQueue.main.async { task.updateStatus(.failed(message)) }
    }
}
```

Do not trigger the post-upload rescan immediately. The Go bridge currently gets a short stabilization window from `Kalam_RefreshStorage` / `Kalam_ResetDeviceCache`; the Swift path should preserve that timing with a delayed cache clear + device rescan:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task { @MainActor in
        await FileSystemManager.shared.clearCache(for: device)
        await FileSystemManager.shared.forceClearCache()
        DeviceManager.shared.scanDevices()
        NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
    }
}
```

Directory uploads need the same treatment; do not leave the synthetic task half-wired. Replace the old `directoryUploadCancelled` bool/lock with a tracked task ID plus the same cancellation-token map, register the token immediately after creating the synthetic task, and remove it in `defer` when `uploadDirectory(...)` exits:

```swift
private let directoryTaskLock = NSLock()
private var currentDirectoryUploadTaskID: UUID?

private func setCurrentDirectoryUploadTaskID(_ taskID: UUID?) {
    directoryTaskLock.lock()
    currentDirectoryUploadTaskID = taskID
    directoryTaskLock.unlock()
}

func cancelDirectoryUpload() {
    directoryTaskLock.lock()
    let taskID = currentDirectoryUploadTaskID
    directoryTaskLock.unlock()

    if let taskID {
        cancellationToken(for: taskID)?.cancel()
    }
}

func uploadDirectory(
    to device: Device,
    sourceURL: URL,
    parentId: UInt32,
    storageId: UInt32,
    progressHandler: ((Int, Int) -> Void)? = nil
) async -> DirectoryUploadResult {
    let filesToUpload = collectFilesInDirectory(sourceURL)
    guard !filesToUpload.isEmpty else {
        return DirectoryUploadResult(totalFiles: 0, uploadedFiles: 0, failedFiles: 0, skippedFiles: 0, errors: ["No files found in directory"])
    }

    let totalSize: UInt64 = filesToUpload.reduce(0) { sum, url in
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        return sum + fileSize
    }

    if let storage = device.storageInfo.first(where: { $0.storageId == storageId }),
       totalSize > storage.freeSpace {
        let needed = FileItem.formatFileSize(totalSize)
        let available = FileItem.formatFileSize(storage.freeSpace)
        return DirectoryUploadResult(
            totalFiles: filesToUpload.count,
            uploadedFiles: 0,
            failedFiles: filesToUpload.count,
            skippedFiles: 0,
            errors: ["Insufficient storage space: needed \(needed), available \(available)"]
        )
    }

    let directoryTask = TransferTask(
        type: .upload,
        fileName: "📁 \(sourceURL.lastPathComponent)",
        sourceURL: sourceURL,
        destinationPath: "/device/\(parentId)",
        totalSize: totalSize
    )
    let token = makeCancellationToken(for: directoryTask.id)
    setCurrentDirectoryUploadTaskID(directoryTask.id)

    defer {
        removeCancellationToken(for: directoryTask.id)
        setCurrentDirectoryUploadTaskID(nil)
    }

    await MainActor.run {
        self.activeTasks.append(directoryTask)
        directoryTask.updateStatus(.transferring)
    }

    let dirName = sourceURL.lastPathComponent
    let targetFolderId = await getOrCreateFolder(
        device: device,
        folderName: dirName,
        parentId: parentId,
        storageId: storageId
    )

    guard targetFolderId != 0 else {
        let message = "Failed to create target folder: \(dirName)"
        await MainActor.run {
            directoryTask.updateStatus(.failed(message))
            self.moveTaskToCompleted(directoryTask)
        }
        return DirectoryUploadResult(
            totalFiles: filesToUpload.count,
            uploadedFiles: 0,
            failedFiles: filesToUpload.count,
            skippedFiles: 0,
            errors: [message]
        )
    }

    var uploadedCount = 0
    var failedCount = 0
    var skippedCount = 0
    var errors: [String] = []
    var totalTransferred: UInt64 = 0
    let basePath = sourceURL.path
    var folderCache: [String: UInt32] = [:]

    for (index, fileURL) in filesToUpload.enumerated() {
        if token.isCancelled() {
            skippedCount = filesToUpload.count - index
            errors.append("Upload cancelled by user")
            break
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
        if let storage = device.storageInfo.first(where: { $0.storageId == storageId }) {
            let remainingSpace = storage.freeSpace > totalTransferred ? storage.freeSpace - totalTransferred : 0
            if fileSize > remainingSpace {
                let needed = FileItem.formatFileSize(fileSize)
                let available = FileItem.formatFileSize(remainingSpace)
                failedCount += 1
                errors.append("Insufficient storage for \(fileURL.lastPathComponent): needed \(needed), available \(available)")
                continue
            }
        }

        guard let relativePath = getRelativePath(from: basePath, to: fileURL.path) else {
            failedCount += 1
            errors.append("Failed to get relative path: \(fileURL.lastPathComponent)")
            continue
        }

        let subFolderId = await createSubdirectoryStructure(
            device: device,
            relativePath: relativePath,
            baseFolderId: targetFolderId,
            storageId: storageId,
            folderCache: &folderCache
        )

        guard subFolderId != 0 else {
            failedCount += 1
            errors.append("Failed to create subdirectory: \(relativePath)")
            continue
        }

        let success = await performFileUploadWithoutTask(
            device: device,
            sourceURL: fileURL,
            parentId: subFolderId,
            storageId: storageId,
            isCancelled: { token.isCancelled() }
        )

        if success {
            uploadedCount += 1
            totalTransferred += fileSize
        } else if token.isCancelled() {
            skippedCount = filesToUpload.count - index
            errors.append("Upload cancelled by user")
            break
        } else {
            failedCount += 1
            errors.append("Failed to upload: \(fileURL.lastPathComponent)")
        }

        await MainActor.run {
            directoryTask.updateProgress(transferred: totalTransferred, speed: 0)
        }

        progressHandler?(index + 1, filesToUpload.count)
    }

    let finalStatus: TransferStatus
    if token.isCancelled() {
        finalStatus = .cancelled
    } else if failedCount == 0 {
        finalStatus = .completed
    } else if uploadedCount == 0 {
        finalStatus = .failed("All files failed to upload")
    } else {
        finalStatus = .completed
    }
    await MainActor.run {
        directoryTask.updateStatus(finalStatus)
        self.moveTaskToCompleted(directoryTask)
    }

    if !token.isCancelled() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                await FileSystemManager.shared.clearCache(for: device)
                await FileSystemManager.shared.forceClearCache()
                DeviceManager.shared.scanDevices()
                NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
            }
        }
    }

    return DirectoryUploadResult(
        totalFiles: filesToUpload.count,
        uploadedFiles: uploadedCount,
        failedFiles: failedCount,
        skippedFiles: skippedCount,
        errors: errors
    )
}
```

Update `FileTransferManager+DirectoryUpload.swift` so folder creation also goes through `FileSystemManager` instead of `Kalam_CreateFolder`:

```swift
private func getOrCreateFolder(
    device: Device,
    folderName: String,
    parentId: UInt32,
    storageId: UInt32
) async -> UInt32 {
    do {
        let files = try await FileSystemManager.shared.getFileList(
            for: device,
            parentId: parentId,
            storageId: storageId
        )

        if let existingFolder = files.first(where: {
            $0.isDirectory && $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }) {
            return existingFolder.objectId
        }

        let newFolderID = try await FileSystemManager.shared.createFolder(
            named: folderName,
            parentId: parentId,
            storageId: storageId,
            device: device
        )

        let updatedFiles = try await FileSystemManager.shared.getFileList(
            for: device,
            parentId: parentId,
            storageId: storageId
        )

        return updatedFiles.first(where: {
            $0.isDirectory && $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        })?.objectId ?? newFolderID
    } catch {
        return 0
    }
}
```

Replace `performFileUploadWithoutTask` — this method currently calls `Kalam_UploadFile` directly for individual files during directory upload:

```swift
private func performFileUploadWithoutTask(
    device: Device,
    sourceURL: URL,
    parentId: UInt32,
    storageId: UInt32,
    isCancelled: @Sendable () -> Bool = { false }
) async -> Bool {
    guard FileManager.default.fileExists(atPath: sourceURL.path),
          let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
          let fileSize = fileAttributes[.size] as? UInt64 else {
        return false
    }

    guard !isCancelled() else { return false }

    if let storage = device.storageInfo.first(where: { $0.storageId == storageId }),
       fileSize > storage.freeSpace {
        return false
    }

    do {
        try await MTPDevicePool.shared.withDevice(for: device.transportIdentity) { mtpDevice in
            let operations = MTPFileOperations(device: mtpDevice)
            try await operations.uploadFile(
                from: sourceURL,
                storageID: storageId,
                parentID: parentId,
                isCancelled: isCancelled
            )
        }
        return true
    } catch {
        return false
    }
}
```

Inside `FileTransferManager+DirectoryUpload.swift` after a successful directory upload:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task { @MainActor in
        await FileSystemManager.shared.clearCache(for: device)
        await FileSystemManager.shared.forceClearCache()
        DeviceManager.shared.scanDevices()
        NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
    }
}
```

Move delete and create-folder behind `FileSystemManager` so the full app cutover is complete before cleanup:

```swift
// In FileSystemManager
func createFolder(named folderName: String, parentId: UInt32, storageId: UInt32, device: Device) async throws -> UInt32 {
    let normalizedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
        throw MTPError.nonRecoverable("Folder name cannot be empty.")
    }
    guard normalizedName.count <= 255 else {
        throw MTPError.nonRecoverable("Folder name too long (\(normalizedName.count) chars).")
    }
    let invalidCharacters = CharacterSet(charactersIn: "/\\\\:*?\"<>|")
    guard normalizedName.rangeOfCharacter(from: invalidCharacters) == nil else {
        throw MTPError.nonRecoverable("Folder name contains invalid characters.")
    }

    let handle = try await MTPDevicePool.shared.withDevice(for: device.transportIdentity) { device in
        let operations = MTPFileOperations(device: device)
        try await operations.createFolder(name: normalizedName, storageID: storageId, parentID: parentId)
    }
    clearCache(for: device)
    return handle
}

func deleteObject(_ objectId: UInt32, device: Device) async throws {
    try await MTPDevicePool.shared.withDevice(for: device.transportIdentity) { device in
        let operations = MTPFileOperations(device: device)
        try await operations.deleteObject(handle: objectId)
    }
    clearCache(for: device)
}
```

**Update** **`FileSystemManaging`** **protocol** to include the new methods:

```swift
// Add to FileSystemManaging protocol:
func createFolder(named folderName: String, parentId: UInt32, storageId: UInt32, device: Device) async throws -> UInt32
func deleteObject(_ objectId: UInt32, device: Device) async throws
```

`SwiftMTP/Views/FileBrowserView+Actions.swift`

```swift
Task {
    do {
        try await FileSystemManager.shared.deleteObject(file.objectId, device: device)
        await loadFiles()
    } catch {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
    }
}
```

Update the batch-delete path in the same file so it also routes through `FileSystemManager`:

```swift
Task {
    var failedFiles: [String] = []

    for file in files {
        do {
            try await FileSystemManager.shared.deleteObject(file.objectId, device: device)
        } catch {
            failedFiles.append(file.name)
        }
    }

    await loadFiles()

    if !failedFiles.isEmpty {
        errorMessage = "The following files failed to delete:\n\n\(failedFiles.joined(separator: "\n"))"
        showingErrorAlert = true
    }

    selectedFiles.removeAll()
}
```

`SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift`

```swift
Task {
    do {
        _ = try await FileSystemManager.shared.createFolder(named: folderName, parentId: parentId, storageId: storageId, device: device)
        await loadFiles()
        showingCreateFolderDialog = false
        newFolderName = ""
    } catch {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
    }
}
```

- [ ] **Step 5: Re-run the transfer tests and a full build**

Run:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/MTPFileOperationsTests -only-testing:SwiftMTPTests/ErrorPathTests
xcodebuild build -project SwiftMTP.xcodeproj -scheme SwiftMTP
```

Expected: focused transfer/mutation tests pass and the app still builds.

- [ ] **Step 6: Commit**

```bash
git add SwiftMTP/Services/MTP/FileSystemManager.swift SwiftMTP/Services/MTP/FileTransferManager.swift SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift SwiftMTP/Views/FileBrowserView+Actions.swift SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift SwiftMTP/Services/MTPCore/MTPDevice/MTPFileOperations.swift SwiftMTPTests/MTPCore/MTPFileOperationsTests.swift SwiftMTPTests/MTPCore/ErrorPathTests.swift
git commit -m "refactor(app): finish mtpcore mutation cutover"
```

### Task 11: Remove Bridge Artifacts and Verify the Full Migration

**Files:**

- Modify: `SwiftMTP/App/SwiftMTPApp.swift`
- Modify: `SwiftMTP.xcodeproj/project.pbxproj`
- Modify: `Scripts/run_tests.sh`
- Modify: `setup-check.sh`
- Modify: `AGENTS.md`
- Modify: `SwiftMTP/Resources/Base.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/en.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ja.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ko.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/ru.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/fr.lproj/Localizable.strings`
- Modify: `SwiftMTP/Resources/de.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `docs/README.zh-CN.md`
- Modify: `docs/README.ja.md`
- Modify: `docs/README.ko.md`
- Modify: `docs/README.ru.md`
- Modify: `docs/README.fr.md`
- Modify: `docs/README.de.md`
- Modify: `docs/SwiftMTP.wiki/API.md`
- Modify: `docs/SwiftMTP.wiki/Architecture.md`
- Modify: `docs/SwiftMTP.wiki/Build-and-Deploy.md`
- Modify: `docs/SwiftMTP.wiki/Development-Setup.md`
- Modify: `docs/SwiftMTP.wiki/Home.md`
- Modify: `docs/SwiftMTP.wiki/Modules.md`
- Modify: `docs/SwiftMTP.wiki/FAQ.md`
- Modify: `docs/SwiftMTP.wiki/Testing.md`
- Modify: `docs/SwiftMTP.wiki/Troubleshooting.md`
- Modify: `docs/TESTING.md`
- Modify: `docs/sequence-diagrams.md`
- Modify: `docs/architecture-diagrams.md`
- Modify: `docs/WIKI.md`
- Modify: `CLAUDE.md`
- Delete: `SwiftMTP/SwiftMTP-Bridging-Header.h`
- Delete: `SwiftMTP/libkalam.dylib`
- Delete: `SwiftMTP/libkalam.h`
- Delete: `SwiftMTP/libusb-1.0.dylib`
- Delete: `Scripts/build_kalam.sh`
- Delete: `Native/`
- [ ] **Step 1: Write the final failing audit as a search-based test**

Run:

```bash
rg -n "Kalam_|libkalam|libkalam\.dylib|libusb-1\.0\.dylib|SwiftMTP-Bridging-Header|build_kalam|CGO|go-mtpx|Native/|Go bridge|Go kernel" . \
  -g '!docs/superpowers/specs/**' \
  -g '!docs/superpowers/plans/**' \
  -g '!build/**'
find SwiftMTP -maxdepth 1 \( -name 'libkalam.dylib' -o -name 'libusb-1.0.dylib' -o -name 'libkalam.h' -o -name 'SwiftMTP-Bridging-Header.h' \) -print
```

Expected: the commands print remaining Go/bridge references and any leftover bridge-era binaries in the app bundle root.

- [ ] **Step 2: Remove the bridge, project references, old build script, and stale docs**

Delete the files and folders:

```bash
rm -f SwiftMTP/SwiftMTP-Bridging-Header.h SwiftMTP/libkalam.dylib SwiftMTP/libkalam.h SwiftMTP/libusb-1.0.dylib Scripts/build_kalam.sh Scripts/record_mtp_fixtures.go
rm -rf Native
```

Update `SwiftMTPApp.swift` cleanup handler:

```swift
private func setupCleanupHandler() {
    NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
    ) { _ in
        assert(Thread.isMainThread, "termination handler must run on main thread")

        DeviceManager.shared.prepareForTermination()

        // Blocking shutdown: the pool must release all USB interfaces before
        // the process exits, otherwise a quick relaunch hits "device busy".
        // Keep Task 6's reset-on-close-failure behavior inside pool shutdown;
        // a failed CloseSession must still reset the USB handle before close.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await MTPDevicePool.shared.shutdown()
            semaphore.signal()
        }
        semaphore.wait()
    }
}
```

Update `project.pbxproj`:

```text
SWIFT_OBJC_BRIDGING_HEADER = "";   # or delete the build setting entirely — empty string may trigger Xcode warnings
HEADER_SEARCH_PATHS = (
    "$(SRCROOT)/SwiftMTP/CLibUSB",
);
```

**Prefer deleting the `SWIFT_OBJC_BRIDGING_HEADER` key entirely** from the build settings rather than setting it to `""`. An empty string may trigger a "bridging header not found" warning in some Xcode versions.
Also delete the `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` entries that embed `libkalam.dylib` and `libusb-1.0.dylib`; otherwise the target can keep trying to sign or embed files that were removed from disk.

Update docs, tooling, and localized UI strings so every build/test instruction uses `xcodebuild build` or `xcodebuild test` only, and remove all references to Go, `build_kalam.sh`, `libkalam`, `CGO`, `go-mtpx`, and `Native/`. This sweep must include repo-level guidance files such as `AGENTS.md` and `CLAUDE.md`, tooling scripts such as `setup-check.sh`, and the localized `builtWith` strings under `SwiftMTP/Resources/*.lproj/Localizable.strings`, not just product docs.

For the localization sweep, explicitly verify or add these keys in `Base`, `en`, `zh-Hans`, `ja`, `ko`, `ru`, `fr`, and `de`:

- `builtWith`
- `deviceDisconnectedCheckUSB`
- `checkConnectionAndStorage`
- `downloadFailed`
- `uploadFailed`
- `cannotCreateDirectory`
- `cannotReplaceExistingFile`
- `fileAlreadyExistsAtDestination`
- `mtp.error.accessDenied`
- `mtp.error.storeFull`
- `mtp.error.sessionAlreadyOpened`
- `mtp.error.cancelled`
- `mtp.error.poolShutdown`
- `mtp.error.invalidResponse`

- [ ] **Step 3: Run the full verification suite**

Run:

```bash
xcodebuild build -project SwiftMTP.xcodeproj -scheme SwiftMTP
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS'
desloppify scan --path .
rg -n "Kalam_|libkalam|libusb-1\.0\.dylib|SwiftMTP-Bridging-Header|build_kalam|CGO|go-mtpx|Native/|Go bridge|Go kernel" . \
  -g '!docs/superpowers/specs/**' \
  -g '!docs/superpowers/plans/**' \
  -g '!build/**'
find SwiftMTP -maxdepth 1 \( -name 'libkalam.dylib' -o -name 'libusb-1.0.dylib' -o -name 'libkalam.h' -o -name 'SwiftMTP-Bridging-Header.h' \) -print
ENABLE_REAL_DEVICE_TESTS=1 xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -only-testing:SwiftMTPTests/ManualRealDeviceSmokeTests
```

Expected:

- `xcodebuild build` succeeds
- `xcodebuild test` succeeds
- `desloppify scan --path .` ends with `Open: 0`
- the final `rg` command prints nothing
- the final `find` command prints nothing
- the real-device smoke test passes with a connected Android device
- [ ] **Step 4: Verify the full success-criteria table by hand**

Run the app and check these behaviors against a real device:

1. Plug and unplug the device and confirm the sidebar updates.
2. Confirm device name, manufacturer, model, and serial are shown.
3. Confirm storage description, free space, and capacity are shown.
4. Browse folders and confirm names, sizes, and modified dates.
5. Download a photo and confirm the file size matches on disk.
6. Upload a file and confirm it appears in the current folder.
7. Delete a file and confirm it disappears.
8. Create a folder and confirm it appears.
9. Upload a directory and confirm nested folders are preserved.
10. Start a transfer, cancel it, and confirm the task stops cleanly.
11. Upload a file and confirm free space decreases after refresh.
12. Clear cache by refreshing the folder and confirm the list is fresh.
13. Time two consecutive list operations and confirm the second run is below 500ms.
14. Force one transient failure in a mock test and confirm one retry succeeds.
15. Quit and relaunch the app immediately and confirm there is no `device busy` failure.
16. Download an empty file and confirm the result is zero bytes.
17. Download a file larger than 100MB and confirm it opens successfully via the default `GetObject` streaming path; do not require Android-only extensions for parity.
18. Plug in two devices at the same time and confirm both appear as separate sidebar entries and can be selected independently.
19. If two attached devices report the same serial, trigger repeated rescans without unplugging them and confirm selection continuity follows `transportIdentity` (bus + address) rather than collapsing them into one logical device during that attachment.
20. If a device reports an empty serial, rescan while it remains attached and confirm continuity/disconnect handling falls back to `transportIdentity` for the lifetime of that attachment. A fresh unplug/replug may legitimately assign a new UUID because bus/address can change.

- [ ] **Step 5: Commit**

```bash
git add SwiftMTP/App/SwiftMTPApp.swift SwiftMTP.xcodeproj/project.pbxproj Scripts/run_tests.sh setup-check.sh AGENTS.md SwiftMTP/Resources/Base.lproj/Localizable.strings SwiftMTP/Resources/en.lproj/Localizable.strings SwiftMTP/Resources/zh-Hans.lproj/Localizable.strings SwiftMTP/Resources/ja.lproj/Localizable.strings SwiftMTP/Resources/ko.lproj/Localizable.strings SwiftMTP/Resources/ru.lproj/Localizable.strings SwiftMTP/Resources/fr.lproj/Localizable.strings SwiftMTP/Resources/de.lproj/Localizable.strings README.md docs/README.zh-CN.md docs/README.ja.md docs/README.ko.md docs/README.ru.md docs/README.fr.md docs/README.de.md docs/SwiftMTP.wiki/API.md docs/SwiftMTP.wiki/Architecture.md docs/SwiftMTP.wiki/Build-and-Deploy.md docs/SwiftMTP.wiki/Development-Setup.md docs/SwiftMTP.wiki/Home.md docs/SwiftMTP.wiki/Modules.md docs/SwiftMTP.wiki/FAQ.md docs/SwiftMTP.wiki/Testing.md docs/SwiftMTP.wiki/Troubleshooting.md docs/TESTING.md docs/sequence-diagrams.md docs/architecture-diagrams.md docs/WIKI.md CLAUDE.md
git add -u
git commit -m "refactor(mtpcore): remove go bridge and finish native migration"
```

***

## Design Corrections

These notes keep the historical reasoning, but the task steps above are the only authoritative implementation instructions.

- **Correction A:** Device model migration and `transportIdentity` call-site inventory were folded into Task 9 Step 3.
- **Correction B:** `FileSystemManaging` async migration and affected call sites were folded into the Task 9 header.
- **Correction C:** `MTPDevicePool.withDeviceSync` and the `DispatchQueue`/`NSLock` transfer-model preservation were folded into Task 10 Step 4.
- **Correction D:** Swift-side cancellation design is now fully documented in Task 10 Step 4 instead of relying on Go-era `Kalam_CancelTask`.
- **Correction E:** The redundant `withDeviceQuick` path was removed; tasks now use `withDevice` with explicit retry settings where needed.
- **Correction F:** Fixture scope was tightened; Tasks 2-4 stay synthetic/spec-derived, and real-device confidence comes from Tasks 5, 8, and 11.
- **Correction G:** `MTPDevice` thread-safety expectations are documented inline in Task 6's code block.
- **Correction H:** Upload helper coverage is complete in Task 6; `performDelete`, `performSendObjectInfo`, `performSendObjectStream`, and `performCreateFolder` all live there.
- **Correction I:** The termination-handler safety fix is integrated into Task 11 Step 2.
- **Correction J:** `project.pbxproj` edit strategy is now reflected directly in Tasks 1 and 11, including post-edit verification via `xcodebuild -showBuildSettings`.
- **Correction K:** Pool cleanup moved to lazy startup and is integrated into Task 8 Step 3.
- **Correction L:** Download streaming replaced the old buffer-then-write path; the final design lives in Task 6 Step 3 and Task 10 Step 3.
- **Correction M:** Transfer speed is computed from per-callback deltas, and the final logic lives in Task 10 Step 4.
- **Correction N:** Large MTP payload reads now loop until `declaredPayload` is fully consumed; the final logic lives in Task 6 Step 3.
- **Correction O:** Task 3 now explicitly covers the full constant port plus deletion of `constants_reference.json`.
