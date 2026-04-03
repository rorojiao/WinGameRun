//
//  AppDelegate.swift
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
import SwiftUI
import WinGameKit

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasShownMoveToApplicationsAlert") private var hasShownMoveToApplicationsAlert = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after WinGameRun has been opened
            // so that the `onOpenURL` handler is actually called
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasShownMoveToApplicationsAlert && !AppDelegate.insideAppsFolder {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                NSApp.activate(ignoringOtherApps: true)
                self.showAlertOnFirstLaunch()
                self.hasShownMoveToApplicationsAlert = true
            }
        }

        // 清理上次会话遗留的孤儿 Wine 进程（app 崩溃/强制退出后残留）
        Task.detached(priority: .background) {
            AppDelegate.killOrphanedWineProcesses()
        }
    }

    /// 通过 lsof 查找所有加载了 Wine loader 的进程并强制终止
    /// 扫描 Application Support 下所有含 wingamerun 的目录，兼容 .backup 等变体
    static func killOrphanedWineProcesses() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        // 找出所有属于本 app 的 Wine loader（含 .backup 等历史残留目录）
        let appDirs = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
        let loaderPaths = appDirs
            .filter { $0.lastPathComponent.lowercased().contains("wingamerun") }
            .map { $0.appending(path: "Libraries/Wine/lib/wine/x86_64-unix/wine").path(percentEncoded: false) }
            .filter { fm.fileExists(atPath: $0) }

        guard !loaderPaths.isEmpty else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for loaderPath in loaderPaths {
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-F", "p", "-a", "-d", "txt", loaderPath]
            let pipe = Pipe()
            lsof.standardOutput = pipe
            lsof.standardError = Pipe()

            guard (try? lsof.run()) != nil else { continue }
            lsof.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.components(separatedBy: .newlines) where line.hasPrefix("p") {
                guard let pid = Int32(line.dropFirst()), pid != myPID else { continue }
                kill(pid, SIGKILL)
            }
        }

        // 第二阶段：清理 Wine loader 已删除但进程仍存活的 ghost 进程
        // 通过进程命令行特征（Windows 路径）精准匹配，不影响其他应用
        for pattern in ["system32", "start.exe /exec"] {
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-f", pattern]
            let pipe = Pipe()
            pgrep.standardOutput = pipe
            pgrep.standardError = Pipe()

            guard (try? pgrep.run()) != nil else { continue }
            pgrep.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.components(separatedBy: .newlines) {
                guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)), pid != myPID else { continue }
                kill(pid, SIGKILL)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 始终清理：wineserver -k 处理仍活跃的 prefix，killOrphanedWineProcesses 处理孤儿进程
        WinGameRunApp.killBottles()
        AppDelegate.killOrphanedWineProcesses()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let expectedUrl = URL(fileURLWithPath: "/Applications/WinGameRun.app")

    private static var insideAppsFolder: Bool {
        if let url = appUrl {
            return url.path.contains("Xcode") || url.path.contains(expectedUrl.path)
        }
        return false
    }

    @MainActor
    private func showAlertOnFirstLaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "showAlertOnFirstLaunch.messageText")
        alert.informativeText = String(localized: "showAlertOnFirstLaunch.informativeText")
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.moveToApplications"))
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.dontMove"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let appURL = Bundle.main.bundleURL

            do {
                _ = try FileManager.default.replaceItemAt(AppDelegate.expectedUrl, withItemAt: appURL)
                NSWorkspace.shared.open(AppDelegate.expectedUrl)
            } catch {
                print("Failed to move the app: \(error)")
            }
        }
    }
}
