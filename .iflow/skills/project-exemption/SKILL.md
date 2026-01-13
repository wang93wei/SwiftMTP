---
name: project-exemption
description: 项目豁免规则。文件传输模块必须使用传统并发模型，使用 Swift6 会导致应用崩溃。
---

# 项目豁免规则

## 适用范围

**文件传输模块** (`FileTransferManager.swift`)

## 豁免原因

使用 Swift 6 并发模型（`@MainActor`、`Actor`、`Sendable`）会导致应用崩溃。

## 强制要求

- 禁止将 `FileTransferManager.swift` 迁移到 Swift 6 并发模型
- 保持 `DispatchQueue` + `NSLock` 的实现方式
- CGO 桥接代码必须使用传统指针操作

## 其他模块

UI、状态管理、服务层等模块应优先采用 Swift 6 特性。