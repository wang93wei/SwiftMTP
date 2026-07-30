# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述
macOS 原生 Android MTP 文件传输工具。Swift 前端通过 CGO 桥接调用 Go MTP 库操作 USB 设备。

- **技术栈**: Swift 6+ / SwiftUI / Go 1.26 / libusb-1.0
- **架构**: MVVM + 单例模式（`DeviceManager.shared`, `FileSystemManager.shared`, `FileTransferManager.shared`）
- **平台**: macOS 26.0+，沙盒已禁用以访问 USB 设备

## 构建命令

```bash
# Go 桥接层（每次 Go 代码变更后必须执行）
./Scripts/build_kalam.sh

# Swift 编译（优先使用 Xcode MCP；未启用则用 xcodebuild）
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP build

# Go 单元测试
cd Native && go test ./...

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
    ├── TESTING.md                   # 测试文档（当前待补充）
    └── sequence-diagrams.md         # 时序图
```

## 禁止 / 必须

**禁止**:
- 非主线程更新 `@Published` / `@Observable` 状态
- 使用 `[unowned self]`（用 `[weak self]` 替代）
- 忘记调用 `Kalam_FreeString` 释放 Go 返回的字符串
- 在 `FileSystemManager`（actor）外部直接访问其属性（必须 `await`）

**必须**:
- Go 代码变更后执行 `./Scripts/build_kalam.sh`
- Swift 代码变更后编译验证
- 遵循 `DeviceManager` 的 `@MainActor` 线程分离模式
- 新增配置常量放入 `AppConfiguration.swift`
- 编写代码前调用相关技能：`project-exemption`（检查豁免规则）、`moai-lang-swift`（Swift 6 规范）、`build-macos-apps`（macOS 开发规范）、`go-best-practices`（Go 规范）

## 提交前检查（强制）

1. `git push` 时调用 `git-workflow` 技能

## 设计原则

- **逻辑完备性**: 优先领域建模和正交设计，拒绝打补丁式地添加 flag 参数
- **无向后兼容负担**: 允许破坏旧格式以换取更干净的设计
- **重构熔断器**: 如果理想结构需要大规模重写，先说明范围和风险
- **避免静默失败**: 使用错误状态属性，不要吞掉错误

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


<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
