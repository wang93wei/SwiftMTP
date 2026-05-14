# Go-to-Swift Migration Design Spec

**Date:** 2026-04-11
**Status:** Draft
**Scope:** Remove all Go/CGO dependencies, replace with native Swift + libusb

---

## 1. Goal

Eliminate the entire Go toolchain dependency (CGO bridge, `libkalam.dylib`, `Native/` directory). Replace with native Swift code that directly calls libusb-1.0 and implements the MTP/PTP protocol stack in Swift.

### Go Tool Policy

**Go is a migration-phase-only tool.** The fixture recording program (`Scripts/record_mtp_fixtures.go`) is a standalone CLI utility described here for reference but **not created in the implementation plan**. The plan's fixtures are synthetic (hand-crafted from the MTP spec), not hardware-captured. If real-device fixture capture is needed for debugging, this tool can be written ad-hoc and should:

- Live in `Scripts/` (not `Native/`) during migration
- NOT link against the project's Go bridge code — it has its own `main.go`
- Be deleted after Phase 3 when `Native/` is removed
- The final repository will contain **zero `.go` files**

### Success Criteria

The following behaviors must be preserved from the current Go-backed implementation. Each item is verifiable by connecting a real Android device:

| # | Behavior | Current Go Function | Verification |
|---|----------|-------------------|-------------|
| 1 | Detect USB MTP device connection/disconnection | `Kalam_Scan` | Plug/unplug device, verify device list updates in UI |
| 2 | Display device info (name, manufacturer, model, serial) | `Kalam_Scan` → DeviceInfo JSON | Compare device name/manufacturer shown in sidebar |
| 3 | Display storage info (description, free space, capacity) | `Kalam_Scan` → StorageInfo JSON | Compare storage free space / capacity values |
| 4 | Browse device filesystem (list files/folders) | `Kalam_ListFiles` | Navigate directories, verify file names/sizes/dates match |
| 5 | Download file from device to Mac | `Kalam_DownloadFile` | Download a photo, verify file size matches |
| 6 | Upload file from Mac to device | `Kalam_UploadFile` | Upload a file, verify it appears in device listing |
| 7 | Delete file on device | `Kalam_DeleteObject` | Delete a file, verify it disappears |
| 8 | Create folder on device | `Kalam_CreateFolder` | Create folder, verify it appears |
| 9 | Directory upload (recursive) | `FileTransferManager+DirectoryUpload` | Upload a folder with subfolders, verify structure preserved |
| 10 | Task cancellation during transfer | `Kalam_CancelTask` | Start download, cancel mid-transfer, verify clean stop |
| 11 | Storage refresh after upload | `Kalam_RefreshStorage` | Upload file, verify free space decreases |
| 12 | Device cache reset | `Kalam_ResetDeviceCache` | Call after upload, verify subsequent list is fresh |
| 13 | Connection pool reuse (2nd operation is faster than 1st) | `kalam_pool.go` | Time two consecutive file list operations; 2nd must complete in <500ms (no USB re-init) |
| 14 | Retry with backoff on transient errors | `withDevice` / `Kalam_DownloadFile` | Unit test: mock USB fails once then succeeds → verify operation completes and retry count is 1 |
| 15 | Clean shutdown (session close, interface release) | `MTPDevicePool.shutdown()` + `Kalam_CleanupDevicePool` | 1) Quit app, check Console.app for `MTPDevicePool: disposed N entries` log. 2) Relaunch app immediately, verify device scan succeeds without "device busy" error (proves USB interface was released) |
| 16 | Download empty file (0 bytes) | `Kalam_DownloadFile` | Download empty file, verify no crash |
| 17 | Large file download (≥100MB) | `Kalam_DownloadFile` | Download large video, verify integrity |
| 18 | Two devices scanned distinctly | `Kalam_Scan` (multi-device) | Plug in two devices, verify both appear as separate sidebar entries and can be selected independently |
| 19 | Duplicate serial continuity | `Kalam_Scan` | Two devices with same serial: rescan without unplugging, verify selection continuity follows `transportIdentity` (bus + address) |
| 20 | Empty serial continuity | `Kalam_Scan` | Device with empty serial: rescan while attached, verify continuity falls back to `transportIdentity` for lifetime of attachment |

**Non-functional criteria:**
- No `SwiftMTP-Bridging-Header.h`, no `libkalam.h` in final project
- No `build_kalam.sh` step required
- Swift MTP module test coverage ≥80%
- All MTPCore unit tests + integration tests pass in CI

---

## 2. Current Architecture (Before)

```
SwiftUI Views
  → Services (DeviceManager / FileSystemManager / FileTransferManager)
    → Bridging Header (SwiftMTP-Bridging-Header.h → libkalam.h)
      → C exported functions (Kalam_Scan, Kalam_ListFiles, etc.)
        → Go bridge (kalam_bridge*.go, ~863 lines)
          → go-mtpx (1,831 lines) / go-mtpfs/mtp (3,867 lines)
            → usb wrapper (863 lines CGo → libusb-1.0)
```

### Code Inventory

| Layer | Files | Lines |
|-------|-------|-------|
| Bridge (kalam_bridge*.go) | 2 | 863 |
| Connection pool (kalam_pool.go) | 1 | 409 |
| Domain model (kalam_domain.go) | 1 | 427 |
| Config (kalam_config.go) | 1 | 203 |
| **Go self-owned** | **5** | **1,902** |
| go-mtpfs/mtp (MTP protocol) | 9 | 3,867 |
| go-mtpx (high-level API) | 9 | 1,831 |
| usb (libusb wrapper) | 2 | 863 |
| **Vendor** | **20** | **6,561** |
| **Total** | **25** | **8,463** |

---

## 3. Target Architecture (After)

```
SwiftUI Views
  → Services (DeviceManager / FileSystemManager / FileTransferManager)
    → MTPDevice (Swift native, direct calls)
      → MTPProtocol (Swift native MTP binary protocol encode/decode)
        → USBTransport (thin Swift wrapper over libusb C API)
          → libusb-1.0 (C library, Swift C interop)
```

### Eliminated

- `SwiftMTP-Bridging-Header.h`
- `libkalam.h` / `libkalam.dylib`
- `build_kalam.sh`
- `Native/` directory (entire Go source tree)
- `Scripts/record_mtp_fixtures.go` (deleted after migration)
- Go toolchain dependency
- `Kalam_FreeString` / `Kalam_CleanupLeakedStrings` memory management
- JSON-over-C-strings serialization
- CGO overhead

---

## 4. Module Mapping

### 4.1 USB Transport Layer

| Go Source | Lines | Swift Target | Est. Lines |
|-----------|-------|-------------|------------|
| `usb/usb.go` | 745 | `USBTransport/USBDevice.swift` | ~200 |
| `usb/print.go` | 118 | `USBTransport/USBDebugLogger.swift` | ~80 |

**Rationale:** Go needs CGo boilerplate to call C functions. Swift calls libusb directly via C interop. The 745-line Go wrapper reduces to ~200 lines of Swift type-safe wrappers.

**USBDebugLogger includes:**
- USB class/request type → string mappings (from Go `print.go`)
- Bulk transfer hex dump for send/receive data packets
- USB operation logging (Open, Close, ClaimInterface, BulkTransfer with timing and status)
- Output via `os.Logger`, filterable in Console.app

### 4.2 MTP Protocol Layer

| Go Source | Lines | Swift Target | Est. Lines |
|-----------|-------|-------------|------------|
| `mtp/const.go` | 1,974 | `MTPProtocol/MTPConstants.swift` | ~1,800 |
| `mtp/types.go` | 170 | `MTPProtocol/MTPTypes.swift` | ~150 |
| `mtp/encoding.go` | 459 | `MTPProtocol/MTPEncoding.swift` | ~350 |
| `mtp/mtp.go` | 693 | `MTPDevice/MTPDevice.swift` | ~500 |
| `mtp/ops.go` | 220 | `MTPDevice/MTPDevice+Operations.swift` | ~180 |
| `mtp/select.go` | 172 | `MTPDevice/MTPDeviceScanner.swift` | ~130 |
| `mtp/android.go` | 81 | (eliminated — deferred to post-migration; `OC_GetPartialObject64` is optional optimization, not in migration parity path) | 0 |
| `mtp/nullreader.go` | 20 | (inline, not needed) | 0 |
| `mtp/print.go` | 78 | `MTPProtocol/MTPDebugLogger.swift` | ~50 |

### 4.3 MTP High-Level API

| Go Source | Lines | Swift Target | Est. Lines |
|-----------|-------|-------------|------------|
| `mtpx/main.go` | 702 | `MTPDevice/MTPDeviceManager.swift` | ~500 |
| `mtpx/helpers.go` | 572 | `MTPDevice/MTPFileOperations.swift` | ~400 |
| `mtpx/structs.go` | 113 | `MTPDevice/MTPDataStructures.swift` | ~90 |
| `mtpx/utils.go` | 260 | `MTPDevice/MTPUtilities.swift` | ~180 |
| `mtpx/errors.go` | 53 | `MTPDevice/MTPError.swift` | ~40 |
| `mtpx/const.go` | 20 | (inline into MTPConstants) | 0 |
| `mtpx/enums.go` | 8 | `MTPDevice/MTPDataStructures.swift` | (included) |
| `mtpx/env.go` | 5 | (not needed) | 0 |

### 4.4 Bridge Layer (Eliminated / Merged)

| Go Source | Lines | Swift Target |
|-----------|-------|-------------|
| `kalam_bridge.go` | 424 | **Eliminated** — logic merges into existing `DeviceManager`, `FileSystemManager` |
| `kalam_bridge_transfer.go` | 439 | **Eliminated** — logic merges into `FileTransferManager` |
| `kalam_pool.go` | 409 | `Services/MTPDevicePool.swift` (actor-based) |
| `kalam_domain.go` | 427 | **Merged** into existing `Models/` directory |
| `kalam_config.go` | 203 | **Merged** into existing `Config/AppConfiguration.swift` |

### Estimated Total

| | Go LOC | Swift LOC (est.) |
|---|--------|-----------------|
| USB transport | 863 | 280 |
| MTP protocol | 3,676 | 3,220 |
| MTP high-level | 1,738 | 1,210 |
| Pool + domain + config | 1,039 | ~400 (merged into existing) |
| **Total** | **7,316** | **~5,110** |

Swift is ~30% more concise due to: no CGo boilerplate, native C interop, Codable replacing manual JSON serialization, async/await replacing goroutine+channel patterns.

---

## 5. Technical Decisions

### 5.1 libusb Integration

Swift calls libusb-1.0 directly via C interop. No intermediate Go or CGo layer.

**Xcode integration via module.modulemap:**

Create `SwiftMTP/CLibUSB/module.modulemap`:

```
module CLibUSB {
    header "libusb.h"
    export *
}
```

**Path resolution:** The header path must NOT be hardcoded to `/opt/homebrew/` (Apple Silicon) or `/usr/local/` (Intel). Instead:

- Copy `libusb.h` into `SwiftMTP/CLibUSB/` directory (the header is small, ~1,200 lines, and stable)
- Or use Xcode's **Header Search Paths** with `$(HOMEbrew --prefix)/include/libusb-1.0` via build script
- The recommended approach: copy the header, so the project is self-contained and CI doesn't need Homebrew for compilation

**Static linking for distribution:**

Link against `libusb-1.0.a` to embed libusb into the app binary. No runtime dependency.

Xcode project settings:
- **Header Search Paths:** `$(PROJECT_DIR)/SwiftMTP/CLibUSB` (contains copied `libusb.h`)
- **Library Search Paths:** `/opt/homebrew/lib` (Apple Silicon) or `/usr/local/lib` (Intel) — only needed at compile time
- **Other Linker Flags:** `$(PROJECT_DIR)/lib/libusb-1.0.a` (checked-in prebuilt static lib, or resolved via Homebrew)
- **Import Path:** `$(PROJECT_DIR)/SwiftMTP/CLibUSB/` (for module map discovery)

**Recommended: check in a prebuilt `lib/libusb-1.0.a`** (universal binary or arm64-only) so CI and other developers don't need `brew install libusb`. The `.a` file is ~400KB and platform-specific. Update it when libusb releases a new version.

**获取预编译libusb静态库的方法：**
1. **推荐方式**：使用Homebrew安装后复制：
   ```bash
   # 安装libusb
   brew install libusb
   
   # 创建lib目录并复制静态库
   mkdir -p lib
   cp "$(brew --prefix libusb)/lib/libusb-1.0.a" lib/libusb-1.0.a
   
   # 复制头文件到项目
   mkdir -p SwiftMTP/CLibUSB
   cp "$(brew --prefix libusb)/include/libusb-1.0/libusb.h" SwiftMTP/CLibUSB/libusb.h
   ```

2. **手动构建**（如果Homebrew不可用）：
   ```bash
   # 下载libusb源码
   curl -L https://github.com/libusb/libusb/releases/download/v1.0.29/libusb-1.0.29.tar.bz2 | tar xj
   cd libusb-1.0.29
   
   # 配置并构建静态库（仅arm64）
   ./configure --disable-shared --enable-static --host=aarch64-apple-darwin
   make -j$(sysctl -n hw.ncpu)
   
   # 复制到项目
   cp libusb/.libs/libusb-1.0.a ../../lib/
   cp libusb/libusb.h ../../SwiftMTP/CLibUSB/
   ```

3. **CI/CD集成**：在CI脚本中添加libusb安装步骤：
   ```yaml
   # GitHub Actions示例
   - name: Install libusb
     run: brew install libusb
   
   - name: Copy libusb to project
     run: |
       mkdir -p lib SwiftMTP/CLibUSB
       cp "$(brew --prefix libusb)/lib/libusb-1.0.a" lib/
       cp "$(brew --prefix libusb)/include/libusb-1.0/libusb.h" SwiftMTP/CLibUSB/
   ```

**DMG packaging impact:**
- Remove `cp libusb-1.0.dylib` step from build scripts
- Remove `install_name_tool -change` and `install_name_tool -id` for libusb
- Remove libusb codesigning step
- Only the app binary itself needs signing (libusb is baked in)

```swift
import CLibUSB

struct USBHandleRef: @unchecked Sendable {
    let context: OpaquePointer?      // libusb_context*
    let handle: OpaquePointer?       // libusb_device_handle*
    let interfaceNumber: Int32
    let configurationValue: UInt8
    let interfaceStringIndex: UInt8
    let sendMaxPacketSize: Int
    let fetchMaxPacketSize: Int
    let endpoints: USBEndpoints
}
```

**Design note:** The plan uses `@unchecked Sendable` instead of `~Copyable` for simplicity. The pool's per-device exclusivity prevents double-close via concurrent access. The `@unchecked Sendable` annotation is safe because `USBHandleRef` is only mutated through `MTPDevice` methods, which are protected by the pool.

### 5.2 MTP Binary Encoding

Go uses `reflect`-based generic encode/decode. Swift uses `Data` + `LittleEndian` + protocol-based approach:

```swift
protocol MTPEncodable {
    func encode(to writer: inout MTPDataWriter) throws
}

protocol MTPDecodable {
    init(from reader: inout MTPDataReader) throws
}

struct MTPDataWriter {
    private var data = Data()

    mutating func writeUInt16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeString(_ s: String) throws {
        // MTP string: uint8 length, UTF-16LE codepoints, null terminator
        // Same logic as Go's encodeStr()
        let utf16 = Array(s.utf16)
        let length = UInt8(utf16.count)
        data.append(length)

        for codeUnit in utf16 {
            writeUInt16(codeUnit)
        }

        // Null terminator
        writeUInt16(0)
    }

    mutating func writeData(_ newData: Data) {
        data.append(newData)
    }

    var bytes: Data {
        return data
    }
}

struct MTPDataReader {
    private let data: Data
    private var offset: Data.Index

    init(from data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func readUInt16() throws -> UInt16 {
        let size = MemoryLayout<UInt16>.size
        guard offset + size <= data.endIndex else {
            throw MTPError.invalidResponse
        }
        let value = data[offset..<offset+size].withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        offset += size
        return UInt16(littleEndian: value)
    }

    mutating func readUInt32() throws -> UInt32 {
        let size = MemoryLayout<UInt32>.size
        guard offset + size <= data.endIndex else {
            throw MTPError.invalidResponse
        }
        let value = data[offset..<offset+size].withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        offset += size
        return UInt32(littleEndian: value)
    }

    mutating func readString() throws -> String {
        // MTP string: uint8 length, UTF-16LE codepoints, null terminator
        guard offset < data.endIndex else {
            throw MTPError.invalidResponse
        }
        let length = Int(data[offset])
        offset += 1

        guard offset + (length + 1) * 2 <= data.endIndex else {
            throw MTPError.invalidResponse
        }

        var codeUnits: [UInt16] = []
        for _ in 0..<length {
            let codeUnit = try readUInt16()
            codeUnits.append(codeUnit)
        }

        // Skip null terminator
        _ = try readUInt16()

        guard let string = String(utf16CodeUnits: codeUnits, count: codeUnits.count) else {
            throw MTPError.invalidResponse
        }
        return string
    }

    mutating func readData(count: Int) throws -> Data {
        guard offset + count <= data.endIndex else {
            throw MTPError.invalidResponse
        }
        let result = data[offset..<offset+count]
        offset += count
        return Data(result)
    }

    var remainingBytes: Int {
        return data.endIndex - offset
    }
}
```

### 5.3 Concurrency Model and Connection Pool

**Concurrency policy (derived from current Go behavior in `kalam_pool.go`):**

| Rule | Go Current Behavior | Swift Equivalent |
|------|---------------------|-----------------|
| Per-device exclusivity | `deviceMu sync.Mutex` — only one MTP operation at a time per device. **当前Go实现的实际行为**：由于`Kalam_Scan`等函数是全局序列化的（通过全局mutex），实际上只支持单设备操作。Swift池将支持多设备并发。 | `inUseIdentities: Set<USBDeviceIdentity>` inside actor — prevents concurrent operations on the same device identity while allowing parallel operations on different devices. Waiting callers use `CheckedContinuation` (zero-overhead, no polling). **Actor isolation alone is insufficient** — `await device.operation()` suspends the actor, allowing re-entry. The set prevents concurrent use of the same device. |
| Pool size | Max 3 entries (`cfg.Pool.MaxSize = 3`) | `maxPoolSize = 3` constant |
| Entry TTL | 2 minutes (`cfg.Pool.EntryTTL`) | `entryTTL: Duration = .seconds(120)` |
| Cleanup interval | 1 minute background goroutine (`cfg.Pool.CleanupTick`) | `Task` with periodic timer, lazily started on first `withDevice` call (not in `init`), cancelled on `shutdown()` |
| Health check before reuse | Call `GetDeviceInfo` to test connection | Same: call `getDeviceInfo()` on pooled device before returning |
| Evict on failure | Remove dead entry, retry with fresh connection | Same: remove entry, create new device |
| Scan and transfer share pool | `withDeviceQuick` (scan) and `withDevice` (transfer) use same pool, same mutex | Both use same `actor` instance, differentiated by explicit timeout/retry params at call site (no separate `withDeviceQuick` method) |

**Shutdown policy:**

| Event | Go Current Behavior | Swift Equivalent |
|-------|---------------------|-----------------|
| App termination | `Kalam_CleanupDevicePool` disposes all devices | `shutdown()` closes all pooled devices and releases USB interfaces |
| Bridge shutdown flag | `bridgeShutdownFlag atomic.Bool` prevents new operations | `isShutdown` flag in actor, checked at entry of every public method; waiting continuations are resumed with `poolShutdown` error |
| Background cleanup | `init()` goroutine with `time.Ticker` | `Task` lazily started on first use, cancelled in `shutdown()` |

### 5.4 Device Connection Pool

**Note:** The implementation plan (Task 8) is the authoritative source for the pool's exact code. This section provides an architectural overview; any discrepancy should defer to the plan.

```swift
actor MTPDevicePool {
    private struct PoolEntry {
        let device: MTPDeviceProtocol
        var lastUsed: Date
    }

    private var entries: [USBDeviceIdentity: PoolEntry] = [:]
    private var inUseIdentities: Set<USBDeviceIdentity> = []  // CRITICAL: enforces per-device exclusivity
    private var isShutdown = false
    private var waitersByIdentity: [USBDeviceIdentity: [CheckedContinuation<Void, Error>]] = [:]
    private let maxPoolSize = AppConfiguration.mtpPoolMaxEntries
    private let transport: any USBTransport
    private var cleanupTask: Task<Void, Never>?
    private var nextSessionID: UInt32 = 1

    static let shared = MTPDevicePool(transport: LibUSBTransport())

    init(transport: any USBTransport) {
        self.transport = transport
        // cleanupTask is started lazily on first withDevice call.
    }

    private func ensureCleanupStarted() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppConfiguration.mtpPoolCleanupIntervalSeconds))
                await self?.cleanupExpiredEntries()
            }
        }
    }

    func withDevice<T>(
        for identity: USBDeviceIdentity,
        retries: Int = 3,
        backoff: @Sendable (Int) -> Duration = { attempt in
            min(.milliseconds(500 * attempt * attempt), .seconds(2))
        },
        operation: @Sendable (MTPDeviceProtocol) async throws -> T
    ) async throws -> T {
        guard !isShutdown else { throw MTPError.poolShutdown }
        ensureCleanupStarted()

        // Wait for exclusive access to this specific device using CheckedContinuation (zero-overhead, no polling).
        // Per-device exclusivity: different devices can be used concurrently.
        while inUseIdentities.contains(identity) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waitersByIdentity[identity, default: []].append(cont)
            }
        }
        guard !isShutdown else { throw MTPError.poolShutdown }

        inUseIdentities.insert(identity)
        defer {
            inUseIdentities.remove(identity)
            if var waiters = waitersByIdentity[identity], let first = waiters.first {
                waiters.removeFirst()
                if waiters.isEmpty {
                    waitersByIdentity.removeValue(forKey: identity)
                } else {
                    waitersByIdentity[identity] = waiters
                }
                first.resume()
            }
        }

        for attempt in 0...retries {
            do {
                let device = try await getOrCreateDevice(for: identity)
                let result = try await operation(device)
                if var entry = entries[identity] {
                    entry.lastUsed = Date()
                    entries[identity] = entry
                }
                return result
            } catch let error as MTPError where error.isRecoverable && attempt < retries {
                try await Task.sleep(for: backoff(attempt + 1))
                await evictEntry(identity)
                continue
            }
        }
        throw MTPError.nonRecoverable("operation exhausted retries")
    }

    func shutdown() async {
        isShutdown = true
        cleanupTask?.cancel()
        for (_, entry) in entries {
            try? await entry.device.closeSession()
        }
        let count = entries.count
        entries.removeAll()
        for (_, waiters) in waitersByIdentity {
            for waiter in waiters {
                waiter.resume(throwing: MTPError.poolShutdown)
            }
        }
        waitersByIdentity.removeAll()
        Logger.mtp.info("MTPDevicePool: disposed \(count) entries")
    }
}
```

**Quick scan pattern** (uses `withDevice` with lightweight parameters instead of a separate method — see Correction E):
```swift
try await pool.withDevice(for: identity, retries: 1, backoff: { _ in .milliseconds(200) }) { device in
    // metadata read or quick verification
}
```

**Sync bridge** (`MTPDevicePool+Sync.swift`): Provides `withDeviceSync` for `DispatchQueue`-based callers (e.g., `FileTransferManager`) that cannot use `async/await`. Uses `DispatchSemaphore` to block the calling thread until the async pool operation completes. See plan Task 8 Step 5 for implementation details.

### 5.5 Error Classification and Timeout/Retry Strategy

**Timeout configuration (matching current Go defaults from `kalam_config.go`):**

**Note:** Timeouts are configured via `AppConfiguration` constants and consumed internally by `MTPDevice` at the USB transport level — they are NOT passed as parameters to `withDevice`. The "Timeout" column below shows the effective timeout for each operation type.

| Operation Type | Swift Call Site | Effective Timeout | Retries | Backoff | User Message |
|---------------|----------------|-------------------|---------|---------|-------------|
| Device scan | `withDevice(for:retries:1, backoff:{ _ in .milliseconds(200) })` | 5s (`mtpQuickTimeoutSeconds`) | 1 | 200ms fixed | "扫描设备失败" |
| File list / info | `withDevice(for:retries:3)` | 45s (`mtpDefaultTimeoutSeconds`) | 3 | quadratic (max 2s) | "读取文件列表失败" |
| File download | `withDevice(for:retries:3)` | 5min (`mtpDownloadTimeoutSeconds`) per attempt | 3 | progressive: 1s, 2s, 4s | "下载失败，正在重试..." |
| File upload | `withDevice(for:retries:3)` | 45s (`mtpDefaultTimeoutSeconds`) per attempt | 3 | quadratic (max 2s) | "上传失败，正在重试..." |
| Delete / create folder | `withDevice(for:retries:3)` | 45s (`mtpDefaultTimeoutSeconds`) | 3 | quadratic (max 2s) | "操作失败" |
| Pool health check | `getOrCreateDevice(for:)` | 5s (`mtpQuickTimeoutSeconds`) | 0 | none | (internal, not shown) |

**Error classification (derived from `kalam_bridge_transfer.go` lines 229-243 and `kalam_pool.go`):**

| Error Pattern | Classification | Action | MTPError Case |
|--------------|---------------|--------|---------------|
| Error string contains "device" | Non-recoverable (protocol) | Fail, show to user | `.deviceError(original)` |
| Error string contains "connection" | Recoverable | Retry | `.connectionError(original)` |
| Error string contains "timeout" | Recoverable | Retry | `.timeout(original)` |
| Error string contains "not found" | Recoverable | Retry | `.deviceNotFound(original)` |
| Error string contains "no device" | Recoverable | Retry | `.deviceNotFound(original)` |
| Error string contains "LIBUSB_ERROR" | Recoverable | Retry | `.usbError(original)` |
| Error string contains "busy" | Recoverable | Retry with longer backoff | `.deviceBusy(original)` |
| Error string contains "device is not open" | Recoverable (pool) | Evict entry, create new device | `.deviceClosed(original)` |
| Error string contains "device closed" | Recoverable (pool) | Evict entry, create new device | `.deviceClosed(original)` |
| All other errors | Non-recoverable | Fail immediately, show to user | `.nonRecoverable(original)` |
| MTP return code RC_AccessDenied | Non-recoverable | Fail, "权限被拒绝" | `.accessDenied` |
| MTP return code RC_StoreFull | Non-recoverable | Fail, "存储空间不足" | `.storeFull` |
| Task cancelled by user | Non-recoverable | Stop, no retry | `.cancelled` |

```swift
enum MTPError: Error, LocalizedError, Equatable {
    case usbTransferFailed(Int32)
    case sessionAlreadyOpened
    case accessDenied
    case storeFull
    case cancelled
    case poolShutdown
    case invalidResponse
    // Recoverable errors (String associated value for logging)
    case connectionError(String)
    case timeout(String)
    case deviceNotFound(String)
    case usbError(String)
    case deviceBusy(String)
    case deviceClosed(String)
    // Non-recoverable
    case deviceError(String)
    case nonRecoverable(String)

    var isRecoverable: Bool {
        switch self {
        case .connectionError, .timeout,
             .deviceNotFound, .usbError, .deviceBusy, .deviceClosed:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied: return String(localized: "mtp.error.accessDenied", defaultValue: "Access denied")
        case .storeFull: return String(localized: "mtp.error.storeFull", defaultValue: "Storage is full")
        case .sessionAlreadyOpened: return String(localized: "mtp.error.sessionAlreadyOpened", defaultValue: "MTP session already open")
        case .cancelled: return String(localized: "mtp.error.cancelled", defaultValue: "Operation cancelled")
        case .poolShutdown: return String(localized: "mtp.error.poolShutdown", defaultValue: "Connection pool has shut down")
        case .invalidResponse: return String(localized: "mtp.error.invalidResponse", defaultValue: "Invalid device response")
        case let .usbTransferFailed(code): return String(localized: "mtp.error.usbTransferFailed \(code)", defaultValue: "USB transfer failed: \(code)")
        case let .connectionError(message),
             let .timeout(message),
             let .deviceNotFound(message),
             let .usbError(message),
             let .deviceBusy(message),
             let .deviceClosed(message),
             let .deviceError(message),
             let .nonRecoverable(message):
            return message
        }
    }
}
```

**Note:** Invalid object handles are wrapped as `.deviceError("Invalid object handle")` rather than a separate case, matching the plan's Task 6 implementation. The `from(responseCode:)` factory method in Task 6 handles MTP return code mapping.

**Note:** All associated values use `String` (not `Error`). This matches the implementation plan's Task 5/6/8 definition. The `String` approach avoids nested `Error` unwrapping and works cleanly with the `from(message:)` and `from(responseCode:)` factory methods.

---

## 6. TDD Strategy

### 6.1 Principle

Every module is developed test-first. No Swift implementation code is written without a failing test that defines its expected behavior.

### 6.2 Test Pyramid

| Layer | Scope | When | Runs in CI | Example |
|-------|-------|------|-----------|---------|
| Unit | Encode/decode, constants, data structures | Before porting each module | Yes | `testEncodeStringUTF16LE()` |
| Integration (Mock USB) | Protocol transaction flow | Before porting MTPDevice | Yes | `testOpenSessionSendsCorrectBytes()` |
| Fixture comparison | Go vs Swift output parity | Phase 1-3 | Yes (static fixtures) | `testDecodeDeviceInfoMatchesGoSnapshot()` |
| E2E (Real device) | Full operation chain | Each phase (POC: feasibility; Phase 2: file ops; Phase 3: all 20 behaviors) | No (manual) | `testScanDetectsRealDevice()` |

### 6.3 USB Transport Abstraction (Dependency Injection)

To enable mocking in tests, USB calls must be abstracted behind a protocol that uses opaque Swift types, not raw libusb pointers:

```swift
/// Opaque handle — wraps libusb context + device handle + interface metadata
struct USBHandleRef: @unchecked Sendable {
    let context: OpaquePointer?
    let handle: OpaquePointer?
    let interfaceNumber: Int32
    let configurationValue: UInt8
    let interfaceStringIndex: UInt8
    let sendMaxPacketSize: Int
    let fetchMaxPacketSize: Int
    let endpoints: USBEndpoints
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

// Production — wraps real libusb calls
struct LibUSBTransport: USBTransport { /* calls real libusb via CLibUSB */ }

// Testing — no libusb dependency, uses canned data
struct MockUSBTransport: USBTransport {
    var devices: [USBScannedDevice]
    var responses: [Data]
}
```

`MTPDevice` uses `any USBTransport` (existential, not generic) so the transport is determined at runtime. All tests use `MockUSBTransport`. Production uses `LibUSBTransport`. The protocol does not import or reference `CLibUSB` types, so test targets never need libusb installed.

**Design note:** The spec previously used `~Copyable` noncopyable handle types. The plan uses `@unchecked Sendable` instead — simpler, and the pool's per-device exclusivity already prevents double-close via concurrent access. The `@unchecked Sendable` is safe because `USBHandleRef` is only mutated through `MTPDevice` methods, which are protected by the pool.

### 6.4 Fixture Types

**Type A: Protocol Format Fixtures (CI-safe, portable)**

Binary data conforming to the MTP/PTP specification (PIMA 15740). Used to verify encode/decode correctness against the standard.

- Do NOT depend on any specific device
- **Truth source:** Values are hardcoded as literals in `FixtureGenerator` directly from the MTP specification (e.g., `0x1002` for OpenSession, `0x3001` for OFC_Association). The generator does NOT import or read from `MTPConstants.swift`
- **Purpose:** Tests decode a `.bin` fixture and assert against the same spec-derived literals. This catches encoding bugs and struct layout errors in the production code. Because fixture values and test assertions both trace to the spec — not to `MTPConstants.swift` — a wrong constant in production code will fail the test rather than be silently baked into the fixture
- **Generation:** The plan's Tasks 2-4 generate `.bin` fixtures via shell `printf | xxd` commands from spec-derived hex literals. For new fixtures, derive hex from the MTP spec and encode via the same shell pattern. Never regenerate to "match" the production code
- Checked into git; CI runs decode tests against them

```
TestFixtures/Protocol/
├── container_command.bin          # command container per MTP spec
├── container_response_ok.bin      # RC_OK response
├── device_info.bin                # synthetic DeviceInfo per spec
├── storage_info.bin               # synthetic StorageInfo per spec
├── object_info.bin                # synthetic ObjectInfo per spec
├── object_handles.bin             # synthetic handle array
└── error_responses/
    ├── response_access_denied.bin
    ├── response_store_full.bin
    └── response_invalid_handle.bin
```

**Type B: Device Capture Fixtures (development-only, gitignored)**

Recorded from real device via `Scripts/record_mtp_fixtures.go`. Device-specific, used for manual smoke testing.

- This Go program is a **migration-phase-only tool** (see Section 1 "Go Tool Policy")
- Deleted from repository after Phase 3
- Stored in `TestFixtures/Devices/{device-name}/` (gitignored)

### 6.5 Test Plan Per Module

**MTPEncoding tests (against MTP spec):**
- `testEncodeUInt16` / `testDecodeUInt16` — verify little-endian byte order
- `testEncodeString` / `testDecodeString` — verify UTF-16LE, null-terminated, length-prefixed per spec
- `testEncodeArray` / `testDecodeArray` — verify uint32 count + packed elements
- `testEncodeTime` / `testDecodeTime` — verify `YYYYMMDDThhmmss` format
- `testRoundTripObjectInfo` — encode→decode produces identical struct
- `testRoundTripDeviceInfo` — encode→decode produces identical struct
- `testRoundTripStorageInfo` — encode→decode produces identical struct
- `testDecodeMalformedString` — truncated data returns error, no crash
- `testDecodeMalformedArray` — length field exceeds available data returns error
- `testDecodeDeviceInfoFromSpecFixture` — decode Type A fixture, verify all fields

**MTPConstants tests (against PTP/MTP specification):**

**Canonical source:** Values are hardcoded directly in test assertions from the PIMA 15740 specification. Example: `XCTAssertEqual(MTPConstants.OC_OpenSession, 0x1002)`.

**Migration aid:** During Phase 0, a one-time script extracts Go constants into `TestFixtures/Protocol/constants_reference.json` and checks it in. This file is used **only** to catch typos during the initial port — compare Go's `const.go` values against the Swift constants to find discrepancies. After Phase 1, `constants_reference.json` is deleted. If spec and Go-derived reference disagree, the MTP specification wins.

- `testOperationCodes` — verify `OC_OpenSession == 0x1002`, etc. (values from PIMA 15740, hardcoded in test)
- `testReturnCodes` — verify `RC_OK == 0x2001`, etc. (same approach)
- `testObjectFormatCodes` — verify `OFC_Association == 0x3001`, etc. (same approach)

**MTPContainer tests (against MTP spec):**
- `testEncodeCommandContainer` — verify header length, type=COMMAND, code, transactionID, params
- `testDecodeResponseContainer` — verify parsing of Type A response fixtures
- `testCommandContainerWithZeroParams` — edge case: no params → header-only
- `testCommandContainerWithMaxParams` — edge case: 5 params (MTP max)

**MTPDevice tests (mock USB, using Type A fixtures):**
- `testOpenSession` — verify correct request bytes sent via MockUSBTransport
- `testGetObjectHandles` — verify request + response parsing with mock data
- `testSendObjectInfo` — verify upload initiation sequence
- `testDeleteObject` — verify request format
- `testGetPartialObject64` — verify Android extension command
- `testTransactionTimeout` — mock USB delays, verify timeout error thrown
- `testDeviceDisconnectMidTransfer` — mock USB returns error mid-transfer, verify cleanup

**MTPDeviceManager tests (mock USB):**
- `testInitialize` — device open + session + get info sequence
- `testFetchStorages` — storage ID list + info parsing
- `testInitializeFailsNoDevice` — no USB device → clean error
- `testInitializeSessionAlreadyOpen` — recover by closing and reopening

**MTPFileOperations tests (mock USB):**
- `testListFiles` — object handles → ObjectInfo → [FileInfo] conversion
- `testDownloadFile` — GetObject writes to temp file correctly
- `testUploadFile` — SendObjectInfo + SendObject sequence
- `testDeleteFile` — DeleteObject call
- `testCreateFolder` — SendObjectInfo with OFC_Association format
- `testDownloadEmptyFile` — edge case: 0-byte file
- `testUploadLargeFile` — verify chunked transfer (multiple bulk writes)

**Go vs Swift parity tests (CI-safe, using static snapshots):**

These tests cover **decode parity only** — given the same raw bytes (from Type A fixtures), Swift and Go produce the same decoded structs. They do NOT validate request sequencing or multi-step transaction flows.

- Record Go decode output for DeviceInfo, StorageInfo, ObjectInfo, ObjectHandles as `.expected.json` files
- Swift code decodes same fixture data, compares against `.expected.json`
- Scope: single-response decode operations only (scan, list, info queries)

**Request-sequence parity** for stateful operations (upload: SendObjectInfo→SendObject, download: GetObjectInfo→GetObject, delete: DeleteObject) is validated by MockUSBTransport integration tests in `MTPFileOperationsTests`, which assert the exact sequence and content of USB bulk transfers sent for each operation. These are Swift-only tests (no Go comparison) — correctness is defined by the MTP specification, not by Go's behavior.

**Error path tests:**
- `testMTPErrorAccessDenied` — mock returns RC_AccessDenied → correct error thrown
- `testMTPErrorStoreFull` — mock returns RC_StoreFull → correct error thrown
- `testUSBTransferError` — mock libusb returns LIBUSB_ERROR_IO → correct error thrown
- `testCorruptedResponseHeader` — truncated response → decode error, no crash
- `testResponseLengthMismatch` — declared length > actual data → error, no crash
- `testTaskCancellation` — cancel mid-transfer → cooperative cancellation works
- `testRecoverableErrorRetries` — device error → retry succeeds on 2nd attempt
- `testNonRecoverableErrorNoRetry` — access denied → fail immediately, no retry

### 6.6 TDD Workflow Per Module

```
1. Identify Go function to port
2. Write Swift test that validates expected behavior against MTP spec (RED)
3. Port minimum code to make test pass (GREEN)
4. Run round-trip tests (encode→decode→compare)
5. Run Go parity test (decode same bytes, compare with Go snapshot)
6. Refactor for Swift idioms (REFACTOR)
7. Run full test suite to check for regressions
8. Move to next function
```

---

## 7. Phased Execution Plan

### Phase 0: POC + Test Infrastructure (verify feasibility)

**Goal:** Prove Swift can talk to an MTP device via libusb.

1. Copy `libusb.h` into `SwiftMTP/CLibUSB/`, create `module.modulemap`
2. Check in prebuilt `lib/libusb-1.0.a` (arm64 only — macOS 26+ does not support Intel Macs, so universal binary is unnecessary)
3. Configure Xcode project: header search paths, linker flags, import path
4. Write `Scripts/record_mtp_fixtures.go` (migration-phase-only tool, see Section 1)
5. Record real device MTP fixtures (Type B, gitignored)
6. Implement `USBTransport/USBDevice.swift` (minimally: init, open, bulk transfer)
7. Implement `MTPProtocol/MTPEncoding.swift` (enough for Container encode/decode)
8. Implement `MTPProtocol/MTPConstants.swift` (core operation codes only)
9. Implement `MTPDevice/MTPDeviceScanner.swift` (find MTP devices on USB bus)
10. Implement minimal `MTPDevice.swift`: Open → OpenSession → GetDeviceInfo
11. **Pass criteria:** Xcode builds, test connects to real Android device, logs device name and manufacturer

### Phase 1: Protocol Layer (TDD)

**Goal:** Complete MTP binary protocol implementation.

1. Full `MTPConstants.swift` (all 1,974 lines of constants)
2. Full `MTPTypes.swift` (all data structures)
3. Full `MTPEncoding.swift` (all encode/decode paths)
4. `MTPDevice.swift` core: runTransaction, sendReq, fetchPacket, bulkWrite, bulkRead
5. `MTPDevice+Operations.swift`: all operations from `ops.go`
6. `MTPDebugLogger.swift`: protocol debug output
7. **Pass criteria:** All unit tests + mock USB integration tests pass; fixture-based tests verify byte-level compatibility with Go

### Phase 2: High-Level API + Device Pool (TDD)

**Goal:** Replace go-mtpx functionality.

1. `MTPDeviceManager.swift` (Initialize, Dispose, FetchDeviceInfo, FetchStorages)
2. `MTPFileOperations.swift` (list, upload, download, delete, walk)
3. `MTPDataStructures.swift` + `MTPUtilities.swift` + `MTPError.swift`
4. `MTPDevicePool.swift` (actor-based connection pool, matching Go's serialization/retry/cleanup behavior per Section 5.3-5.4)
5. **Pass criteria:** All module tests pass; file operations work on real device

### Phase 3: Switch Service Layer (TDD + Regression)

**Goal:** Replace Kalam C calls with Swift MTP module calls.

1. Modify `DeviceManager` to use `MTPDevicePool` + `MTPDeviceManager` instead of `Kalam_Scan`
2. Modify `FileSystemManager` to use `MTPFileOperations` instead of `Kalam_ListFiles`
3. Modify `FileTransferManager` to use Swift MTP instead of `Kalam_DownloadFile`/`Kalam_UploadFile`
4. Move `Kalam_DeleteObject` call from `FileBrowserView+Actions` into `FileSystemManager`
5. Parity tests: decode same Type A fixtures in Swift, compare output against Go's `.expected.json` snapshots
6. Verify each behavior from Success Criteria table (Section 1) on real device
7. Remove `SwiftMTP-Bridging-Header.h`, `libkalam.h`, `libkalam.dylib`
8. Remove `build_kalam.sh` from build pipeline
9. Delete `Native/` directory
10. Delete `Scripts/record_mtp_fixtures.go` (migration tool no longer needed)
11. Clean up Xcode project: remove Go-related build phases (CGO, libkalam copy/sign), remove `Native/` from header search paths; **keep** the new `CLibUSB/` module map settings and `libusb-1.0.a` linker flag
12. Update all docs and guidance files (`AGENTS.md`, `CLAUDE.md`, `README.md`, wiki pages, localized strings) to remove Go/CGO references
13. **Pass criteria:** All 20 behaviors from Success Criteria verified on real device; all MTPCore tests pass; app binary contains no Go/CGO artifacts

---

## 8. Project Structure (After Migration)

```
SwiftMTP/
├── SwiftMTP/
│   ├── App/
│   ├── Models/
│   ├── Services/
│   │   ├── MTP/
│   │   │   ├── DeviceManager.swift
│   │   │   ├── FileSystemManager.swift
│   │   │   ├── FileTransferManager.swift
│   │   │   └── FileTransferManager+DirectoryUpload.swift
│   │   ├── MTPCore/                    # NEW: Swift native MTP
│   │   │   ├── USBTransport/
│   │   │   │   ├── USBDevice.swift
│   │   │   │   └── USBDebugLogger.swift
│   │   │   ├── MTPProtocol/
│   │   │   │   ├── MTPConstants.swift
│   │   │   │   ├── MTPTypes.swift
│   │   │   │   ├── MTPEncoding.swift
│   │   │   │   └── MTPDebugLogger.swift
│   │   │   ├── MTPDevice/
│   │   │   │   ├── MTPDevice.swift
│   │   │   │   ├── MTPDevice+Operations.swift
│   │   │   │   ├── MTPDevice+Download.swift
│   │   │   │   ├── MTPDeviceScanner.swift
│   │   │   │   ├── MTPDeviceManager.swift
│   │   │   │   ├── MTPFileOperations.swift
│   │   │   │   ├── MTPDataStructures.swift
│   │   │   │   ├── MTPUtilities.swift
│   │   │   │   └── MTPError.swift
│   │   │   ├── MTPDevicePool.swift
│   │   │   └── MTPDevicePool+Sync.swift  # withDeviceSync for DispatchQueue-based callers (FileTransferManager)
│   │   ├── Protocols/
│   │   └── ...
│   ├── Views/
│   ├── Config/
│   └── Resources/
├── SwiftMTPTests/
│   └── MTPCore/                        # NEW: TDD test suite
│       ├── Fixtures/
│       │   └── Protocol/               # Type A: spec-derived generated fixtures (CI-safe)
│       │       ├── container_command.bin
│       │       ├── container_response_ok.bin
│       │       ├── device_info.bin
│       │       ├── storage_info.bin
│       │       ├── object_info.bin
│       │       └── error_responses/
│       ├── Snapshots/                  # Go output .expected.json for parity
│       ├── MTPEncodingTests.swift
│       ├── MTPConstantsTests.swift
│       ├── MTPContainerTests.swift
│       ├── MTPDeviceTests.swift
│       ├── MTPDeviceManagerTests.swift
│       ├── MTPFileOperationsTests.swift
│       ├── ErrorPathTests.swift
│       └── ServiceComparisonTests.swift
├── lib/                                # Prebuilt static lib (arm64 only)
│   └── libusb-1.0.a                    # Checked in; macOS 26+ is arm64-only
└── (Native/ removed, Scripts/record_mtp_fixtures.go deleted)
```

---

## 9. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| MTP device incompatibility (specific Android vendors) | Medium | High | TDD with recorded fixtures; **具体测试设备清单**：Samsung Galaxy S23 (Android 14), Google Pixel 8 (Android 14), Xiaomi 13 (MIUI 14), OnePlus 11 (OxygenOS 13)。Phase 0-2期间在每台设备上验证所有20个行为。 |
| USB bulk transfer timeout differences | Medium | Medium | Match Go's exact timeout values (Section 5.5); hex dump logging for diagnosis; **具体调试步骤**：1) 启用`USBDebugLogger`的hex dump输出，2) 对比Go和Swift的USB请求/响应字节序列，3) 使用Wireshark USB抓包验证协议正确性 |
| Session management differences | Low | Medium | Match Go's session ID generation (random \| 1); exact same Configure() flow; **验证方法**：编写测试验证session ID生成算法，对比Go的`sessionID = rand.Uint32() | 1`实现 |
| Performance regression | Low | Low | Swift-to-C libusb call overhead is lower than Swift→CGO→Go→libusb; **性能测试**：在Phase 3中添加性能基准测试，对比Go和Swift的文件传输速度 |
| libusb static linking conflicts with entitlements | Low | High | Sandbox already disabled for USB (per CLAUDE.md); verify during POC; **具体验证步骤**：1) 检查`SwiftMTP.entitlements`中`com.apple.security.app-sandbox`为`false`，2) 运行`codesign -d --entitlements - SwiftMTP.app`验证签名 |
| libusb.h version drift (checked-in copy vs Homebrew) | Low | Low | Pin to libusb 1.0.29; update checked-in header when upgrading; **版本管理**：在`CLibUSB/libusb.h`顶部添加版本注释，`build_kalam.sh`中添加版本检查 |
| MTPConstants test depends on Go source at runtime | Eliminated | — | Constants reference is generated as JSON during Phase 0 and checked in; no Go needed at test time |
| **新增风险**：USB设备突然断开连接 | Medium | Medium | **缓解措施**：1) 在`MTPDevice`中添加连接状态监控，2) 实现自动重连机制（最多3次），3) 在UI中显示设备连接状态变化通知 |
| **新增风险**：大文件传输内存溢出 | Low | High | **缓解措施**：1) 实现流式传输，不将整个文件加载到内存，2) 添加传输进度回调，3) 设置单次传输最大大小限制（建议1GB） |

---

## 10. Out of Scope

- Rewriting the SwiftUI views or existing Services API
- Adding new features (progress callback, multi-device simultaneous access)
- Changing the app's data model or user-facing behavior
- Windows/Linux support (macOS only)
- Keeping Go code as a fallback option (full cutover, no dual-mode)
