# WinGameRun

在 Apple Silicon Mac 上运行 Windows 游戏的启动器。

Fork 自 [Bourbon](https://github.com/leonewt0n/Bourbon)（[Whisky](https://github.com/Whisky-App/Whisky) 的活跃分支），采用三层翻译栈：

```
Windows 游戏 (.exe)
    │
    ├─ Rosetta 2   — x86_64 → ARM64（CPU 指令翻译）
    ├─ Wine        — Windows API → macOS POSIX（系统调用翻译）
    └─ D3DMetal    — DirectX → Metal（图形 API 翻译）
```

---

## 系统要求

| 条件 | 要求 |
|------|------|
| 芯片 | Apple Silicon（M1 / M2 / M3 / M4） |
| 系统 | macOS 13.0 Ventura 或更高 |
| Rosetta 2 | 首次启动时自动引导安装 |

> 不支持 Intel Mac。Wine 为 x86 二进制，必须通过 Rosetta 2 在 Apple Silicon 上运行。

---

## 安装

1. 前往 [Releases](https://github.com/rorojiao/WinGameRun/releases) 下载最新 `.dmg`
2. 将 `WinGameRun.app` 拖入 `/Applications`
3. 首次打开时系统提示"无法验证开发者"——在**系统设置 → 隐私与安全性**中点击"仍要打开"

> 本应用未进行 Apple 公证（非沙盒应用，Wine 需要广泛文件系统权限），无法上架 Mac App Store，通过 GitHub Release 分发。

---

## 首次启动向导

首次启动会依次引导完成以下步骤，全程自动化：

### 第一步：Rosetta 2 检测

若未安装 Rosetta 2，应用跳转说明页。也可手动在终端执行：

```bash
softwareupdate --install-rosetta --agree-to-license
```

### 第二步：Wine 引擎下载与安装

- 自动下载预编译 Wine（约 444 MB）
- 解压安装至 `~/Library/Application Support/com.wingamerun.app/Libraries/`
- 自动移除隔离属性（`xattr -dr com.apple.quarantine`），无需手动操作

### 第三步：D3DMetal / GPTK 引导

D3DMetal 是 Apple 提供的 DirectX → Metal 翻译层，可显著提升游戏性能。

- 应用首先检测 Wine tarball 内置路径（`Libraries/Wine/lib/external/D3DMetal.framework`）
- 若已内置则自动跳过，无需任何手动操作
- 若未检测到，提供两个选项：
  - **自动安装**：从网络下载 GPTK 包并自动提取（约 23 MB）
  - **跳过**：降级使用 DXMT（开源，DX10/11，性能略低）

---

## 图形后端

| 后端 | 翻译路径 | DX 支持 | 状态 |
|------|---------|---------|------|
| D3DMetal | DirectX → Metal（直接） | DX11, DX12 | 推荐，首选 |
| DXMT | DirectX → Metal | DX10, DX11 | 备选（开源） |
| DXVK | DirectX → Vulkan → MoltenVK → Metal | DX10, DX11 | 备选（开源） |

---

## 基本使用

### 创建 Bottle

**Bottle** 是独立的 Windows 运行环境（Wine Prefix），建议每款游戏使用独立 Bottle。

1. 主界面左下角点击 **"+"**
2. 输入名称，选择存储位置（默认 `~/WinGameRun/Bottles/`）
3. 点击**创建**

### 安装 Windows 程序

在 Bottle 详情页：

1. 点击工具栏**文件夹图标**，或将 `.exe` 文件直接拖入窗口
2. Wine 运行安装程序，按 Windows 正常安装流程操作
3. 安装完成后程序出现在**程序列表**中

### 启动程序

- 在**程序列表**中双击程序图标
- 已固定的程序可在 Bottle 首页大图标直接启动

### 固定常用程序

程序列表 → 右键 → **固定到首页**

---

## Steam 集成

### 安装 Windows Steam

Bottle 详情页 → **配置** → **安装 Steam**

Steam 通过 `https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe` 下载安装。

### 检测已安装游戏

安装 Steam 后，应用自动解析 `libraryfolders.vdf`（Valve KeyValue 格式），列出已安装游戏。

### 启动 Steam 游戏

支持通过 `steam://rungameid/<AppID>` 协议直接启动，无需打开 Steam 界面：

```
steam://rungameid/570    # Dota 2
steam://rungameid/440    # Team Fortress 2
```

---

## Bottle 配置

Bottle 详情页 → **齿轮图标**：

| 选项 | 说明 |
|------|------|
| Windows 版本 | 模拟的 Windows 版本（默认 Windows 10） |
| D3DMetal / DXMT / DXVK | 图形后端选择 |
| 增强同步（MSync/ESync） | 减少 CPU 等待，提升帧数稳定性 |
| 高分辨率模式 | HiDPI / Retina 支持 |
| 自定义环境变量 | 高级 Wine 环境变量配置 |

---

## Winetricks

Bottle 详情页 → **Winetricks**，安装常用 Windows 运行库：

| 组件 | 用途 |
|------|------|
| `vcrun2019` | Visual C++ 2019（大多数游戏需要） |
| `dotnet48` | .NET Framework 4.8 |
| `d3dx9` | DirectX 9 组件 |
| `xna40` | XNA Framework 4.0（独立游戏常用） |

---

## RuntimeAIO

一键安装游戏常用运行库全家桶（Visual C++ 全版本 + DirectX + .NET）。

Bottle 配置页 → **安装 RuntimeAIO**

---

## 游戏启动流程

```
用户点击启动
  │
  ├─ 前置检查
  │     ├─ Rosetta 2 已安装？ → 否: 提示安装
  │     ├─ Wine 引擎已安装？ → 否: 跳转安装向导
  │     └─ 图形后端可用？ → 否: 降级到 DXMT
  │
  ├─ 准备 Wine 环境
  │     ├─ WINEPREFIX=<bottle_path>
  │     ├─ WINEDEBUG=fixme-all
  │     ├─ 图形后端环境变量
  │     └─ 用户自定义环境变量
  │
  ├─ 启动 Wine 进程
  │     └─ wine start /unix <exe_path> [args]
  │
  └─ 运行监控
        ├─ stdout/stderr → 日志文件
        └─ 异常退出 → 显示错误日志 + 建议
```

---

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| Wine 未安装 | 自动跳转安装向导 |
| D3DMetal 未安装 | 自动安装或降级到 DXMT |
| 游戏崩溃 | 保存完整日志，显示最近错误，建议切换图形后端 |
| 反作弊（EAC/BattlEye） | 不支持，不可绕过 |
| Wine 进程卡死 | Cmd+Shift+K 杀死所有 Wine 进程 |

---

## 命令行工具

**设置 → 安装命令行工具** 安装后：

```bash
# 列出所有 Bottle
wingamerun list

# 在指定 Bottle 中运行程序
wingamerun run --bottle "MyBottle" /path/to/game.exe
```

---

## 自动更新

使用 [Sparkle](https://github.com/sparkle-project/Sparkle) 框架，启动时自动检查更新。

- **设置 → 检查应用更新** — 手动检查 WinGameRun 新版本
- **设置 → 检查 Wine 更新** — 独立管理 Wine 引擎版本

---

## 文件位置

```
~/Library/Application Support/com.wingamerun.app/
  Libraries/
    Wine/bin/          # Wine 引擎二进制
    Wine/lib/external/ # D3DMetal.framework（若 tarball 内置）
    WhiskyWineVersion.plist  # Wine 版本信息

~/WinGameRun/Bottles/
  <BottleName>/
    drive_c/           # Windows 文件系统
    Metadata.plist     # Bottle 配置

~/Library/Preferences/com.wingamerun.app.plist  # 应用设置（含 Bottle 路径列表）
~/Library/Logs/com.wingamerun.app/              # Wine 进程日志
```

---

## 卸载

删除应用：

```bash
rm -rf /Applications/WinGameRun.app
```

删除所有数据（可选）：

```bash
rm -rf ~/Library/Application\ Support/com.wingamerun.app
rm -rf ~/WinGameRun/Bottles
rm ~/Library/Preferences/com.wingamerun.app.plist
rm /usr/local/bin/wingamerun  # 若安装了 CLI
```

---

## 开发

### 构建

```bash
git clone https://github.com/rorojiao/WinGameRun.git
cd WinGameRun
open WinGameRun.xcodeproj
```

> Sparkle 二进制需手动放置，详见 [CLAUDE.md](./CLAUDE.md)。

### 运行单元测试（CI）

```bash
xcodebuild test \
  -project WinGameRun.xcodeproj \
  -scheme WinGameRun \
  -testPlan UnitTests
```

测试覆盖：VDF 解析器（12 项）、D3DMetal 路径检测（5 项）、SteamGame 模型（3 项），共 20 项。

### WinGameKit SPM 包

```bash
cd WinGameKit
swift build
swift test
```

### 架构

```
WinGameRun/          SwiftUI 主应用（Views + MVVM）
WinGameKit/          核心库 SPM Package
  ├── Bottle/        Wine 前缀数据模型
  ├── Wine/          Wine 进程启动和管理
  ├── WineEngine/    Wine 引擎下载安装
  ├── Steam/         Steam 集成 + VDF 解析器
  ├── Utils/         D3DMetal 检测、Rosetta 2 检测
  └── PE/            Windows PE 文件解析
WinGameCmd/          CLI 工具
WinGameThumbnail/    Finder 缩略图扩展
```

---

## 已知限制

- **反作弊**：EAC、BattlEye 等反作弊系统不支持
- **DX12 Ultimate**：部分高端 DX12 特性（光追等）不可用
- **App Store**：非沙盒应用，无法上架
- **Intel Mac**：不支持

---

## 许可证

GPL v3 — Fork 自 Bourbon / Whisky，所有修改必须开源，需保留原始版权声明。

详见 [LICENSE](./LICENSE)。

---

## 参考项目

- [Bourbon](https://github.com/leonewt0n/Bourbon) — 基础 fork 来源
- [Whisky](https://github.com/Whisky-App/Whisky) — 原始架构
- [DXMT](https://github.com/3Shain/dxmt) — 开源 Metal 翻译层
- [Gcenx/wine-on-mac](https://github.com/Gcenx/wine-on-mac) — macOS Wine 参考
