# ENGINEERING GUIDELINES

### Code Readability
* Use meaningful variable and function names.
* Comments must be added only when necessary.
* Use comments to explain "why," not "what." Good code is self-documenting and explains what it does. Comments should be reserved for explaining design decisions or complex logic.
* Avoid clutter. Do not write obvious comments, such as `i++ // Increment i by 1`.
* Avoid Hardcoding: Extract unexplained numeric and string values into named constants.

### Best Practices
* Break down complex problems into smaller, manageable parts
* Consider performance implications early and profile critical paths
* Review code for correctness, robustness, and edge cases
* Use appropriate tools and skills (MCP tools, skills, etc.) based on task requirements
* Every time must run `project-exemption` skill to check if the code is compliant with the project exemption rules.

### Design for Testability
* No Direct Instantiation: Prohibit instantiating external dependencies directly inside functions (DB, API clients, etc.) .
* Dependency Injection: Ensure all dependencies are provided externally via the constructor or method parameters.
* Dependency Inversion: Define Interfaces for all external dependencies; business logic must rely on these abstractions rather than concrete implementations.
* Avoid Global State: Ban the use of Singletons or global variables unless absolutely necessary and properly encapsulated, as they impede test isolation.

### Design Principles
* Principle of Least Surprise: Design logic to be intuitive. Code implementation must behave as a developer expects, and functional design must align with the user's intuition.
* Logical Completeness: Prioritize first-principles domain modeling and logical orthogonality; favor refactoring core structures to capture native semantics over adding additive flags or 'patch' parameters.
* No Backward Compatibility: Prioritize architectural correctness over legacy support. You are free to break old formats if it results in a cleaner design.
* Refactoring Circuit Breaker: If achieving the ideal structure requires a massive, high-risk rewrite (e.g., changing core assumptions), STOP and explain the scope and complexity first. 

## 技术架构
- **语言**: Swift 6+, Go 1.22+
- **UI**: SwiftUI
- **架构**: MVVM, Combine
- **依赖**: libmtp, go-mtpx, libusb-1.0
- **桥接**: CGO (Swift ↔ C ↔ Go)

## 项目结构
Native/ (Go 桥接), Scripts/ (构建脚本), SwiftMTP/ (App/Models/Services/Views/Resources/)

## 核心原则
增量开发 → 编译验证 → 测试通过 → 提交

## 常用命令
```bash
# 构建
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug
scripts/build.sh

# 清理
xcodebuild clean -project SwiftMTP.xcodeproj -scheme SwiftMTP

# 依赖
brew install go libusb
```

## 状态管理
DeviceManager.shared: 设备检测
FileSystemManager.shared: 文件浏览
FileTransferManager.shared: 文件传输

## 目标平台与限制
macOS 26.0+, Android MTP 模式。单设备支持、需禁用沙盒、仅单个文件上传。

## 文件传输模块 Swift 6 优化豁免

### 背景
`FileTransferManager.swift` 是核心的文件传输模块，负责在 Swift 与 Go 桥接层之间进行大文件的上传/下载操作。

### 豁免原因

1. **CGO 互操作性限制**
   - 文件传输需要直接调用 Go 层的 C 函数（`Kalam_UploadFile`、`Kalam_DownloadFile`）
   - 这些 C 函数要求使用传统的 C 指针和内存管理模型
   - 必须使用 `withCString`、`UnsafeMutablePointer`、`strdup` 等底层 API

2. **线程安全模型约束**
   - 传输队列需要细粒度的并发控制（`DispatchQueue` + `NSLock`）
   - 进度回调需要在主线程更新 UI（`@MainActor` + `DispatchQueue.main.async`）
   - 改用 Swift 6 的 `Actor` 模型会破坏现有的线程同步逻辑

3. **性能关键路径**
   - 文件传输是 I/O 密集型操作，需要控制并发队列的 QoS
   - `DispatchQueue` 提供了更灵活的资源调度策略
   - 内存分配和释放需要精确控制时机

4. **代码复杂度**
   - 当前实现已通过多轮测试验证稳定性
   - 强制迁移会导致大量 `UnsafeMutablePointer` 重构
   - 风险收益比不划算

### 结论
文件传输模块保持当前实现，不强制遵循 Swift 6 并发规则。其他模块（UI、状态管理）应优先采用 Swift 6 特性。