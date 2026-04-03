//
//  D3DMetal.swift
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

/// D3DMetal (GPTK) 安装检测
public enum D3DMetal {

    /// GPTK 可能的安装路径（按优先级排序）
    public static var searchPaths: [String] {
        [
            // App 内置（随 Wine tarball 一起安装）
            WineInstaller.libraryFolder
                .appending(path: "Wine/lib/external/D3DMetal.framework")
                .path(percentEncoded: false),
            WineInstaller.libraryFolder
                .appending(path: "external/D3DMetal.framework")
                .path(percentEncoded: false),
            // 系统级 GPTK 安装
            "/Library/Apple/usr/lib/d3d/",
            "/usr/local/lib/d3d/",
            "/usr/local/opt/game-porting-toolkit/"
        ]
    }

    /// 检测 D3DMetal 是否可用（包括 App 内置）
    public static func isAvailable() -> Bool {
        return installedPath() != nil
    }

    /// 检测系统级 GPTK 是否安装（D3D12 需要系统级 GPTK，
    /// App 内置的 D3DMetal.framework 仅支持 D3D11/DXMT，
    /// 因为 libd3dshared.dylib 内部需要系统路径存在才能初始化 D3D12）
    public static func isSystemGPTKInstalled() -> Bool {
        let fm = FileManager.default
        let systemPaths = [
            "/Library/Apple/usr/lib/d3d/",
            "/usr/local/lib/d3d/",
            "/usr/local/opt/game-porting-toolkit/",
            "/System/Library/Frameworks/D3DMetal.framework"
        ]
        return systemPaths.contains { fm.fileExists(atPath: $0) }
    }

    /// 返回找到的安装路径，未安装返回 nil
    public static func installedPath() -> String? {
        let fm = FileManager.default
        for path in searchPaths where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// 检测 GPTK 版本（优先从 Info.plist 读取，fallback 基于路径推断）
    public static func detectedVersion() -> String? {
        guard let path = installedPath() else { return nil }

        // 尝试从 Info.plist 读取真实版本号
        let plistPath = URL(fileURLWithPath: path)
            .appending(path: "Versions/A/Resources/Info.plist")
        if let data = try? Data(contentsOf: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let version = plist["CFBundleShortVersionString"] as? String {
            if path.contains("CrossOver") { return "\(version) (CrossOver)" }
            if path.contains("com.wingamerun.app") { return "\(version) (内置)" }
            return version
        }

        // fallback：基于路径推断
        if path.contains("com.wingamerun.app") { return "3.0 (内置)" }
        if path.contains("/Library/Apple/") { return "3.0" }
        if path == "/usr/local/lib/d3d/" { return "2.0+" }
        if path.contains("game-porting-toolkit") { return "1.x" }
        return nil
    }
}
