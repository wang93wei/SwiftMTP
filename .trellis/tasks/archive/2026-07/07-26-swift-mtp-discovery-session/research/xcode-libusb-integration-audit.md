# Research: Xcode / libusb Integration Audit

- Query: 审查 Xcode project、CLibUSB module/header、`libusb-1.0.dylib` / `libkalam.dylib`、build phases、rpath、codesign、新 Swift 文件自动纳入方式；判断 Debug/Release arm64 构建与测试是否正确导入/链接 libusb，并列出移除 Go 前的构建/打包契约。
- Scope: mixed
- Date: 2026-07-27

## Findings

### 1. 结论摘要

- **arm64 Debug / arm64 Release 当前可正确编译和链接 CLibUSB/libusb，且不会移除或绕过现有 libkalam。** 隔离 DerivedData 实跑两种配置均 `BUILD SUCCEEDED`；产物同时包含 `Contents/Frameworks/libusb-1.0.dylib` 与 `libkalam.dylib`。
- **默认 Release / Archive / DMG 构建当前不成立。** `xcodebuild -configuration Release build` 解析为 `ARCHS = arm64 x86_64`，而两份仓库 dylib 均为 thin arm64；x86_64 链接阶段忽略两库并以缺失 `Kalam_*` 等符号失败（exit 65）。因此 `Scripts/create_dmg_simple.sh` 与 `Scripts/create_dmg.sh` 的无架构覆盖 Release 构建也会在当前机器/SDK 设置下失败。
- **测试必须签名。** 当前 55 个测试在仓库安全的 ad-hoc 签名参数下全部通过；同一测试命令加 `CODE_SIGNING_ALLOWED=NO` 会在 XCTest bootstrap 前崩溃（0 tests），不能作为有效测试 gate。
- **新 Swift/测试文件自动纳入是有效的。** App 与 test target 都使用 Xcode 16+ file-system-synchronized root group；空 `PBXSourcesBuildPhase.files` 是预期形态。实跑生成的 `SwiftMTP.SwiftFileList` / `SwiftMTPTests.SwiftFileList` 已包含本任务所有未显式登记到 pbxproj 的新文件。
- **当前 Go 生产路径仍是硬链接/硬调用依赖，不能先删 `libkalam`。** bridging header 仍导入 `libkalam.h`，多个生产 manager/view/app 直接调用 `Kalam_*`；arm64 链接命令同时含 `-lkalam` 与 `-lusb-1.0`，产物同时依赖 `@rpath/libkalam.dylib` 和 `@rpath/libusb-1.0.dylib`。

### 2. Files Found

| Path | Description |
|---|---|
| `SwiftMTP.xcodeproj/project.pbxproj` | target、同步目录、Embed Libraries、Debug/Release search path、rpath、link flags、签名设置的唯一工程事实来源。 |
| `SwiftMTP.xcodeproj/xcshareddata/xcschemes/SwiftMTP.xcscheme` | Shared scheme；测试使用 Debug，Archive 使用 Release。 |
| `SwiftMTP/Support/CLibUSB/module.modulemap` | `CLibUSB` system module；导入 vendored header，并声明 `link "usb-1.0"`。 |
| `SwiftMTP/Support/CLibUSB/include/libusb.h` | vendored libusb public header。 |
| `SwiftMTP/Support/CLibUSB/SOURCE.md` | 声明上游 `libusb/libusb` tag `v1.0.29` 与二进制版本来源。 |
| `SwiftMTP/libusb-1.0.dylib` | tracked thin arm64 libusb；install name 为 `@rpath/libusb-1.0.dylib`。 |
| `SwiftMTP/libkalam.dylib` | tracked thin arm64 Go/CGO bridge；依赖 `@rpath/libusb-1.0.dylib`。 |
| `SwiftMTP/SwiftMTP-Bridging-Header.h` | 现有 Go C API 的 Swift 入口，仍 `#import "libkalam.h"`。 |
| `Scripts/build_kalam.sh` | 从 Homebrew 构建 Go dylib，并覆盖复制仓库 `libusb-1.0.dylib`；不是当前 Xcode build phase。 |
| `Scripts/create_dmg_simple.sh` | 直接执行默认 Release build 后打 DMG；当前会触发 universal link failure。 |
| `Scripts/create_dmg.sh` | 执行默认 Release archive/export；同样受 thin-arm64 dylib 限制。 |
| `.trellis/tasks/07-26-swift-mtp-foundation/verification.md` | foundation 交接已经记录 arm64 支持边界、unsigned XCTest bootstrap 失败和 ad-hoc 测试命令。 |

### 3. Xcode 工程模式与标识

#### File-system-synchronized target membership

- App root group `F55680C52EF71DB6001F64CC` 是 `PBXFileSystemSynchronizedRootGroup`，路径 `SwiftMTP`（`project.pbxproj:52-60`），并由 app target `F55680C22EF71DB6001F64CC` 的 `fileSystemSynchronizedGroups` 引用（`:114-136`）。
- Test root group `F5F181682F0434B80072DEB2` 同样同步路径 `SwiftMTPTests`（`:61-65`），由 test target `F5F181662F0434B80072DEB2` 引用（`:138-159`）。
- App/test 的 `PBXSourcesBuildPhase` 文件列表均为空（`:223-238`）；这不是漏加文件，而是同步目录模式的正常表现。
- 实际 Debug build 的 `SwiftMTP.SwiftFileList` 包含：
  - `MTPDeviceSession.swift`
  - `LibUSBContext.swift`
  - `LibUSBDeviceHandle.swift`
  - `LibUSBFunctionTable.swift`
  - `LibUSBTransfer.swift`
  - `LibUSBTransport.swift`
  - `USBDescriptors.swift`
  - `USBDeviceEnumerator.swift`
- 实际 test build 的 `SwiftMTPTests.SwiftFileList` 包含本任务新测试及 `FakeLibUSBFunctions.swift`。因此只要新 `.swift` 保持在对应同步 root 下且没有 membership exception，无需手改 pbxproj。

#### Embed Libraries and CodeSignOnCopy

- Copy phase `F5FF14C72EF73F3800308744` 名为 `Embed Libraries`，`dstSubfolderSpec = 10`（Frameworks）（`:19-29`）。
- exception set `F5702F6C2EF7506900097552` 把 `libkalam.dylib` 与 `libusb-1.0.dylib` 加入该 phase，并为两者设置 `CodeSignOnCopy`（`:37-49`）。
- App target build phase 顺序为 Sources → Frameworks → Resources → Embed Libraries（`:118-123`）。Frameworks phase 自身为空（`:68-83`）；链接来自 module/linker 输入，嵌入来自同步目录 exception。
- 签名开启时的 build log 明确执行两次 Copy 和两次 CodeSign。ad-hoc 产物中两库均显示 `Signature=adhoc`、`TeamIdentifier=not set`，且：
  - `codesign --verify --deep --strict --verbose=2 SwiftMTP.app` 通过；
  - Developer 签名产物中两库 Team ID 与 app 相同。

### 4. CLibUSB 导入与链接链

- `SwiftMTP/Support/CLibUSB/module.modulemap:1-4`：
  - module 名为 `CLibUSB [system]`；
  - header 为 `include/libusb.h`；
  - `link "usb-1.0"`；
  - 导出全部 C API。
- Project Debug/Release 都将 `SWIFT_INCLUDE_PATHS` 指向 `$(SRCROOT)/SwiftMTP/Support/CLibUSB`（`project.pbxproj:249-317`, `:319-379`），所以 app 与依赖 app module 的测试都可 `import CLibUSB`。
- App target Debug/Release 都配置：
  - `LIBRARY_SEARCH_PATHS = $(PROJECT_DIR)/SwiftMTP`（`:410-413`, `:464-467`）；
  - `OTHER_LDFLAGS += -lusb-1.0`（`:416-419`, `:470-473`）。
- module map 和 `OTHER_LDFLAGS` 都请求 libusb，实际 arm64 link line出现两次 `-lusb-1.0`。当前无功能错误，但属于重复契约；后续应选定一个权威链接入口，避免其中一个被删除后误以为另一层也同步修改。
- `LibUSBFunctionTable.swift:1,10,51-138` 直接导入并绑定 `libusb_init/exit/get_device_list/open/claim_interface/submit_transfer/handle_events_timeout_completed`；`nm -gU SwiftMTP/libusb-1.0.dylib` 已确认这些符号存在。
- 当前二进制事实：
  - `libusb-1.0.dylib`: Mach-O thin arm64；ID `@rpath/libusb-1.0.dylib`。
  - `libkalam.dylib`: Mach-O thin arm64；ID `@rpath/libkalam.dylib`；依赖 `@rpath/libusb-1.0.dylib`。

### 5. rpath 与运行时共存

- App target macOS 生效 rpath 是 `@executable_path/../Frameworks`（`project.pbxproj:408-409`, `:462-463`），与两库实际嵌入位置一致。
- Debug 采用 Xcode 的 `SwiftMTP.debug.dylib` 结构：
  - launcher 依赖 `@rpath/SwiftMTP.debug.dylib`；
  - `SwiftMTP.debug.dylib` 依赖 `@rpath/libusb-1.0.dylib` 与 `@rpath/libkalam.dylib`；
  - launcher 与 debug dylib 的 LC_RPATH 均能到达 `Contents/Frameworks`。
- Release 主可执行文件直接依赖两库，且 LC_RPATH 为 `@executable_path/../Frameworks`。
- Test target Debug rpath 指向 app 的 `Contents/MacOS` 与 `Contents/Frameworks`（`project.pbxproj:489-512`）；shared scheme 的 TestAction 固定 Debug（`SwiftMTP.xcscheme:25-40`），因此测试运行时可从 app host 产物解析两库。

### 6. 现有 Go 路径不可提前破坏

- `SwiftMTP/SwiftMTP-Bridging-Header.h:11` 仍导入 `libkalam.h`。
- 直接生产调用仍存在，例如：
  - `DeviceManager.swift:120,228-250` — init、scan、free string；
  - `FileSystemManager.swift:121-128` — list、free string；
  - `FileTransferManager.swift:114-128,224-377` — cancel、scan、upload/download、storage refresh/cache reset；
  - `FileTransferManager+DirectoryUpload.swift:181-182,249,348` — refresh/reset/create/upload；
  - `FileBrowserView+Actions.swift:282,335` — delete；
  - `FileBrowserView+ToolbarDrop.swift:153` — create folder；
  - `SwiftMTPApp.swift:113-116` — process cleanup。
- 实际 arm64 link line包含 `-lkalam`；Release 可执行或 Debug app dylib 的 `otool -L` 也包含 `@rpath/libkalam.dylib`。因此仅删除 dylib、embed exception、bridging header 任一项都会让现有生产 app 在链接或启动时失败。
- `Scripts/build_kalam.sh:40-79` 仍负责生成 `libkalam`、将其依赖改为 `@rpath`，并从 `/opt/homebrew/opt/libusb` 覆盖复制仓库 libusb。该脚本没有出现在 pbxproj 的 shell build phase 中；常规 Xcode build 使用的是已跟踪二进制，不会自动重建 Go。

### 7. 实跑结果

环境：

- Xcode `27.0` (`27A5228h`)
- Apple Swift `6.4`
- host / destination `arm64`, macOS 27.0 beta，deployment target 26.0

| Probe | Result |
|---|---|
| Debug arm64 build，`CODE_SIGNING_ALLOWED=NO` | PASS，exit 0 |
| Release arm64 build，显式 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO` | PASS，exit 0 |
| 默认 Release build，`CODE_SIGNING_ALLOWED=NO` | FAIL，exit 65；x86_64 忽略 arm64-only libusb/libkalam，undefined symbols |
| Test arm64，`CODE_SIGNING_ALLOWED=NO` | FAIL，exit 65；XCTest bootstrap 前 unexpected exit，0 tests |
| Test arm64，默认 Developer signing | PASS，55 tests / 0 failures |
| Test arm64，`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` | PASS，55 tests / 0 failures |
| ad-hoc app deep/strict signature verification | PASS；两份 embedded dylib 均 ad-hoc 签名 |

说明：`CODE_SIGNING_ALLOWED=NO` 的测试失败是运行器签名门槛，不是 libusb 编译或测试断言失败。构建阶段已成功产生 app/test bundle，但 xctest 未启动任何测试。

### 8. Risks

#### Blocking

1. **默认 Release/Archive 仍声明 universal，但依赖为 arm64-only。**
   - `xcodebuild -showBuildSettings`：Debug `ARCHS=arm64`, `ONLY_ACTIVE_ARCH=YES`；Release `ARCHS=arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`。
   - `Scripts/create_dmg_simple.sh:35-41` 和 `Scripts/create_dmg.sh:36-42` 没有 arm64 限定，会继承默认 universal。
   - 在保留 `libkalam` 期间，必须二选一：
     - 明确把产品/打包契约限制为 arm64；或
     - 同时提供 arm64+x86_64 的 **libkalam 和 libusb**。只把 libusb 做 universal 仍会因 libkalam 失败。

2. **计划中的 test 命令错误地禁用签名。**
   - `implement.md` 的 `xcodebuild test ... CODE_SIGNING_ALLOWED=NO` 会在当前 Xcode/macOS 环境产生假红。
   - 可复现、无需开发证书的 gate 应使用 ad-hoc：`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`。

#### High

3. **Go build 脚本会覆盖 pinned libusb。**
   - `Scripts/build_kalam.sh:53-79` 从当前 Homebrew 安装直接复制并改 install name；它没有核对版本、SHA 或架构。
   - 这可能使 `Support/CLibUSB/SOURCE.md` 声明的 `v1.0.29` header 与运行时二进制漂移。最终去 Go 前需把 libusb 供应链从 `build_kalam.sh` 拆出并做版本/哈希/架构校验。

4. **签名验证不能只看顶层 app。**
   - 两库是 nested code，必须先由 Xcode 的 `CodeSignOnCopy` 使用同一签名身份签名，再签顶层 app。分发时还需 archive/export/notarization 级验证；ad-hoc 仅证明本地测试结构正确。

#### Medium

5. **libusb 链接声明重复。**
   - `module.modulemap:3` 和 target `OTHER_LDFLAGS` 都声明 `-lusb-1.0`，实际 link line重复。当前 linker 去重/容忍，但最终构建契约应只保留一个清晰所有者。

6. **同步目录会自动纳入任何新 Swift 文件。**
   - 这是本任务的便利，也是误纳入风险。临时/实验 `.swift` 放入 `SwiftMTP/` 或 `SwiftMTPTests/` 会自动参与对应 target；若文件不应构建，必须放在同步 root 外或增加明确 membership exception。

7. **当前分发安全设置较宽。**
   - Debug/Release target 都是 `DISABLE_LIBRARY_VALIDATION=YES`、`ENABLE_HARDENED_RUNTIME=NO`（`project.pbxproj:388-394`, `:442-448`）。这不阻塞本任务的本地 arm64 构建，但最终去 Go/正式分发应明确是否仍需该豁免，并用真实 Developer ID archive/notarization 验证。

### 9. 移除 Go 前必须满足的构建/打包契约

以下条件应作为独立 migration gate，不能在 discovery/session 阶段提前执行：

1. **调用契约清零**
   - 所有生产 `Kalam_*` 调用已迁移；
   - `SwiftMTP-Bridging-Header.h` 不再导入 `libkalam.h`，或整个 bridging-header build setting 被安全移除；
   - 全配置链接产物 `otool -L` 不再出现 `libkalam`。

2. **工程契约清理**
   - 从 `F5702F6C2EF7506900097552` 移除 `libkalam.dylib` 的 membership/`CodeSignOnCopy`；
   - 删除或退役 `libkalam.dylib`、`libkalam.h` 和 Go build-only packaging 逻辑；
   - 保留 `libusb-1.0.dylib` 的 Embed Libraries + `CodeSignOnCopy`，以及正确 rpath。

3. **CLibUSB 契约保留**
   - `module.modulemap`、vendored header、license/source provenance 保持可从 clean checkout 构建；
   - `SWIFT_INCLUDE_PATHS` 可找到 module map；
   - `LIBRARY_SEARCH_PATHS`/显式 binary dependency 可找到 libusb；
   - 选定 module map 或 target linker flag 为唯一链接所有者；
   - `nm` 验证 Swift transport 使用的 libusb symbols 都存在。

4. **架构契约显式化**
   - 若产品只支持 Apple Silicon：Debug、Release、Archive、test、DMG 脚本全部显式 arm64，且文档/CI 一致；
   - 若产品支持 Intel：必须提供 universal libusb，并在移除 libkalam 后验证 app 和每个 nested dylib 都含 `arm64 x86_64`。

5. **产物与动态加载契约**
   - `Contents/Frameworks/libusb-1.0.dylib` 必须存在；
   - install name 必须是 `@rpath/libusb-1.0.dylib`；
   - app/Debug app dylib 必须使用 `@rpath/libusb-1.0.dylib`；
   - app LC_RPATH 必须能到达 `@executable_path/../Frameworks`；
   - `libkalam` 在产物和 load commands 中均不存在。

6. **签名/分发契约**
   - 本地测试用 ad-hoc 签名通过；
   - archive/export 后 libusb 与 app 使用预期的同一 Team/分发身份；
   - `codesign --verify --deep --strict`、Gatekeeper assessment、notarization/stapling（若走独立分发）通过；
   - 不以 `CODE_SIGNING_ALLOWED=NO` 的 test 结果替代有效测试。

7. **打包脚本契约**
   - `create_dmg_simple.sh` / `create_dmg.sh` 的 Release 架构与供应二进制一致；
   - 打包前自动验证 file/lipo/otool/codesign；
   - `build_kalam.sh` 不再是 libusb 供应入口；替代流程必须 pin 版本、校验 SHA、install name 和架构，不能从任意当前 Homebrew 版本静默覆盖。

### 10. Recommended Verification Commands

当前保留 Go、arm64 baseline：

```bash
# Debug arm64
xcodebuild \
  -project SwiftMTP.xcodeproj \
  -scheme SwiftMTP \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build

# Release arm64（ONLY_ACTIVE_ARCH 单独使用不够稳，显式 ARCHS）
xcodebuild \
  -project SwiftMTP.xcodeproj \
  -scheme SwiftMTP \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

# Tests：使用 ad-hoc 签名，不要 CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project SwiftMTP.xcodeproj \
  -scheme SwiftMTP \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
```

产物审计（`APP` 替换为实际 DerivedData/archive app）：

```bash
APP=/path/to/SwiftMTP.app

file \
  "$APP/Contents/MacOS/SwiftMTP" \
  "$APP/Contents/Frameworks/libusb-1.0.dylib" \
  "$APP/Contents/Frameworks/libkalam.dylib"

lipo -info "$APP/Contents/Frameworks/libusb-1.0.dylib"
lipo -info "$APP/Contents/Frameworks/libkalam.dylib"

otool -L "$APP/Contents/MacOS/SwiftMTP"
test ! -e "$APP/Contents/MacOS/SwiftMTP.debug.dylib" ||
  otool -L "$APP/Contents/MacOS/SwiftMTP.debug.dylib"
otool -D "$APP/Contents/Frameworks/libusb-1.0.dylib"
otool -D "$APP/Contents/Frameworks/libkalam.dylib"

codesign -dvv "$APP/Contents/Frameworks/libusb-1.0.dylib"
codesign -dvv "$APP/Contents/Frameworks/libkalam.dylib"
codesign --verify --deep --strict --verbose=2 "$APP"
```

最终移除 Go 后增加：

```bash
APP=/path/to/SwiftMTP.app

test -e "$APP/Contents/Frameworks/libusb-1.0.dylib"
test ! -e "$APP/Contents/Frameworks/libkalam.dylib"

if test -e "$APP/Contents/MacOS/SwiftMTP.debug.dylib"; then
  ! otool -L "$APP/Contents/MacOS/SwiftMTP.debug.dylib" | grep -q libkalam
else
  ! otool -L "$APP/Contents/MacOS/SwiftMTP" | grep -q libkalam
fi

nm -gU "$APP/Contents/Frameworks/libusb-1.0.dylib" |
  grep -E '_libusb_(init|exit|get_device_list|open|claim_interface|submit_transfer|handle_events_timeout_completed)$'

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

### 11. External References

- libusb upstream tag declared by the repository: <https://github.com/libusb/libusb/tree/v1.0.29>
- libusb API documentation: <https://libusb.sourceforge.io/api-1.0/>
- Apple — Managing files and folders in your Xcode project: <https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project>
- Apple — Creating distribution-signed code for macOS: <https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/>
- Apple — Embedding nonstandard code structures in a bundle: <https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle>

Context7 did not return an authoritative `/libusb/libusb` documentation entry; external libusb conclusions therefore use the repository-pinned upstream tag/API site plus direct binary inspection, not a third-party wrapper.

### 12. Related Specs / Artifacts

- `.trellis/tasks/07-26-swift-mtp-discovery-session/prd.md`
  - KD3 / AC: Swift provider 仅开发/测试启用，Go 仍是生产默认；Xcode build 与全部 Swift tests 通过，Go 默认路径无回归。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/design.md`
  - shared `LibUSBContext` event loop；provider 在 session 创建时固定。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/implement.md`
  - Validation 需要修正 unsigned XCTest 命令，并显式 arm64 Release。
- `.trellis/tasks/07-26-swift-mtp-foundation/verification.md:9-21,35-48,117-123`
  - 已确认相同 arm64 baseline、ad-hoc test gate、默认 Release universal 失败和 Go 生产路径保持不变。
- `.trellis/spec/guides/cross-layer-thinking-guide.md`
  - 构建设置、模块、二进制、打包脚本和运行时加载是跨层契约，必须一起验证。

## Caveats / Not Found

- 未读取 `implement.jsonl` / `check.jsonl`：Trellis researcher 角色要求与 implement/check 上下文隔离；本报告依据 task artifacts、spec、工程文件和实跑产物。
- 未执行真实 Android 硬件 scan/open/close；本报告只证明构建、链接、嵌入、签名和 scripted tests，不代表 USB 权限、claim 或 MTP 真机互操作已验证。
- 未执行 DMG 创建或 archive/export/notarization；默认 Release 已在链接阶段复现失败，因此继续打包没有有效产物价值。
- 未修改源码、测试、pbxproj 或脚本，也未提交。
