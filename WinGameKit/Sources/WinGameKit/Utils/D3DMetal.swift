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

/// D3DMetal (GPTK) 安装检测与自动安装
public enum D3DMetal {

    /// GPTK DMG 下载 URL（从 Bourbon Release 获取，内含 D3DMetal redist）
    public static let gptkDMGURL = URL(
        string: "https://github.com/leonewt0n/Bourbon/releases/download/Release/Evaluation_environment_for_Windows_games_3.0_beta_5.dmg"
    )!

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
            // 系统级安装
            "/Library/Apple/usr/lib/d3d/",
            "/usr/local/lib/d3d/",
            "/usr/local/opt/game-porting-toolkit/"
        ]
    }

    /// 检测 D3DMetal 是否可用
    public static func isAvailable() -> Bool {
        return installedPath() != nil
    }

    /// 返回找到的安装路径，未安装返回 nil
    public static func installedPath() -> String? {
        let fm = FileManager.default
        for path in searchPaths where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// 检测 GPTK 版本（基于路径推断）
    public static func detectedVersion() -> String? {
        guard let path = installedPath() else { return nil }
        if path.contains("com.wingamerun.app") { return "3.0 (内置)" }
        if path.contains("/Library/Apple/") { return "3.0" }
        if path == "/usr/local/lib/d3d/" { return "2.0+" }
        if path.contains("game-porting-toolkit") { return "1.x" }
        return nil
    }

    /// D3DMetal 在 App Libraries 中的安装目标路径
    public static var appInstallPath: URL {
        WineInstaller.libraryFolder.appending(path: "external")
    }

    /// 自动安装 GPTK：下载 DMG → 挂载 → 复制 redist → 卸载
    public static func autoInstall() async throws {
        // 如果已安装则跳过
        guard !isAvailable() else { return }

        let fm = FileManager.default

        // 下载 DMG
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let (dmgURL, _) = try await URLSession(configuration: config).download(from: gptkDMGURL)

        let localDMG = fm.temporaryDirectory.appending(path: "gptk.dmg")
        if fm.fileExists(atPath: localDMG.path(percentEncoded: false)) {
            try fm.removeItem(at: localDMG)
        }
        try fm.moveItem(at: dmgURL, to: localDMG)

        // 挂载 DMG
        let mountPoint = fm.temporaryDirectory.appending(path: "gptk_mount")
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", localDMG.path(percentEncoded: false),
                          "-nobrowse", "-mountpoint", mountPoint.path(percentEncoded: false)]
        try mount.run()
        mount.waitUntilExit()

        defer {
            // 卸载 DMG
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path(percentEncoded: false)]
            try? detach.run()
            detach.waitUntilExit()
            try? fm.removeItem(at: localDMG)
        }

        let redistLib = mountPoint.appending(path: "redist/lib")

        // 复制 external（D3DMetal.framework + libd3dshared.dylib）
        let srcExternal = redistLib.appending(path: "external")
        let dstExternal = WineInstaller.libraryFolder.appending(path: "external")
        if fm.fileExists(atPath: dstExternal.path(percentEncoded: false)) {
            try fm.removeItem(at: dstExternal)
        }
        try fm.copyItem(at: srcExternal, to: dstExternal)

        // 复制 Wine DLL（d3d10/d3d11/d3d12/dxgi 等）
        let wineLibDir = WineInstaller.libraryFolder.appending(path: "Wine/lib/wine")
        for subdir in ["x86_64-unix", "x86_64-windows"] {
            let src = redistLib.appending(path: "wine/\(subdir)")
            let dst = wineLibDir.appending(path: subdir)
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
            let contents = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
            for file in contents {
                let target = dst.appending(path: file.lastPathComponent)
                if fm.fileExists(atPath: target.path(percentEncoded: false)) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: file, to: target)
            }
        }
    }
}
