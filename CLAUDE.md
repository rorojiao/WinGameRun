# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

WinGameRun 是一个 macOS 游戏启动器，用于在 Apple Silicon Mac 上运行 Windows 游戏。Fork 自 [Bourbon](https://github.com/leonewt0n/Bourbon)（Whisky 的活跃分支），进行品牌重塑和功能增强。**当前项目处于设计阶段，源码尚未实现。**

设计文档位于 `docs/superpowers/specs/2026-03-25-wingamerun-design.md`。

## 构建与开发命令

项目为 Xcode + SPM 工程，尚未创建 Xcode 项目文件。基础命令（Xcode 工程创建后适用）：

```bash
# 构建（命令行）
xcodebuild -project WinGameRun.xcodeproj -scheme WinGameRun -configuration Debug build

# 运行单元测试（CI 可用）
xcodebuild test -project WinGameRun.xcodeproj -scheme WinGameRun -testPlan UnitTests

# 运行集成测试（需本地 Wine + Rosetta 2）
xcodebuild test -project WinGameRun.xcodeproj -scheme WinGameRun -testPlan IntegrationTests

# SPM 依赖（在 WinGameKit/ 目录下）
swift package resolve
swift build
swift test
```

**注意：** 集成测试和 UI 测试需要安装 Wine 和 Rosetta 2，GitHub Actions CI 只运行单元测试。

## 架构

四个 Target 的模块化结构：

| 模块 | 类型 | 职责 |
|------|------|------|
| `WinGameRun/` | SwiftUI App Target | UI、视图、应用生命周期 |
| `WinGameKit/` | Swift Package (SPM) | 核心库：Bottle/Program 模型、Wine 进程管理、Steam 集成、PE 文件解析 |
| `WinGameCmd/` | CLI Tool Target | 无头 Wine 操作 |
| `WinGameThumbnail/` | Extension Target | 缩略图生成 |

### 数据流（MVVM）

```
SwiftUI Views → BottleVM (ObservableObject) → WinGameKit 方法 → Process() → Wine 运行时
```

- `BottleVM` 持有全局 Bottle 列表，作为 `@EnvironmentObject` 传递
- `Bottle` 对象管理单个 Wine prefix，`Program` 管理单个游戏/程序

### 翻译栈

Windows 游戏在 Apple Silicon 上需三层翻译：Rosetta 2（x86→ARM64）+ Wine（Windows API→POSIX）+ D3DMetal/DXMT（DirectX→Metal）

### 文件存储

应用**不使用 App Sandbox**（Wine 需要广泛文件系统权限）。

```
~/Library/Application Support/com.wingamerun.app/Libraries/  # Wine 二进制和图形 DLL
~/WinGameRun/Bottles/                                          # 默认 Bottle 位置（用户可自定义）
~/Library/Preferences/com.wingamerun.app.plist               # UserDefaults（含 Bottle 路径列表）
~/Library/Logs/com.wingamerun.app/                           # Wine 进程日志
```

## 关键实现约束

1. **D3DMetal 不可内置分发**：必须引导用户通过 `developer.apple.com` 下载安装 GPTK 3.0
2. **Rosetta 2 必需**：Wine 为 x86 二进制，首次运行前必须检测
3. **最低系统要求**：macOS 13.0+（Ventura）
4. **GPL v3**：Fork 约束，所有修改必须开源，保留原始版权声明
5. **分发方式**：GitHub Release（.dmg），无 App Store，无 Apple 公证

## 品牌重塑映射

从 Bourbon/Whisky 重命名时的对照表：

| 原始名称 | 新名称 |
|---------|--------|
| `WhiskyKit` | `WinGameKit` |
| `WhiskyCmd` | `WinGameCmd` |
| `WhiskyWineInstaller` | `WineInstaller` |
| `com.leonewton.Bourbon` | `com.wingamerun.app` |
| `WhiskyWineDownloadView` | `WineDownloadView` |

注意：`View Models/` 目录名保留原始空格（Xcode 约定）。

## 第三方依赖

| 依赖 | 用途 |
|------|------|
| `sparkle-project/Sparkle` | 应用自动更新，appcast.xml 指向 WinGameRun GitHub Release |
| `SwiftPackageIndex/SemanticVersion` | Wine 版本号比较 |

## 新增功能（相比 Bourbon）

- **GPTK 引导安装**（`GPTKGuideView.swift`）：检测 D3DMetal 路径（`/Library/Apple/usr/lib/d3d/` 等），引导安装或跳过使用 DXMT
- **Steam 集成**（`WinGameKit/Steam/`）：安装 Windows Steam、解析 `libraryfolders.vdf`（非标准 Valve KeyValue 格式，需自写解析器）、通过 `steam://rungameid/<appId>` 启动游戏
