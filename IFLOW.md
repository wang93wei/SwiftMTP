# ENGINEERING GUIDELINES

### Code Readability
* Use meaningful variable and function names.
* Comments must be added only when necessary.
* Use comments to explain "why," not "what." Good code is self-documenting and explains what it does. Comments should be reserved for explaining design decisions or complex logic.
* Avoid clutter. Do not write obvious comments, such as `i++ // Increment i by 1`.
* Avoid Hardcoding: Extract unexplained numeric and string values into named constants.

### Best Practices
* Break down complex problems into smaller, manageable parts
* Consider performance implications
* Always review code for rightness and correctness.
* Use appropriate tools (agents, MCP tools, etc.) based on task requirements.

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
- **语言**: Swift 5.9+, Go 1.22+
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
macOS 13.0+, Android MTP 模式。单设备支持、需禁用沙盒、仅单个文件上传。