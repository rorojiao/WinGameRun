//
//  WineInstaller.swift
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
import SemanticVersion
import os.log

public class WineInstaller {
    /// The WinGameRun application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.appBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    // MARK: - D3DMetal PE Stub 安装

    /// 将 D3DMetal PE stub DLL 安装到 Bottle 的 system32
    /// 来源：Wine tarball 内置的 Libraries/Wine/lib/wine/x86_64-windows/
    public static func installD3DMetalStubs(to bottleURL: URL) throws {
        let srcDir = libraryFolder
            .appending(path: "Wine/lib/wine/x86_64-windows")
        guard FileManager.default.fileExists(atPath: srcDir.path(percentEncoded: false)) else {
            return  // Wine 未安装，跳过
        }
        try installD3DMetalStubs(to: bottleURL, from: srcDir)
    }

    /// 从指定路径安装 D3DMetal PE stub DLL
    private static func installD3DMetalStubs(to bottleURL: URL, from srcDir: URL) throws {
        let sys32 = bottleURL.appending(path: "drive_c/windows/system32")
        let fm = FileManager.default

        for dll in ["d3d12.dll", "d3d11.dll", "dxgi.dll", "atidxx64.dll"] {
            let src = srcDir.appending(path: dll)
            let dst = sys32.appending(path: dll)
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
    }

    /// 检查 Bottle 是否已安装 D3DMetal PE stub
    public static func isD3DMetalStubInstalled(in bottleURL: URL) -> Bool {
        let sys32 = bottleURL.appending(path: "drive_c/windows/system32")
        let d3d11 = sys32.appending(path: "d3d11.dll")
        guard let size = try? FileManager.default.attributesOfItem(
            atPath: d3d11.path(percentEncoded: false)
        )[.size] as? Int else { return false }
        // D3DMetal PE stub < 200KB, wined3d 完整实现 > 3MB
        return size < 200_000
    }

    // MARK: - Bourbon Wine 检测

    public static func isWineInstalled() -> Bool {
        // 优先检查版本 plist，fallback 检查 wine 二进制是否存在
        if wineVersion() != nil { return true }
        return FileManager.default.fileExists(atPath: binFolder.appending(path: "wine").path(percentEncoded: false))
    }

    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try FileManager.default.removeItem(at: from)
            // Remove quarantine attribute from the installed files
            removeQuarantineAttribute()
        } catch {
            print("Failed to install Wine: \(error)")
        }
    }
    /// Removes the quarantine attribute from the WinGameRun application support directory
    private static func removeQuarantineAttribute() {
        let appSupportPath = "\(NSHomeDirectory())/Library/Application Support/com.wingamerun.app/"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", appSupportPath]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                print("Successfully removed quarantine attribute from WinGameRun directory")
            } else {
                print("Warning: Failed to remove quarantine attribute (exit code: \(process.terminationStatus))")
            }
        } catch {
            print("Warning: Could not run xattr command to remove quarantine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall Wine: \(error)")
        }
    }

    public static func shouldUpdateWine() async -> (Bool, SemanticVersion) {
        // swiftlint:disable:next line_length
        let versionPlistURL = "https://raw.githubusercontent.com/rorojiao/WinGameRun/refs/heads/main/WineVersion.plist"
        let localVersion = wineVersion()

        guard let remoteUrl = URL(string: versionPlistURL) else {
            return (false, SemanticVersion(0, 0, 0))
        }

        do {
            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [:]
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }

            let (data, _) = try await session.data(from: remoteUrl)
            let remoteInfo = try PropertyListDecoder().decode(WineVersion.self, from: data)

            if let localVersion = localVersion, localVersion < remoteInfo.version {
                return (true, remoteInfo.version)
            }
        } catch {
            Logger.wineKit.error("检查 Wine 更新失败: \(error)")
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func wineVersion() -> SemanticVersion? {
        // 兼容两种文件名：tarball 中原始名称和重命名后的名称
        let candidates = [
            libraryFolder.appending(path: "WineVersion").appendingPathExtension("plist"),
            libraryFolder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        ]

        for versionPlist in candidates {
            do {
                let data = try Data(contentsOf: versionPlist)
                let info = try PropertyListDecoder().decode(WineVersion.self, from: data)
                return info.version
            } catch {
                continue
            }
        }
        return nil
    }
}

struct WineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
