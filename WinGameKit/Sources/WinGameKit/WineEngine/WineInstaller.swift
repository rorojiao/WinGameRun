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

public class WineInstaller {
    /// The WinGameRun application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.appBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    // MARK: - CrossOver Wine 检测

    /// CrossOver.app 可能的安装路径
    private static let crossoverSearchPaths = [
        "/Applications/CrossOver.app",
        NSHomeDirectory() + "/Applications/CrossOver.app"
    ]

    /// 检测 CrossOver 是否已安装，返回 .app 路径
    public static func crossoverAppPath() -> String? {
        for path in crossoverSearchPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// CrossOver 是否已安装
    public static func isCrossoverInstalled() -> Bool {
        return crossoverAppPath() != nil
    }

    /// CrossOver 内部资源根路径
    public static func crossoverBasePath() -> URL? {
        guard let appPath = crossoverAppPath() else { return nil }
        return URL(fileURLWithPath: appPath)
            .appending(path: "Contents/SharedSupport/CrossOver")
    }

    /// CrossOver Wine 二进制文件夹（含 wineloader、wineserver）
    public static func crossoverBinFolder() -> URL? {
        return crossoverBasePath()?.appending(path: "CrossOver-Hosted Application")
    }

    /// CrossOver D3DMetal 组件路径（apple_gptk）
    public static func crossoverD3DMetalFolder() -> URL? {
        return crossoverBasePath()?.appending(path: "lib64/apple_gptk")
    }

    /// 将 CrossOver D3DMetal DLL 安装到指定 Bottle 的 system32
    public static func installCrossoverD3DMetal(to bottleURL: URL) throws {
        guard let d3dFolder = crossoverD3DMetalFolder() else { return }
        let sys32 = bottleURL.appending(path: "drive_c/windows/system32")
        let fm = FileManager.default

        for dll in ["d3d12.dll", "d3d11.dll", "dxgi.dll", "atidxx64.dll"] {
            let src = d3dFolder.appending(path: "wine/x86_64-windows/\(dll)")
            let dst = sys32.appending(path: dll)
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
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
        // MVP 阶段：使用 Bourbon 的版本信息，后续替换为 WinGameRun 自己的 Release
        let versionPlistURL = "https://raw.githubusercontent.com/leonewt0n/Bourbon/refs/heads/main/WhiskyWineVersion.plist"
        let localVersion = wineVersion()

        var remoteVersion: SemanticVersion?

        if let remoteUrl = URL(string: versionPlistURL) {
            remoteVersion = await withCheckedContinuation { continuation in
                let config = URLSessionConfiguration.ephemeral
                config.connectionProxyDictionary = [:]
                URLSession(configuration: config).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data = data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(WineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error = error {
                            print(error)
                        }
                    } catch {
                        print(error)
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
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
