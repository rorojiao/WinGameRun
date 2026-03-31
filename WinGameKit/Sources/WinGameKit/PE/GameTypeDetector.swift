//
//  GameTypeDetector.swift
//  WinGameKit
//
//  This file is part of WinGameRun.
//
//  WinGameRun is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  WinGameRun is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with WinGameRun.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

/// 检测到的游戏运行时框架
public enum GameFramework: String, Codable, Equatable {
    case nwjs       // NW.js / Chromium（ANGLE 渲染器，与 native D3D override 不兼容）
    case electron   // Electron（也基于 Chromium）
    case rpgMaker   // RPG Maker MV/MZ（基于 NW.js）
    case native     // 标准 Windows 游戏
    case unknown    // 无法判断

    /// 用于 UI 显示的名称
    public var displayName: String {
        switch self {
        case .nwjs: return "NW.js"
        case .electron: return "Electron"
        case .rpgMaker: return "RPG Maker"
        case .native: return "Native"
        case .unknown: return "Unknown"
        }
    }
}

/// DLL Override 策略（每个程序可单独设置）
public enum DLLOverridePolicy: String, Codable, CaseIterable, Equatable {
    case auto          // 根据 GameTypeDetector 自动决定
    case forceNative   // 强制使用 native D3D（CrossOver D3DMetal 模式）
    case forceBuiltin  // 强制使用 Wine 内置 d3d（兼容模式）

    public func pretty() -> String {
        switch self {
        case .auto: return String(localized: "program.dllPolicy.auto")
        case .forceNative: return String(localized: "program.dllPolicy.forceNative")
        case .forceBuiltin: return String(localized: "program.dllPolicy.forceBuiltin")
        }
    }
}

/// 游戏类型检测器：通过分析游戏目录中的文件特征判断运行时框架
public enum GameTypeDetector {

    /// 通过游戏目录文件特征检测框架类型
    public static func detect(programURL: URL) -> GameFramework {
        let dir = programURL.deletingLastPathComponent()
        let fm = FileManager.default

        // NW.js 特征文件（任一存在即确认）
        let nwjsIndicators = ["nw.dll", "nw_elf.dll", "node.dll"]
        for indicator in nwjsIndicators {
            if fm.fileExists(atPath: dir.appending(path: indicator).path(percentEncoded: false)) {
                // 进一步判断是否为 RPG Maker
                if isRPGMaker(directory: dir) {
                    return .rpgMaker
                }
                return .nwjs
            }
        }

        // 弱 NW.js 特征：chrome_elf.dll + package.json 同时存在
        let hasChromeElf = fm.fileExists(
            atPath: dir.appending(path: "chrome_elf.dll").path(percentEncoded: false))
        let hasPackageJson = fm.fileExists(
            atPath: dir.appending(path: "package.json").path(percentEncoded: false))
        if hasChromeElf && hasPackageJson {
            return .nwjs
        }

        // Electron 特征
        if isElectron(directory: dir) {
            return .electron
        }

        // 无法检测到特殊框架 → 视为原生 Windows 游戏
        return .native
    }

    /// 该框架是否与 CrossOver 的 native D3D DLL override (d3d11,d3d12,dxgi=n,b) 不兼容
    /// NW.js/Electron/RPG Maker 均基于 Chromium，其 ANGLE 层与 D3DMetal 的 native d3d11.dll 冲突
    public static func isIncompatibleWithNativeD3D(_ framework: GameFramework) -> Bool {
        switch framework {
        case .nwjs, .electron, .rpgMaker:
            return true
        case .native, .unknown:
            return false
        }
    }

    /// 返回针对该框架的性能优化启动参数
    /// NW.js/Electron 在 Wine 下 GPU 渲染管线（ANGLE→D3D→Wine→Metal）非常慢，
    /// --disable-gpu 跳过 ANGLE 直接用软件渲染，CPU 降低约 50%
    public static func performanceArgs(for framework: GameFramework) -> [String] {
        switch framework {
        case .nwjs, .electron, .rpgMaker:
            return ["--disable-gpu"]
        case .native, .unknown:
            return []
        }
    }

    // MARK: - 内部检测方法

    /// RPG Maker MV/MZ 检测：基于 NW.js + 特有目录结构
    private static func isRPGMaker(directory: URL) -> Bool {
        let fm = FileManager.default
        // RPG Maker MV/MZ 特征：www/js/ 或 www/data/System.json
        let wwwDir = directory.appending(path: "www")
        if fm.fileExists(atPath: wwwDir.appending(path: "js").path(percentEncoded: false)) {
            return true
        }
        if fm.fileExists(atPath: wwwDir.appending(path: "data/System.json").path(percentEncoded: false)) {
            return true
        }
        return false
    }

    /// Electron 检测
    private static func isElectron(directory: URL) -> Bool {
        let fm = FileManager.default
        // Electron 特征文件
        let electronIndicators = [
            "resources/electron.asar",
            "resources/app.asar",
            "electron.exe"
        ]
        for indicator in electronIndicators {
            if fm.fileExists(atPath: directory.appending(path: indicator).path(percentEncoded: false)) {
                return true
            }
        }
        return false
    }
}
