//
//  Program+Extensions.swift
//  WinGameRun
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
import AppKit
import os.log

extension Program {
    public func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    func runInWine() {
        var arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()
        let gameFramework = settings.detectedFramework
            ?? GameTypeDetector.detect(programURL: url)
        let dllPolicy = settings.dllOverridePolicy

        // NW.js/Electron 游戏：自动修复 package.json
        // 移除 --in-process-gpu（与 wineserver 输入线程竞争 CPU 导致输入延迟）
        // 加入 --disable-gpu-sandbox（允许 GPU 子进程在 Wine 沙盒外启动）
        switch gameFramework {
        case .nwjs, .electron, .rpgMaker:
            patchNWJSPackageJson(at: url.deletingLastPathComponent())
        default:
            break
        }

        // NW.js/Electron 性能参数：用户设置 > 自动检测
        if let userSetting = settings.disableGPU, userSetting == false {
            // 用户手动选择启用 GPU — 不添加 --disable-gpu
        } else {
            // 自动或用户选择禁用：添加框架优化参数
            for arg in GameTypeDetector.performanceArgs(for: gameFramework) {
                if !arguments.contains(arg) {
                    arguments.append(arg)
                }
            }
        }

        // DXMT / D3DMetal 引擎 + auto 策略 → 启用崩溃自动恢复（native DLL 可能不兼容部分游戏）
        let useCrashRecovery = (bottle.settings.wineEngine == .dxmt
            || bottle.settings.wineEngine == .d3dmetal) && dllPolicy == .auto

        Task.detached(priority: .userInitiated) {
            do {
                if useCrashRecovery {
                    if let workingPolicy = try await CrashRecoveryManager.runWithRecovery(
                        program: self, args: arguments, framework: gameFramework
                    ) {
                        // 降级成功，保存可工作的配置
                        await MainActor.run {
                            self.settings.dllOverridePolicy = workingPolicy
                        }
                    }
                } else {
                    try await Wine.runProgram(
                        at: self.url, args: arguments, bottle: self.bottle,
                        environment: environment,
                        dllOverridePolicy: dllPolicy, gameFramework: gameFramework
                    )
                }
            } catch {
                await MainActor.run {
                    self.showRunError(message: error.localizedDescription)
                }
            }
        }
    }

    public func generateTerminalCommand() -> String {
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    public func runInTerminal() {
        // 转义 AppleScript 字符串中的特殊字符：反斜杠和双引号
        let wineCmd = generateTerminalCommand()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(wineCmd)"
        end tell
        """

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else { return }
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                await self.showRunError(message: String(describing: description))
            }
        }
    }

    /// 自动修复 NW.js/Electron 游戏的 package.json：
    /// 移除 --in-process-gpu（防止 GPU 线程与 Browser 主线程争 CPU，造成输入事件延迟）
    /// 添加 --disable-gpu-sandbox（确保独立 GPU 子进程能在 Wine 环境中正常启动）
    private func patchNWJSPackageJson(at directory: URL) {
        let pkgURL = directory.appending(path: "package.json")
        guard FileManager.default.fileExists(atPath: pkgURL.path(percentEncoded: false)),
              let data = try? Data(contentsOf: pkgURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chromiumArgs = json["chromium-args"] as? String else {
            return
        }

        // 检查是否需要修改（避免每次都写文件）
        let hasInProcessGPU = chromiumArgs.contains("--in-process-gpu")
        let hasGPUSandboxDisabled = chromiumArgs.contains("--disable-gpu-sandbox")
        guard hasInProcessGPU || !hasGPUSandboxDisabled else { return }

        var patched = chromiumArgs
        if hasInProcessGPU {
            patched = patched
                .replacingOccurrences(of: "--in-process-gpu", with: "")
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        if !hasGPUSandboxDisabled {
            patched = "--disable-gpu-sandbox " + patched
        }

        json["chromium-args"] = patched
        guard let newData = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? newData.write(to: pkgURL, options: .atomic)
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
