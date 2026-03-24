# WinGameRun 设计文档

## 概述

WinGameRun 是一个基于 SwiftUI 的 macOS 游戏启动器，用于在 Apple Silicon Mac 上运行 Windows 游戏。项目通过 Fork [Bourbon](https://github.com/leonewt0n/Bourbon)（Whisky 的活跃分支）进行品牌重塑和功能增强。

## 核心决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 定位 | 开源社区项目 (GitHub) | 面向 Mac 游戏社区 |
| 基础 | Fork Bourbon | 成熟的 Wine 管理核心，最快出活 |
| 许可证 | GPL v3（继承自 Bourbon） | Fork 约束 |
| 游戏来源 | 手动添加 .exe + Steam 集成 | MVP 最小范围 |
| 图形后端 | 优先 D3DMetal（引导安装），内置 DXMT 备选 | 性能与开源平衡 |
| UI 风格 | 原生 macOS 简洁风（保持 Bourbon 风格） | 用户友好 |
| Wine 分发 | 首次启动自动下载 | App 体积小，更新灵活 |

## 技术背景

### 翻译层栈

Mac 上运行 Windows 游戏需要三层翻译：

```
Windows 游戏 (.exe)
    │
    ├─ Rosetta 2: x86_64 → ARM64（CPU 指令翻译）
    ├─ Wine: Windows API → macOS/POSIX API（系统调用翻译）
    └─ D3DMetal: DirectX → Metal（图形 API 翻译）
```

### 图形后端

| 后端 | 翻译路径 | DX 支持 | 开源 |
|------|---------|---------|------|
| D3DMetal | DirectX → Metal（直接） | DX11, DX12 | 否（Apple 闭源） |
| DXMT | DirectX → Metal | DX10, DX11 | 是 |
| DXVK | DirectX → Vulkan → MoltenVK → Metal | DX10, DX11 | 是 |

## 架构

### 项目结构

```
WinGameRun/
├── WinGameRun/                  # 主应用（原 Whisky/）
│   ├── AppDelegate.swift        # 应用生命周期（URL scheme、文件关联）
│   ├── Views/
│   │   ├── WinGameRunApp.swift  # @main 入口 + Sparkle 更新
│   │   ├── ContentView.swift    # NavigationSplitView 主界面
│   │   ├── SparkleView.swift    # 自动更新 UI
│   │   ├── Bottle/              # Bottle（Wine 前缀）管理 UI
│   │   ├── Programs/            # 程序管理 UI
│   │   ├── Setup/               # 首次运行向导
│   │   │   ├── SetupView.swift
│   │   │   ├── WelcomeView.swift
│   │   │   ├── RosettaView.swift
│   │   │   ├── WineDownloadView.swift   # 原 WhiskyWineDownloadView
│   │   │   ├── WineInstallView.swift    # 原 WhiskyWineInstallView
│   │   │   └── GPTKGuideView.swift      # 新增
│   │   └── Settings/
│   ├── View Models/             # 注意：目录名保留原始空格
│   │   └── BottleVM.swift       # ObservableObject 全局状态
│   ├── Utils/
│   ├── Extensions/
│   ├── Assets.xcassets/
│   ├── Localizable.xcstrings    # 多语言（保留现有翻译）
│   └── WinGameRun.entitlements
│
├── WinGameKit/                  # 核心库（原 WhiskyKit/）
│   ├── Package.swift            # SPM 包定义
│   └── Sources/WinGameKit/
│       ├── Whisky/              # Bottle/Program 数据模型
│       │   ├── Bottle.swift
│       │   ├── BottleData.swift
│       │   ├── BottleSettings.swift
│       │   ├── Program.swift
│       │   └── ProgramSettings.swift
│       ├── Wine/
│       │   └── Wine.swift       # Wine 进程启动和管理
│       ├── WhiskyWine/
│       │   └── WineInstaller.swift  # 原 WhiskyWineInstaller，引擎下载和安装
│       ├── Steam/
│       │   ├── SteamIntegration.swift  # 新增：Steam 安装和启动
│       │   └── VDFParser.swift         # 新增：Valve KeyValue 格式解析
│       ├── PE/                  # Windows PE 文件解析
│       └── Extensions/
│
├── WinGameCmd/                  # CLI 工具
└── WinGameThumbnail/            # 缩略图扩展
```

### 第三方依赖

| 依赖 | 用途 | 来源 |
|------|------|------|
| SemanticVersion | Wine 版本号比较 | SPM |
| Sparkle | 应用自动更新 | SPM (sparkle-project/Sparkle) |

MVP 保留 Sparkle 自动更新框架，appcast.xml 改为指向 WinGameRun 的 GitHub Release。

### 数据流

```
┌─────────────────────────────────────────┐
│         SwiftUI UI Layer                 │
│  (WinGameRun/Views/*.swift)              │
└─────────────┬───────────────────────────┘
              │ @EnvironmentObject / @Published
┌─────────────▼───────────────────────────┐
│     View Models (MVVM)                   │
│  - BottleVM: 全局 Bottle 列表            │
│  - Bottle: 单个 Wine 前缀               │
│  - Program: 单个游戏/程序                │
└─────────────┬───────────────────────────┘
              │ 方法调用
┌─────────────▼───────────────────────────┐
│     WinGameKit 核心库                    │
│  - Wine.runProgram()  进程管理           │
│  - WineInstaller      引擎管理           │
│  - SteamIntegration   Steam 集成         │
│  - PEFile             文件解析           │
└─────────────┬───────────────────────────┘
              │ Process()
┌─────────────▼───────────────────────────┐
│     运行时                               │
│  Wine + D3DMetal/DXMT + Rosetta 2       │
│  ~/Library/Application Support/          │
│     com.wingamerun.app/Libraries/        │
└─────────────────────────────────────────┘
```

### 文件存储

应用**不使用沙盒**（Wine 需要大量文件系统和进程权限）。Bottle 路径索引通过 UserDefaults 存储，Bottle 目录可以位于用户指定的任意位置。

```
~/Library/
├── Application Support/
│   └── com.wingamerun.app/
│       ├── Libraries/
│       │   ├── Wine/bin/          # Wine 二进制
│       │   ├── DXVK/             # DXVK DLL
│       │   └── DXMT/             # DXMT DLL
│       └── WineVersion.plist
│
├── Preferences/
│   └── com.wingamerun.app.plist   # UserDefaults（含 Bottle 路径列表）
│
└── Logs/
    └── com.wingamerun.app/
        └── <timestamp>.log        # Wine 进程日志

# Bottles 默认位置（用户可自定义）
~/WinGameRun/
└── Bottles/
    └── Default/
        ├── drive_c/               # Windows 文件系统
        └── Metadata.plist         # Bottle 配置
```

## 改造清单

### 1. 品牌重塑（重命名）

| 原始 | 改为 |
|------|------|
| Bourbon / Whisky | WinGameRun |
| WhiskyKit | WinGameKit |
| WhiskyCmd | WinGameCmd |
| WhiskyThumbnail | WinGameThumbnail |
| WhiskyWineInstaller | WineInstaller |
| WhiskyWineDownloadView | WineDownloadView |
| WhiskyWineInstallView | WineInstallView |
| com.leonewton.Bourbon | com.wingamerun.app |
| Bourbon.xcodeproj | WinGameRun.xcodeproj |

需要改的位置：
- Xcode 项目文件和 target 名称
- Bundle Identifier
- Info.plist
- 代码中所有 bundleIdentifier / "Whisky" / "Bourbon" 字符串引用
- 文件存储路径常量（applicationFolder 等）
- App 图标和启动画面
- Sparkle appcast.xml 更新源 URL
- README 和许可证声明（需保留 GPL v3 原始版权声明）
- Localizable.xcstrings 中的品牌名字符串

### 2. Wine 引擎下载源改造

原 Bourbon 从自己的仓库 `Libraries.tar.gz`（Git LFS）下载预编译 Wine tarball。WinGameRun 的策略：

**初期（MVP）：** 在 WinGameRun 自己的 GitHub Release 中托管预编译 Wine tarball（从 Bourbon 或 Gcenx 构建打包），通过 GitHub Release API 分发。

**后续：** 考虑接入 Gcenx 维护的 Homebrew Wine 包或其他公共 Wine 构建源。

```swift
// WinGameKit/Sources/WinGameKit/WhiskyWine/WineInstaller.swift
// 原类名 WhiskyWineInstaller → 重命名为 WineInstaller
struct WineInstaller {
    // 从 WinGameRun 自己的 GitHub Release 下载
    static let wineReleasesAPI = "https://api.github.com/repos/<owner>/WinGameRun/releases/latest"

    // Wine tarball 实际大小需要验证（Bourbon 的 Libraries.tar.gz 为 LFS 指针）
    // 预计 200-400MB 压缩包

    // 下载流程：
    // 1. 查询 GitHub Release 中的 Wine tarball asset
    // 2. 通过 URLSession 下载（显示进度条）
    // 3. 解包到 ~/Library/Application Support/com.wingamerun.app/Libraries/Wine/
    // 4. xattr -cr 移除 quarantine 属性
    // 5. 验证 Wine/bin/wine64 可执行
}
```

### 3. GPTK 安装引导（新功能）

新增 `GPTKGuideView.swift`，在首次运行向导中引导用户安装 D3DMetal：

```swift
// 检测 D3DMetal 是否可用
func isD3DMetalAvailable() -> Bool {
    // GPTK 不同版本的安装路径：
    // GPTK 1.x (Homebrew): /usr/local/opt/game-porting-toolkit/
    // GPTK 2.0+: /usr/local/lib/d3d/
    // GPTK 3.0 (.dmg installer): /Library/Apple/usr/lib/d3d/
    // 需要检查所有可能路径
}

// 引导流程：
// 1. 检测是否已安装
// 2. 如未安装，显示步骤：
//    a. "访问 developer.apple.com/download/all 下载 Game Porting Toolkit 3.0"
//    b. "打开 .dmg 文件并运行安装器"
//    c. "点击'验证安装'按钮"
// 3. 验证安装成功后继续
// 4. 提供"跳过（使用 DXMT）"选项
```

### 4. Steam 集成（新功能）

新增 `WinGameKit/Sources/WinGameKit/Steam/SteamIntegration.swift`：

```swift
public class SteamIntegration {
    /// 在指定 Bottle 内安装 Windows 版 Steam
    /// 通过 Wine 运行 SteamSetup.exe
    public func installSteam(in bottle: Bottle) async throws

    /// 扫描 Bottle 内 Steam 的 libraryfolders.vdf
    /// 使用 VDFParser 解析 Valve KeyValue 格式（非标准格式，需自写解析器）
    /// VDF 格式示例: "key" { "subkey" "value" }
    public func detectInstalledGames(in bottle: Bottle) -> [SteamGame]

    /// 通过 wine + steam://rungameid/<appId> 启动游戏
    public func launchGame(_ appId: String, in bottle: Bottle) async throws

    /// Steam 安装包下载 URL
    static let steamInstallerURL = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
}

public struct SteamGame: Identifiable, Codable {
    public let appId: String
    public let name: String
    public let installDir: String
}
```

## 游戏启动流程

```
用户点击"启动游戏"
  │
  ├─ 1. 前置检查
  │     ├─ Rosetta 2 已安装？ → 否: 提示安装
  │     ├─ Wine 引擎已安装？ → 否: 跳转安装向导
  │     └─ 图形后端可用？ → 否: 降级到 DXMT/WineD3D
  │
  ├─ 2. 准备 Wine 环境
  │     ├─ WINEPREFIX=<bottle_path>
  │     ├─ WINEDEBUG=fixme-all
  │     ├─ 图形后端环境变量
  │     ├─ 用户自定义环境变量
  │     └─ DXVK DLL 替换（如启用）
  │
  ├─ 3. 启动 Wine 进程
  │     └─ Process: wine start /unix <exe_path> [args]
  │        → 返回 AsyncStream<ProcessOutput>
  │
  ├─ 4. 实时监控
  │     ├─ stdout/stderr → 日志文件 + UI 显示
  │     ├─ 进程状态监控（运行中/已退出）
  │     └─ 崩溃检测
  │
  └─ 5. 进程结束
        ├─ 正常退出 → 更新统计
        └─ 异常退出 → 显示最近日志 + 建议
```

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| Wine 未安装 | 自动跳转安装向导 |
| D3DMetal 未安装 | 弹窗引导安装 GPTK，提供降级选项（DXMT/WineD3D） |
| 游戏崩溃 | 保存完整日志，显示最后 20 行错误，建议切换图形后端 |
| Wine 版本不兼容 | 显示当前 Wine 版本，建议更新（MVP 不支持多版本共存） |
| Wine 进程卡死 | 菜单栏 Cmd+Shift+K 杀死所有 Wine 进程 |
| 磁盘空间不足 | 安装前检查剩余空间，提前警告 |
| 网络下载失败 | 重试机制 + 离线安装指引 |

## 测试策略

### 自动化测试

| 层级 | 测试内容 | 工具 | 环境 |
|------|---------|------|------|
| 单元测试 | PE 解析、VDF 解析、配置序列化、路径管理 | XCTest | CI + 本地 |
| 集成测试 | Wine 进程启动、Bottle CRUD | XCTest | 仅本地（需 Wine + Rosetta 2） |
| UI 测试 | 首次运行向导、添加游戏、启动 | XCUITest | 仅本地 |

注：集成测试和 UI 测试需要安装 Wine 和 Rosetta 2，标准 GitHub Actions runner 不支持，标注为本地测试。CI 只跑单元测试和编译检查。

### 运行测试

下载 1-2 个体积小的开源 Windows .exe 程序进行自动运行测试：

- **Notepad++** (~4MB) — 轻量级 Windows 应用，验证 Wine 基本功能
- **7-Zip** (~1.5MB) — 有 GUI 的小工具，验证窗口管理

测试流程：
1. 自动创建测试 Bottle
2. 下载测试 .exe 到 Bottle 的 drive_c
3. 通过 Wine 启动程序
4. 验证进程启动成功（进程存在 + 无崩溃日志）
5. 等待 5 秒后关闭进程
6. 清理测试 Bottle

## 技术约束

1. **D3DMetal 许可证**：不可内置分发，必须引导用户自行下载安装 GPTK
2. **Rosetta 2 必需**：Wine 为 x86 二进制，Apple Silicon 必须通过 Rosetta 运行
3. **macOS 最低版本**：macOS 13.0+（Ventura，GPTK 最低要求）
4. **反作弊不支持**：开源方案无法绕过 EAC/BattlEye 等反作弊系统
5. **GPL v3 约束**：Fork Bourbon 继承 GPL v3，所有修改必须开源
6. **非沙盒应用**：Wine 需要大量文件系统和进程权限，无法使用 App Sandbox，因此无法上架 Mac App Store
7. **分发方式**：通过 GitHub Release 发布 .dmg，用户需手动 `xattr -cr` 移除隔离属性（未进行 Apple 公证）

## 本地化策略

保留 Bourbon 现有的 Localizable.xcstrings 多语言文件。品牌重塑时更新所有包含 "Whisky"/"Bourbon" 的翻译 key。MVP 阶段不新增语言，但确保中英文翻译完整。

## 参考项目

- [Bourbon](https://github.com/leonewt0n/Bourbon) — 基础 fork 来源
- [Whisky](https://github.com/Whisky-App/Whisky) — 原始架构参考
- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) — 图形后端集成参考
- [DXMT](https://github.com/3Shain/dxmt) — 开源 Metal 翻译层
- [Gcenx/wine-on-mac](https://github.com/Gcenx/wine-on-mac) — macOS Wine 安装指南
- [Proton](https://github.com/ValveSoftware/Proton) — Linux 端架构参考
