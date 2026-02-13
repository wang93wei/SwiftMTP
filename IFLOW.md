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

## 概述
- **类型**: macOS Android MTP文件传输工具
- **技术栈**: Swift 6+ / SwiftUI / Go / libusb-1.0
- **架构**: MVVM + 单例模式
- **平台**: macOS 26.0+

## 核心原则
增量开发 → 编译验证 → 测试通过 → 提交

## 项目结构
```
SwiftMTP/
├── Native/          # Go桥接层(Kalam)
├── Scripts/         # 构建脚本
└── SwiftMTP/        # Swift应用
    ├── App/         # 入口
    ├── Models/      # 数据模型
    ├── Services/    # 业务逻辑(MTP/)
    └── Views/       # SwiftUI视图
```

## 关键规范
- **单例**: `DeviceManager.shared`, `FileSystemManager.shared`
- **线程**: UI操作在主线程，耗时操作在global queue
- **内存**: `[weak self]`保护闭包，Go/C内存手动释放
- **错误**: 避免静默失败，使用错误状态属性

## Go桥接
- 函数前缀: `Kalam_`
- 返回: JSON字符串指针，错误返回`nil`
- 必须调用`Kalam_FreeString`释放内存

## 构建命令
```bash
# 构建桥接 --每次 go 代码变更后都需要检查，是否报错，强制使用
./Scripts/build_kalam.sh

# Xcode编译 --每次 Swift 代码变更后都需要编译，检查是否报错，强制使用
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP build
```

## 打包要求（强制）
- 只能在项目根目录下，调用[create_dmg_simple.sh](Scripts/create_dmg_simple.sh)脚本打包

## 重要提醒
**禁止**:
- 非主线程更新SwiftUI状态
- 使用`[unowned self]`
- 忘记释放`Kalam_FreeString`

**必须**:
- 遵循`DeviceManager`线程分离模式
- 使用`[weak self]`保护异步闭包
- 增量提交可运行代码
- 在编写代码前，调用相关技能，例如 [Swift6](../skills/moai-lang-swift)、[macos 开发规范 ](../skills/build-macos-apps)、[go 最佳实践](../skills/go-best-practices)等内容辅助开发