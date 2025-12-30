# SwiftMTP 单元测试文档

## 概述

本文档描述了 SwiftMTP 项目的单元测试框架、测试用例、测试覆盖率以及如何运行测试。

## 测试框架

### Swift 测试框架
- **框架**: XCTest (Xcode 内置)
- **测试目标**: SwiftMTPTests
- **运行方式**: Xcode 或命令行 (xcodebuild)

### Go 测试框架
- **框架**: testing (Go 标准库)
- **测试文件**: kalam_bridge_test.go
- **运行方式**: `go test`

## 测试文件结构

```
SwiftMTP/
├── SwiftMTPTests/                          # Swift 测试目录
│   ├── DeviceTests.swift                   # Device 模型测试
│   ├── FileItemTests.swift                 # FileItem 模型测试
│   ├── TransferTaskTests.swift             # TransferTask 模型测试
│   ├── AppLanguageTests.swift              # AppLanguage 枚举测试
│   ├── LanguageManagerTests.swift          # LanguageManager 服务测试
│   ├── FileSystemManagerTests.swift        # FileSystemManager 服务测试
│   └── FileTransferManagerTests.swift      # FileTransferManager 服务测试
├── Native/
│   └── kalam_bridge_test.go                # Go 桥接层测试
└── Scripts/
    └── run_tests.sh                        # 测试运行脚本
```

## 测试覆盖范围

### Models 层测试

#### 1. DeviceTests.swift
测试 `Device`、`StorageInfo` 和 `MTPSupportInfo` 模型：

- **StorageInfo 测试**:
  - 初始化测试
  - 已用空间计算
  - 使用率百分比计算
  - 边界条件测试（零容量、非常大的值）

- **MTPSupportInfo 测试**:
  - 初始化测试
  - 空字段测试

- **Device 测试**:
  - 初始化测试
  - 存储信息测试
  - MTP 支持信息测试
  - 显示名称逻辑测试
  - 总容量和可用空间计算
  - Hashable 和 Equatable 协议测试
  - 电池电量边界测试
  - 多存储设备测试

**测试用例数**: 约 40+ 个

#### 2. FileItemTests.swift
测试 `FileItem` 模型：

- **初始化测试**:
  - 文件初始化
  - 文件夹初始化
  - 包含子项的文件夹初始化

- **文件扩展名测试**:
  - 常见扩展名
  - 多个点的文件名
  - 无扩展名文件
  - 文件夹（应返回空）
  - 隐藏文件

- **格式化大小测试**:
  - 字节、千字节、兆字节、吉字节
  - 文件夹显示
  - 零大小文件
  - 边界条件（非常大的文件）

- **格式化日期测试**:
  - 有效日期
  - nil 日期
  - 当前日期
  - 边界条件（epoch 之前、未来日期）

- **可比较性测试**:
  - 按名称排序
  - 大小写不敏感
  - 数字排序
  - Hashable 和 Equatable 协议

- **特殊字符和 Unicode 测试**:
  - 特殊字符
  - 中文、日文、韩文字符

**测试用例数**: 约 50+ 个

#### 3. TransferTaskTests.swift
测试 `TransferTask`、`TransferType` 和 `TransferStatus` 模型：

- **TransferType 测试**:
  - 原始值测试
  - Codable 支持

- **TransferStatus 测试**:
  - 所有状态测试
  - 活跃状态判断
  - 等价性测试
  - Codable 支持

- **TransferTask 测试**:
  - 初始化测试
  - 进度计算
  - 格式化进度
  - 速度格式化（B/s、KB/s、MB/s）
  - 预计剩余时间
  - 状态更新
  - 取消状态线程安全
  - 边界条件（大文件、进度溢出）

**测试用例数**: 约 40+ 个

#### 4. AppLanguageTests.swift
测试 `AppLanguage` 枚举：

- **原始值测试**
- **ID 属性测试**
- **显示名称测试**
- **区域标识符测试**
- **CaseIterable 测试**
- **Identifiable 测试**
- **初始化测试**
- **字符串比较测试**
- **显示名称唯一性测试**
- **Unicode 测试**
- **一致性测试**
- **Hashable 和 Equatable 测试**
- **性能测试**

**测试用例数**: 约 30+ 个

### Services 层测试

#### 5. LanguageManagerTests.swift
测试 `LanguageManager` 服务：

- **单例测试**
- **初始化测试**
- **语言变更测试**:
  - 切换到英语、中文、日语、韩语
  - 系统默认
  - 多次语言变更

- **本地化测试**:
  - 有效键
  - 无效键
  - 空键
  - 一致性测试

- **语言持久化测试**
- **通知测试**
- **区域标识符测试**
- **清理测试**
- **边界条件**:
  - 快速语言变更
  - 所有支持的键

- **性能测试**

**测试用例数**: 约 25+ 个

#### 6. FileSystemManagerTests.swift
测试 `FileSystemManager` 服务：

- **单例测试**
- **缓存测试**:
  - 清除缓存
  - 清除设备缓存
  - 强制清除缓存
  - 多次清除

- **获取文件列表测试**:
  - 根目录
  - 自定义目录
  - 不同存储
  - 无存储设备

- **获取子文件测试**:
  - 有效父目录
  - 文件作为父目录

- **缓存键测试**
- **线程安全测试**:
  - 并发缓存操作
  - 并发文件列表请求

- **边界条件**:
  - nil 设备
  - 非常大的父目录 ID
  - 多存储设备

- **性能测试**

**测试用例数**: 约 25+ 个

#### 7. FileTransferManagerTests.swift
测试 `FileTransferManager` 服务：

- **单例测试**
- **发布属性测试**:
  - 活跃任务
  - 已完成任务

- **上传验证测试**:
  - 不存在的文件
  - 目录
  - 空路径
  - 大文件（>10GB）
  - 存储空间不足
  - 无效存储 ID

- **下载测试**:
  - 有效文件项
  - 目录文件项
  - 已存在的目标位置

- **任务管理测试**:
  - 清除已完成任务
  - 取消所有任务
  - 取消单个任务

- **边界条件**:
  - 符号链接
  - 相对路径
  - 多次上传

- **线程安全测试**:
  - 并发上传

- **性能测试**

**测试用例数**: 约 30+ 个

### Go 层测试

#### 8. kalam_bridge_test.go
测试 Go 桥接层核心功能：

- **常量测试**:
  - 超时设置
  - 重试设置
  - 退避设置
  - 文件大小限制
  - MTP 对象格式

- **互斥锁测试**:
  - 锁定/解锁
  - 并发访问

- **取消任务测试**:
  - 映射操作
  - 并发访问

- **JSON 编码/解码测试**

- **退避计算测试**

- **文件大小验证测试**

- **超时选择测试**

- **重试计数测试**

- **MTP 对象格式测试**

- **并发安全测试**

- **边界条件测试**:
  - 零值
  - 最大值

- **基准测试**:
  - 互斥锁性能
  - 取消任务访问性能
  - JSON 编码/解码性能
  - 退避计算性能

**测试用例数**: 约 20+ 个

## 运行测试

### 运行所有测试

```bash
# 使用测试脚本
./Scripts/run_tests.sh

# 或分别运行
./Scripts/run_tests.sh --swift-only    # 仅运行 Swift 测试
./Scripts/run_tests.sh --go-only       # 仅运行 Go 测试
./Scripts/run_tests.sh --coverage      # 运行测试并生成覆盖率报告
```

### 运行 Go 测试

```bash
cd Native
go test -v ./...

# 带覆盖率
go test -v -coverprofile=coverage.out -covermode=atomic ./...
go tool cover -html=coverage.out -o coverage.html
```

### 运行 Swift 测试

```bash
# 使用 xcodebuild
xcodebuild test \
  -project SwiftMTP.xcodeproj \
  -scheme SwiftMTP \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# 带覆盖率
xcodebuild test \
  -project SwiftMTP.xcodeproj \
  -scheme SwiftMTP \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

## 代码覆盖率

### 生成覆盖率报告

```bash
# 使用测试脚本
./Scripts/run_tests.sh --coverage

# 覆盖率报告将生成在 build/coverage/ 目录
# - Swift: build/coverage/swift_coverage.txt, build/coverage/swift_coverage.json
# - Go: build/coverage/go_coverage.txt, build/coverage/go_coverage.html
```

### 覆盖率目标

- **Models 层**: 目标 90%+
- **Services 层**: 目标 80%+
- **Go 层**: 目标 70%+

## CI/CD 集成

项目使用 GitHub Actions 进行自动化测试：

### 工作流文件
- `.github/workflows/test.yml`

### 触发条件
- Push 到 `main` 或 `develop` 分支
- Pull Request 到 `main` 或 `develop` 分支
- 手动触发

### 工作流步骤
1. **Swift 测试**:
   - 设置 Xcode
   - 安装依赖
   - 构建 Kalam Bridge
   - 运行 Swift 测试
   - 生成覆盖率报告

2. **Go 测试**:
   - 设置 Go
   - 安装依赖
   - 运行 Go 测试
   - 生成覆盖率报告

3. **覆盖率汇总**:
   - 下载所有覆盖率报告
   - 显示覆盖率摘要

## 测试最佳实践

### 1. 测试命名
- 使用描述性的测试名称
- 格式: `test[功能][场景]`
- 示例: `testFileSizeValidationWithLargeFile`

### 2. 测试结构
- Arrange (准备): 设置测试数据
- Act (执行): 调用被测试的代码
- Assert (断言): 验证结果

### 3. 边界条件
- 测试零值
- 测试最大值
- 测试负值（如适用）
- 测试空集合

### 4. 异常情况
- 测试 nil 输入
- 测试无效输入
- 测试网络错误
- 测试文件系统错误

### 5. 线程安全
- 测试并发访问
- 测试竞态条件
- 使用适当的同步机制

### 6. 性能测试
- 对关键路径进行基准测试
- 监控性能回归
- 使用 `measure` (Swift) 或 `Benchmark` (Go)

## 持续改进

### 待添加的测试
- [ ] Views 层测试（UI 组件）
- [ ] 集成测试
- [ ] 端到端测试
- [ ] 性能回归测试

### 测试覆盖率提升
- [ ] 增加边界条件测试
- [ ] 增加错误处理测试
- [ ] 增加并发场景测试

## 故障排除

### 常见问题

1. **Swift 测试失败**:
   - 确保 Kalam Bridge 已构建
   - 检查 libkalam.dylib 是否存在
   - 运行 `./Scripts/build_kalam.sh`

2. **Go 测试失败**:
   - 确保依赖已下载
   - 运行 `go mod download`
   - 检查 Go 版本是否 >= 1.25

3. **覆盖率报告未生成**:
   - 确保 xcrun 可用
   - 检查测试是否通过
   - 查看构建日志

## 参考资料

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Go Testing Package](https://golang.org/pkg/testing/)
- [Xcode Build Settings Reference](https://developer.apple.com/documentation/xcode/build-settings-reference)

## 更新日志

### 2025-12-31
- 初始测试框架设置
- 添加 Models 层测试（Device, FileItem, TransferTask, AppLanguage）
- 添加 Services 层测试（LanguageManager, FileSystemManager, FileTransferManager）
- 添加 Go 层测试（kalam_bridge）
- 配置 CI/CD 工作流
- 创建测试运行脚本
- 生成测试文档