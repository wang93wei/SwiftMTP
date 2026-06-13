# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述
macOS 原生 Android MTP 文件传输工具。

- **当前后端**: Swift 前端通过 CGO 桥接调用 Go MTP 库（`libkalam.dylib`）操作 USB 设备
- **演进中**: `Packages/MTPCore` 是纯 Swift + 直调 libusb 的新 MTP 协议层，目标是**替代 Go/CGO 后端**统一技术栈。目前**独立开发、尚未接入主 app**，与 Go 路径并存（详见下文 [MTPCore](#mtpcore纯-swift-mtp-协议层开发中) 节）
- **技术栈**: Swift 6+ / SwiftUI / Go 1.26 / libusb-1.0
- **架构**: MVVM + 单例模式（`DeviceManager.shared`, `FileSystemManager.shared`, `FileTransferManager.shared`）
- **平台**: macOS 26.0+，沙盒已禁用以访问 USB 设备

## 构建命令

```bash
# Go 桥接层（每次 Go 代码变更后必须执行）
./Scripts/build_kalam.sh

# Swift 编译（优先使用 Xcode MCP；未启用则用 xcodebuild）
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP build

# MTPCore（Swift Package）单元测试 — 纯函数,无需 USB 设备
cd Packages/MTPCore && swift test
swift test --filter EncodingGoldenTests          # 跑单个测试套件

# Go 单元测试（含黄金契约 generate + decode）
cd Native && go test ./...
go test -run TestGenerateFixtures                 # 重新生成 MTPCore 黄金 fixture

# 校验 MTPCore 编码黄金 fixture 与 Go 实现一致（防漂移,CI 用）
./Scripts/check_encoding_fixtures.sh

# 全量测试（Swift 主 app + Go,可选 --coverage / --swift-only / --go-only）
./Scripts/run_tests.sh

# 打包 DMG（仅限项目根目录执行）
./Scripts/create_dmg_simple.sh
```

## 架构：Swift → CGO → Go 调用链

```
SwiftUI Views
  → Services (DeviceManager / FileSystemManager / FileTransferManager)
    → Bridging Header (SwiftMTP-Bridging-Header.h imports libkalam.h)
      → C exported functions (Kalam_Scan, Kalam_ListFiles, Kalam_DownloadFile, etc.)
        → Go implementations (Native/kalam_bridge*.go)
          → go-mtpx / libusb-1.0 (USB MTP 协议)
```

- Swift 通过 `SwiftMTP-Bridging-Header.h` 导入 `libkalam.h` 中的 C 函数
- Go 编译为 `libkalam.dylib`（`-buildmode=c-shared`），所有导出函数以 `Kalam_` 为前缀
- 返回值为 JSON 字符串指针（`*C.char`），错误返回 `nil`
- **必须** 在使用完毕后调用 `Kalam_FreeString` 释放内存
- 进度回调通过 `Kalam_SetProgressCallback` 注册 uintptr 函数指针

## MTPCore：纯 Swift MTP 协议层（开发中，目标替代 Go 桥接）

`Packages/MTPCore` 是独立 SwiftPM 包（swift-tools 6.0 / macOS 14+），用 Swift 直调 libusb 实现 MTP/PTP 协议，目标是替代上面的 Go/CGO 路径。**当前尚未接入主 app**（主 app 仍全走 `Kalam_*`），与 Go 后端并存，按 plan 分阶段实现（spike 阶段，写路径 sendObject/bulkWrite 尚未完成）。可独立 `swift test`。

### 分层（单向依赖：Protocol → Models → Encoding → Constants）

| 层 | 职责 | 关键文件 |
|----|------|----------|
| `Constants` | 纯数值常量表（对齐 Go `mtp/const.go`） | `OperationCode` / `ReturnCode`（Sendable） / `MTPConstants`（ContainerType、端点位、超时、buffer=0x4000） |
| `Encoding` | 小端字节流解码（对应 Go `encoding.go` 的 reflect-Decode，Swift 改为**显式逐字段**，线序一处维护） | `MTPReader`（readU8/16/32/64 + readU32Array/readU16Array 带 count 上限保护） / `MTPStrings`（UCS-2） / `MTPTime`（MTP 三变体时间） / `MTPDecodable` |
| `Models` | MTP 结构体（`MTPDecodable, Equatable`，字段序=线序，对齐 Go `types.go`） | `DeviceInfo` / `StorageInfo` / `ObjectInfo` / `Uint32Array` |
| `Protocol` | libusb 调用 + MTP 事务编排（最重，~1200 行） | `MTPDevice` / `MTPOperations` / `MTPTransactionPure` / `USBContext` / `MTPGlobalLock` / `MTPUSBTransfer` / `DeviceRecognition` / `EndpointClassification` |

### 黄金契约（与 Go 交叉验证）

Go `Native/encoding_golden_test.go` 的 `TestGenerateFixtures` 用 `mtp.Encode` 编码已知结构体生成 `Tests/.../Fixtures/*.json`（**真理源**）；Go `TestGoldenDecode` 与 Swift `EncodingGoldenTests` 都 decode 同一 JSON 断言，任一端回归立即被捕获。**改 fixture 流程**：改 Go 输入 → `go test -run TestGenerateFixtures` 重新生成 → `git add` → 两端 decode 自动校验。`Scripts/check_encoding_fixtures.sh` 防漂移。

### 并发与锁（关键约束）

- **禁止 actor/async/Task** —— 传统 `DispatchQueue` + 闭包并发（`project-exemption` 文件传输豁免：Swift 6 actor/async 会导致崩溃）。`MTPDevice` 是 `final class ... @unchecked Sendable`。
- **`MTPGlobalLock`**：进程级全局串行锁，对齐 Go `deviceMu`。所有 libusb 同步调用必须经此串行，**不得降级为 per-device 锁**。
- **局部加锁，禁止整事务加锁**：`bulkTransfer` 每次调用局部加锁；`runTransaction` 整体**绝不**进单把 `MTPGlobalLock.sync` 闭包 —— 否则 open 阶段的 P4（需调 getDeviceInfo→runTransaction→bulkTransfer）会重入串行队列死锁。

### MTP 事务流程（runTransaction，当前仅只读路径完成）

session 注入（锁外）→ COMMAND（`sendReq`）→ 读首包（`fetchPacket`+`parseBulkHeader`）→ 按 type 分派：DATA 则写 sink + `bulkRead` 循环至 short packet（**P1** SeparateHeader 探测 / **P2** XHCI 末包捎带 RESPONSE 复用）→ RESPONSE（`decodeRep` 校验 code）→ tid 校验。

### 设备厂商适配（对应 Go `mtp.go` 补丁）

- **P3 主路径**：接口串（iInterface）含 `MTP`/`CDC`/`ACM`（大小写敏感）→ 三星等。
- **P4 兜底**：iInterface==0 时读 `DeviceInfo.mtpExtension`，含 `microsoft/WindowsPhone` 或 `fujifilm.co.jp` → 微软/富士。
- **P5** SessionAlreadyOpened 恢复（close→open→reset+sleep+重开）。纯函数判定集中在 `MTPTransactionPure.swift`。

### 错误处理

`MTPError` enum（notOpen / alreadyOpen / noMTPInInterface / libusb(MTPUSBError) / rcError(ReturnCode) / syncError）。所有 libusb 调用经 `checkLibusb`（返回码<0 抛 libusb）；MTP 响应非 OK 抛 rcError；type/tid 失同步抛 syncError。解码侧独立 `MTPDecodeError`。

> 设计依据：`docs/superpowers/specs/2026-06-12-go-to-swift-mtp-backend-design.md` + `docs/superpowers/plans/`（本地设计文档，不入库）。

## 线程模型

| 组件 | 并发机制 | 说明 |
|------|----------|------|
| `DeviceManager` | `@MainActor` + `ObservableObject` | UI 状态在主线程更新，设备扫描在 `DispatchQueue.global()` |
| `FileSystemManager` | `actor` | 文件操作和缓存的线程安全 |
| `FileTransferManager` | `ObservableObject` + 专用 `DispatchQueue` | 传输在 `transferQueue` 执行，UI 更新切回 main queue |

## 项目结构

```
SwiftMTP/
├── Native/                          # Go 桥接层 (Kalam Kernel)
│   ├── kalam_bridge.go              # 设备扫描、初始化、字符串管理
│   ├── kalam_bridge_transfer.go     # 文件上传/下载
│   ├── kalam_config.go              # 安全配置、常量定义
│   ├── kalam_domain.go              # MTP 设备域操作
│   ├── kalam_pool.go                # 设备连接池
│   ├── *_test.go                    # Go 单元测试
│   └── vendor/                      # Go 依赖
├── Packages/
│   └── MTPCore/                     # 纯 Swift MTP 协议层（开发中,目标替代 Go 桥接）
│       ├── Sources/MTPCore/         # Constants/Encoding/Models/Protocol 四层
│       ├── Tests/MTPCoreTests/      # 纯函数测试 + Fixtures/（黄金契约 JSON）
│       └── README.md                # 黄金契约 + 线序依据 + 测试说明
├── SwiftMTP/                        # Swift 应用主体
│   ├── App/                         # 入口 (SwiftMTPApp.swift)
│   ├── Models/                      # Device, FileItem, TransferTask, AppError 等
│   ├── Services/
│   │   ├── MTP/                     # 核心业务
│   │   │   ├── DeviceManager.swift          # 设备检测（@MainActor 单例）
│   │   │   ├── FileSystemManager.swift      # 文件浏览（actor 单例）
│   │   │   ├── FileTransferManager.swift    # 文件传输（ObservableObject 单例）
│   │   │   └── FileTransferManager+DirectoryUpload.swift
│   │   ├── Protocols/               # 抽象接口（DeviceManaging, FileSystemManaging 等）
│   │   ├── LanguageManager.swift    # 多语言切换
│   │   ├── LocalizationManager.swift # NSLocalizedString 管理
│   │   └── UpdateChecker.swift      # GitHub 版本检查
│   ├── Views/                       # SwiftUI 视图
│   │   ├── MainWindowView.swift     # NavigationSplitView 主窗口
│   │   ├── DeviceListView.swift     # 设备列表（左侧导航）
│   │   ├── FileBrowserView.swift    # 文件浏览器（右侧主区域）
│   │   ├── FileBrowserView+Actions.swift    # 右键菜单操作
│   │   ├── FileBrowserView+ToolbarDrop.swift # 工具栏 + 拖拽上传
│   │   ├── FileTransferView.swift   # 传输进度视图
│   │   └── Components/              # 可复用组件
│   ├── Config/AppConfiguration.swift # 集中管理所有常量
│   └── Resources/{lang}.lproj/      # 8 语言本地化（en/zh-Hans/ja/ko/ru/fr/de/Base）
├── Scripts/
│   ├── build_kalam.sh               # Go 动态库构建 + @rpath 配置
│   ├── create_dmg_simple.sh         # DMG 打包
│   └── run_tests.sh                 # 测试脚本
└── docs/
    ├── TESTING.md                   # 测试文档
    ├── sequence-diagrams.md         # 时序图
    ├── architecture-diagrams.md     # 架构图
    └── superpowers/                 # spec/plan（本地设计文档,不入库）
```

## 禁止 / 必须

**禁止**:
- 非主线程更新 `@Published` / `@Observable` 状态
- 使用 `[unowned self]`（用 `[weak self]` 替代）
- 忘记调用 `Kalam_FreeString` 释放 Go 返回的字符串
- 在 `FileSystemManager`（actor）外部直接访问其属性（必须 `await`）
- 在 `MTPCore` 使用 actor/async/Task（用传统 DispatchQueue;Swift 6 actor 会导致传输崩溃）

**必须**:
- Go 代码变更后执行 `./Scripts/build_kalam.sh`
- Swift 代码变更后编译验证
- 遵循 `DeviceManager` 的 `@MainActor` 线程分离模式
- 新增配置常量放入 `AppConfiguration.swift`
- 改 `MTPCore` Encoding 结构体线序时,同步改 Go `types.go` 并重新生成黄金 fixture（`go test -run TestGenerateFixtures`）
- 编写代码前调用相关技能：`project-exemption`（检查豁免规则）、`moai-lang-swift`（Swift 6 规范）、`build-macos-apps`（macOS 开发规范）、`go-best-practices`（Go 规范）

## 提交前检查（强制）

1. `desloppify scan --path .` → 确保 `Open: 0`
2. 若涉及 Go/Native 变更：`desloppify --lang go scan --path Native`
3. `git push` 时调用 `git-workflow` 技能

## 设计原则

- **逻辑完备性**: 优先领域建模和正交设计，拒绝打补丁式地添加 flag 参数
- **无向后兼容负担**: 允许破坏旧格式以换取更干净的设计
- **重构熔断器**: 如果理想结构需要大规模重写，先说明范围和风险
- **避免静默失败**: 使用错误状态属性，不要吞掉错误

## 代码导航（CodeGraph MCP）

本项目已配置 CodeGraph MCP（`codegraph_*` 工具），对所有符号建立了知识图谱。查符号定义/调用关系/改动影响面/架构流程时，**优先用 `codegraph_explore`**（一次调用返回相关符号源码，Read 等价），不要 grep+read 循环。详见 `.cursor/rules/codegraph.mdc`。

<!-- desloppify-begin -->
<!-- desloppify-skill-version: 1 -->
---
name: desloppify
description: >
  Codebase health scanner and technical debt tracker. Use when the user asks
  about code quality, technical debt, dead code, large files, god classes,
  duplicate functions, code smells, naming issues, import cycles, or coupling
  problems. Also use when asked for a health score, what to fix next, or to
  create a cleanup plan. Supports 28 languages.
allowed-tools: Bash(desloppify *)
---

# Desloppify

## 1. Your Job

**Improve code quality by fixing findings and maximizing strict score honestly.**
Never hide debt with suppression patterns just to improve lenient score. After
every scan, show the user ALL scores:

| What | How |
|------|-----|
| Overall health | lenient + strict |
| 5 mechanical dimensions | File health, Code quality, Duplication, Test health, Security |
| 7 subjective dimensions | Naming Quality, Error Consistency, Abstraction Fit, Logic Clarity, AI Generated Debt, Type Safety, Contract Coherence |

Never skip scores. The user tracks progress through them.

## 2. Core Loop

```
scan → follow the tool's strategy → fix or wontfix → rescan
```

1. `desloppify scan --path .` — the scan output ends with **INSTRUCTIONS FOR AGENTS**. Follow them. Don't substitute your own analysis.
2. Fix the issue the tool recommends.
3. `desloppify resolve fixed "<id>"` — or if it's intentional/acceptable:
   `desloppify resolve wontfix "<id>" --note "reason why"`
4. Rescan to verify.

**Wontfix is not free.** It lowers the strict score. The gap between lenient and strict IS wontfix debt. Call it out when:
- Wontfix count is growing — challenge whether past decisions still hold
- A dimension is stuck 3+ scans — suggest a different approach
- Auto-fixers exist for open findings — ask why they haven't been run

## 3. Commands

```bash
desloppify scan --path src/               # full scan
desloppify scan --path src/ --reset-subjective  # reset subjective baseline to 0, then scan
desloppify next --count 5                  # top priorities
desloppify show <pattern>                  # filter by file/detector/ID
desloppify plan                            # prioritized plan
desloppify fix <fixer> --dry-run           # auto-fix (dry-run first!)
desloppify move <src> <dst> --dry-run      # move + update imports
desloppify resolve open|fixed|wontfix|false_positive "<pat>"   # classify/reopen findings
desloppify review --run-batches --runner codex --parallel --scan-after-import  # preferred blind review path
desloppify review --run-batches --runner codex --parallel --scan-after-import --retrospective  # include historical issue context for root-cause loop
desloppify review --prepare                # generate subjective review data (cloud/manual path)
desloppify review --external-start --external-runner claude  # recommended cloud durable path
desloppify review --external-submit --session-id <id> --import review_result.json  # submit cloud session output with canonical provenance
desloppify review --import file.json       # import review results
desloppify review --validate-import file.json  # validate payload/mode without mutating state
```

## 4. Subjective Reviews (biggest score lever)

Score = 40% mechanical + 60% subjective. Subjective starts at 0% until reviewed.

1. Preferred local path: `desloppify review --run-batches --runner codex --parallel --scan-after-import`.
   This prepares blind packets, runs isolated subagent batches, merges, imports, and rescans in one flow.

2. **Review each dimension independently.** For best results, review dimensions in
   isolation so scores don't bleed across concerns. If your agent supports parallel
   execution, use it — your agent-specific overlay (appended below, if installed)
   has the optimal approach. Each reviewer needs:
   - The codebase path and the dimensions to score
   - What each dimension means (from `query.json`'s `dimension_prompts`)
   - The output format (below)
   - Nothing else — let them decide what to read and how

3. Cloud/manual path: run `desloppify review --prepare`, perform isolated reviews,
   merge assessments (average scores if multiple reviewers cover the same dimension)
   and findings, then import:
   ```bash
   desloppify review --import findings.json
   ```
   Import is fail-closed by default: if any finding is invalid/skipped, import aborts.
   Use `--allow-partial` only for explicit exceptions.
   External imports ingest findings by default. For durable cloud-subagent scores,
   prefer the session flow:
   `desloppify review --external-start --external-runner claude` then use the generated
   `claude_launch_prompt.md` + `review_result.template.json`, and run the printed
   `desloppify review --external-submit --session-id <id> --import <file>` command.
   Legacy durable import remains available via
   `--attested-external --attest "I validated this review was completed without awareness of overall score and is unbiased."`
   (with valid blind packet provenance in the payload).
   Use `desloppify review --validate-import findings.json ...` to preflight schema
   and import mode before mutating state.
   Manual override cannot be combined with `--allow-partial`, and those manual
   assessment scores are provisional: they expire on the next `scan` unless
   replaced by trusted internal or attested-external imports.

   Required output format per reviewer:
   ```json
   {
     "session": { "id": "<session_id_from_template>", "token": "<session_token_from_template>" },
     "assessments": { "naming_quality": 75.0, "logic_clarity": 82.0 },
     "findings": [{
       "dimension": "naming_quality",
       "identifier": "short_id",
       "summary": "one line",
       "related_files": ["path/to/file.py"],
       "evidence": ["specific observation"],
       "suggestion": "concrete action",
       "confidence": "high|medium|low"
     }]
   }
   ```
   For non-session legacy imports (`review --import ... --attested-external`), `session` may be omitted.

4. **Fix findings via the core loop.** After importing, findings become tracked state
   entries. Fix each one in code, then resolve:
   ```bash
   desloppify issues                    # see the work queue
   # ... fix the code ...
   desloppify resolve fixed "<id>"      # mark as fixed
   desloppify scan --path .             # verify
   ```

**Do NOT fix findings before importing.** Import creates tracked state entries that
let desloppify correlate fixes to findings, track resolution history, and verify fixes
on rescan. If you fix code first and then import, the findings arrive as orphan issues
with no connection to the work already done.

Need a clean subjective rerun from zero? Run `desloppify scan --path src/ --reset-subjective` before preparing/importing fresh review data.

Even moderate scores (60-80) dramatically improve overall health.

Integrity safeguard:
- If one subjective dimension lands exactly on the strict target, the scanner warns and asks for re-review.
- If two or more subjective dimensions land on the strict target in the same scan, those dimensions are auto-reset to 0 for that scan and must be re-reviewed/imported.
- Reviewers should score from evidence only (not from target-seeking).

## 5. Quick Reference

- **Tiers**: T1 auto-fix, T2 quick manual, T3 judgment call, T4 major refactor
- **Zones**: production/script (scored), test/config/generated/vendor (not scored). Fix with `zone set`.
- **Auto-fixers** (TS only): `unused-imports`, `unused-vars`, `debug-logs`, `dead-exports`, etc.
- **query.json**: After any command, has `narrative.actions` with prioritized next steps.
- `--skip-slow` skips duplicate detection for faster iteration.
- `--lang python`, `--lang typescript`, or `--lang csharp` to force language.
- C# defaults to `--profile objective`; use `--profile full` to include subjective review.
- Score can temporarily drop after fixes (cascade effects are normal).

## 6. Escalate Tool Issues Upstream

When desloppify itself appears wrong or inconsistent:

1. Capture a minimal repro (`command`, `path`, `expected`, `actual`).
2. Open a GitHub issue in `peteromallet/desloppify`.
3. If you can fix it safely, open a PR linked to that issue.
4. If unsure whether it is tool bug vs user workflow, issue first, PR second.

## Prerequisite

`command -v desloppify >/dev/null 2>&1 && echo "desloppify: installed" || echo "NOT INSTALLED — run: pip install --upgrade git+https://github.com/peteromallet/desloppify.git"`

<!-- desloppify-end -->

## Codex Overlay

This is the canonical Codex overlay used by the README install command.

1. Prefer first-class batch runs: `desloppify review --run-batches --runner codex --parallel --scan-after-import`.
2. The command writes immutable packet snapshots under `.desloppify/review_packets/holistic_packet_*.json`; use those for reproducible retries.
3. Keep reviewer input scoped to the immutable packet and the source files named in each batch.
4. Do not use prior chat context, score history, narrative summaries, issue labels, or target-threshold anchoring while scoring.
5. Assess every dimension listed in `query.dimensions`; never drop a requested dimension. If evidence is weak/mixed, score lower and explain uncertainty in findings.
6. Return machine-readable JSON only for review imports. For Claude session submit (`--external-submit`), include `session` from the generated template:

```json
{
  "session": {
    "id": "<session_id_from_template>",
    "token": "<session_token_from_template>"
  },
  "assessments": {
    "<dimension_from_query>": 0
  },
  "findings": [
    {
      "dimension": "<dimension_from_query>",
      "identifier": "short_id",
      "summary": "one-line defect summary",
      "related_files": ["relative/path/to/file.py"],
      "evidence": ["specific code observation"],
      "suggestion": "concrete fix recommendation",
      "confidence": "high|medium|low"
    }
  ]
}
```

7. `findings` MUST match `query.system_prompt` exactly (including `related_files`, `evidence`, and `suggestion`). Use `"findings": []` when no defects are found.
8. Import is fail-closed by default: if any finding is invalid/skipped, `desloppify review --import` aborts unless `--allow-partial` is explicitly passed.
9. Assessment scores are auto-applied from trusted internal run-batches imports, or via Claude cloud session imports (`desloppify review --external-start --external-runner claude` then printed `--external-submit`). Legacy attested external import via `--attested-external` remains supported.
10. Manual override is safety-scoped: you cannot combine it with `--allow-partial`, and provisional manual scores expire on the next `scan` unless replaced by trusted internal or attested-external imports.
11. If a batch fails, retry only that slice with `desloppify review --run-batches --packet <packet.json> --only-batches <idxs>`.

<!-- desloppify-overlay: codex -->
<!-- desloppify-end -->

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do not use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
