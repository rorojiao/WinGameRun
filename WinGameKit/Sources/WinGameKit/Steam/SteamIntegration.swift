//
//  SteamIntegration.swift
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
import os.log

/// Steam 集成：在 Wine Bottle 内安装、检测和启动 Steam 游戏
public final class SteamIntegration: Sendable {

    /// Steam 安装包下载 URL
    public static let steamInstallerURL = URL(
        string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
    )!

    public init() {}

    // MARK: - Steam 安装

    /// 检查 Bottle 内是否已安装 Steam
    public func isSteamInstalled(in bottle: Bottle) -> Bool {
        let steamExe = steamExecutablePath(in: bottle)
        return FileManager.default.fileExists(atPath: steamExe.path(percentEncoded: false))
    }

    /// 在指定 Bottle 内安装 Windows 版 Steam
    public func installSteam(in bottle: Bottle) async throws {
        // 下载 SteamSetup.exe 到 Bottle 的 drive_c
        let driveC = bottle.url.appending(path: "drive_c")
        let installerDest = driveC.appending(path: "SteamSetup.exe")

        if !FileManager.default.fileExists(atPath: installerDest.path(percentEncoded: false)) {
            let config = URLSessionConfiguration.default
            config.connectionProxyDictionary = [:]
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }
            let (tempURL, response) = try await session.download(from: Self.steamInstallerURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: tempURL, to: installerDest)
        }

        // 通过 Wine 运行安装程序
        try await Wine.runProgram(at: installerDest, bottle: bottle)
    }

    // MARK: - 游戏检测

    /// 扫描 Bottle 内 Steam 已安装的游戏
    public func detectInstalledGames(in bottle: Bottle) -> [SteamGame] {
        var games: [SteamGame] = []

        for libraryFolder in findLibraryFolders(in: bottle) {
            let appsDir = libraryFolder.appending(path: "steamapps")
            games.append(contentsOf: scanAppManifests(in: appsDir))
        }

        return games
    }

    // MARK: - 游戏启动

    /// 通过 Steam 协议 URL 启动游戏
    public func launchGame(_ appId: String, in bottle: Bottle) async throws {
        let steamExe = steamExecutablePath(in: bottle)
        try await Wine.runProgram(
            at: steamExe,
            args: ["-applaunch", appId],
            bottle: bottle
        )
    }

    // MARK: - 内部方法

    /// Steam 可执行文件路径
    private func steamExecutablePath(in bottle: Bottle) -> URL {
        bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")
            .appending(path: "steam.exe")
    }

    /// 查找所有 Steam Library 目录
    private func findLibraryFolders(in bottle: Bottle) -> [URL] {
        let steamAppsDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: "Steam")

        let libraryFoldersVDF = steamAppsDir
            .appending(path: "steamapps")
            .appending(path: "libraryfolders.vdf")

        guard FileManager.default.fileExists(atPath: libraryFoldersVDF.path(percentEncoded: false)) else {
            return [steamAppsDir]
        }

        do {
            let node = try VDFParser.parseFile(at: libraryFoldersVDF)
            guard let root = node.dictionaryValue else { return [steamAppsDir] }

            // libraryfolders.vdf 顶层 key 是 "libraryfolders" 或直接是数字索引
            let folders = root["libraryfolders"]?.dictionaryValue ?? root
            var paths: [URL] = []

            for (_, value) in folders {
                if let entry = value.dictionaryValue, let path = entry["path"]?.stringValue {
                    paths.append(URL(fileURLWithPath: path))
                }
            }

            return paths.isEmpty ? [steamAppsDir] : paths
        } catch {
            Logger.wineKit.error("解析 libraryfolders.vdf 失败: \(error)")
            return [steamAppsDir]
        }
    }

    /// 扫描 steamapps 目录下的 appmanifest_*.acf 文件
    private func scanAppManifests(in steamAppsDir: URL) -> [SteamGame] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: steamAppsDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.compactMap { url -> SteamGame? in
            guard url.lastPathComponent.hasPrefix("appmanifest_"),
                  url.pathExtension == "acf" else {
                return nil
            }

            guard let node = try? VDFParser.parseFile(at: url),
                  let appState = node["AppState"]?.dictionaryValue ?? node.dictionaryValue,
                  let appId = appState["appid"]?.stringValue,
                  let name = appState["name"]?.stringValue,
                  let installDir = appState["installdir"]?.stringValue else {
                return nil
            }

            return SteamGame(appId: appId, name: name, installDir: installDir)
        }
    }
}
