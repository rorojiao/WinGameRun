//
//  Wine.swift
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
import os.log

public class Wine {
    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WineInstaller.libraryFolder.appending(path: "DXVK")
    /// Bourbon Wine 二进制路径（默认）
    public static let wineBinary: URL = WineInstaller.binFolder.appending(path: "wine")
    /// Bourbon wineserver 路径（默认）
    private static let wineserverBinary: URL = WineInstaller.binFolder.appending(path: "wineserver")

    /// Wine 二进制路径 — 统一使用 Bourbon Wine（D3DMetal 通过 DLL override 控制）
    public static func wineBinaryURL(
        for engine: WineEngine, gameFramework: GameFramework? = nil,
        dllOverridePolicy: DLLOverridePolicy = .auto
    ) -> URL {
        return wineBinary
    }

    /// wineserver 二进制路径 — 统一使用 Bourbon
    private static func wineserverBinaryURL(for engine: WineEngine) -> URL {
        return wineserverBinary
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?, engine: WineEngine = .d3dmetal,
        gameFramework: GameFramework? = nil, dllOverridePolicy: DLLOverridePolicy = .auto
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: wineBinaryURL(
                for: engine, gameFramework: gameFramework,
                dllOverridePolicy: dllOverridePolicy
            ),
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?, engine: WineEngine = .d3dmetal
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: wineserverBinaryURL(for: engine),
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:],
        dllOverridePolicy: DLLOverridePolicy = .auto, gameFramework: GameFramework? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(
                for: bottle, environment: environment,
                dllOverridePolicy: dllOverridePolicy, gameFramework: gameFramework
            ),
            fileHandle: fileHandle,
            engine: bottle.settings.wineEngine,
            gameFramework: gameFramework,
            dllOverridePolicy: dllOverridePolicy
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle,
            engine: bottle.settings.wineEngine
        )
    }

    /// 游戏运行结果（用于崩溃检测）
    public struct ProgramRunResult {
        public let startTime: Date
        public let endTime: Date
        public let terminationStatus: Int32
    }

    /// Execute a `wine start /wait /unix {url}` command returning the output result
    /// /wait 确保等待游戏进程真正退出，退出后自动清理该 Bottle 的 wineserver
    @discardableResult
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:],
        dllOverridePolicy: DLLOverridePolicy = .auto, gameFramework: GameFramework? = nil
    ) async throws -> ProgramRunResult {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        let startTime = Date()
        var terminationStatus: Int32 = 0

        for await output in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/wait", "/unix", url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: environment,
            dllOverridePolicy: dllOverridePolicy, gameFramework: gameFramework
        ) {
            if case .terminated(let process) = output {
                terminationStatus = process.terminationStatus
            }
        }

        // 游戏退出后，wineserver -w 会因 winedevice.exe/services.exe 等系统服务永久阻塞。
        // 改为：等待 2 秒让游戏自身 cleanup 完成，然后直接 wineserver -k 终止整个 prefix。
        try? await Task.sleep(for: .seconds(2))
        try? await Self.runWineserver(["-k"], bottle: bottle)

        return ProgramRunResult(
            startTime: startTime, endTime: Date(),
            terminationStatus: terminationStatus
        )
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let binary = wineBinaryURL(for: bottle.settings.wineEngine)
        let escapedArgs = args.isEmpty ? "" : " " + shellEscape(args)
        var wineCmd = "\(binary.esc) start /wait /unix \(url.esc)\(escapedArgs)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            let escaped = Self.shellEscape(environment.value)
            wineCmd = "\(environment.key)=\(escaped) " + wineCmd
        }

        return wineCmd
    }

    /// 对 shell 字符串使用单引号包裹，防止特殊字符注入
    private static func shellEscape(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        var cmd = """
        export PATH=\"\(WineInstaller.binFolder.path):$PATH\"
        export WINE=\"wine\"
        alias wine=\"wine\"
        alias winecfg=\"wine winecfg\"
        alias msiexec=\"wine msiexec\"
        alias regedit=\"wine regedit\"
        alias regsvr32=\"wine regsvr32\"
        alias wineboot=\"wine wineboot\"
        alias wineconsole=\"wine wineconsole\"
        alias winedbg=\"wine winedbg\"
        alias winefile=\"wine winefile\"
        alias winepath=\"wine winepath\"
        """

        let env = constructWineEnvironment(for: bottle)
        for environment in env {
            let escaped = Self.shellEscape(environment.value)
            cmd += "\nexport \(environment.key)=\(escaped)"
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        var environment = environment
        let engine = bottle?.settings.wineEngine ?? .d3dmetal

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(
            args: args, environment: environment, fileHandle: fileHandle, engine: engine
        ) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) {
        Task.detached(priority: .userInitiated) {
            do {
                try await runWineserver(["-k"], bottle: bottle)
            } catch {
                Logger.wineKit.error("终止 Bottle 失败: \(error)")
            }
        }
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// 从当前进程继承的必要环境变量
    /// Process.environment 完全替换环境，不设置这些会导致 Wine/游戏闪退
    private static var inheritedEnvironment: [String: String] {
        var env: [String: String] = [:]
        // 基础系统变量（缺少会导致闪退）
        for key in ["HOME", "USER", "PATH", "TMPDIR", "LANG"] {
            if let val = ProcessInfo.processInfo.environment[key] {
                env[key] = val
            }
        }
        // X11/显示相关（部分游戏需要）
        env["DISPLAY"] = ProcessInfo.processInfo.environment["DISPLAY"] ?? ":0"
        if let xdg = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            env["XDG_RUNTIME_DIR"] = xdg
        }
        return env
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:],
        dllOverridePolicy: DLLOverridePolicy = .auto, gameFramework: GameFramework? = nil
    ) -> [String: String] {
        var result = inheritedEnvironment
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "fixme-all"
        result["GST_DEBUG"] = "1"

        // D3DMetal 自举加载：DYLD_FRAMEWORK_PATH 指向 Wine 内置 D3DMetal.framework 目录。
        // D3DMetal.framework 依赖 /System/Library/Frameworks/D3DMetal.framework（GPTK 系统安装路径），
        // 但该路径在未安装 GPTK 时不存在。通过 DYLD_FRAMEWORK_PATH 让 dyld 优先在此目录搜索
        // D3DMetal.framework，自举时发现框架已加载直接复用，与 CrossOver 的做法完全一致。
        let externalDir = WineInstaller.libraryFolder
            .appending(path: "Wine/lib/external")
            .path(percentEncoded: false)
        let existingFrameworkPath = result["DYLD_FRAMEWORK_PATH"] ?? ""
        result["DYLD_FRAMEWORK_PATH"] = existingFrameworkPath.isEmpty
            ? externalDir
            : externalDir + ":" + existingFrameworkPath

        bottle.settings.environmentVariables(
            wineEnv: &result,
            dllOverridePolicy: dllOverridePolicy,
            gameFramework: gameFramework
        )
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result = inheritedEnvironment
        result["WINEPREFIX"] = bottle.url.path
        result["WINEDEBUG"] = "fixme-all"
        result["GST_DEBUG"] = "1"
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

enum WineInterfaceError: Error {
    case invalidResponse
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.appBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponse
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["regedit"], bottle: bottle)
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    public static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }

    /// 将 macOS 系统 CJK 字体复制到 Bottle，并注册注册表项，修复中文乱码
    public static func installCJKFonts(bottle: Bottle) async throws {
        let winFontsDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "windows")
            .appending(path: "Fonts")

        try FileManager.default.createDirectory(at: winFontsDir, withIntermediateDirectories: true)

        // macOS 系统自带 CJK 字体候选列表（源路径 → 目标文件名）
        let candidates: [(String, String)] = [
            ("/System/Library/Fonts/STHeiti Light.ttc", "STHeitiSCLight.ttc"),
            ("/System/Library/Fonts/STHeiti Medium.ttc", "STHeitiSCMedium.ttc"),
            ("/Library/Fonts/Arial Unicode.ttf", "ArialUnicode.ttf"),
            ("/System/Library/Fonts/Supplemental/Songti.ttc", "Songti.ttc")
        ]

        let fm = FileManager.default
        var installed: [(fileName: String, displayName: String)] = []
        for (src, dest) in candidates {
            guard fm.fileExists(atPath: src) else { continue }
            let destURL = winFontsDir.appending(path: dest)
            if fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: URL(fileURLWithPath: src), to: destURL)
            let displayName = URL(fileURLWithPath: dest).deletingPathExtension().lastPathComponent
            installed.append((fileName: dest, displayName: displayName))
        }

        guard !installed.isEmpty else { return }

        // 注册字体到 HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts
        let fontsKey = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts"#
        for font in installed {
            try await addRegistryKey(
                bottle: bottle, key: fontsKey,
                name: "\(font.displayName) (TrueType)",
                data: font.fileName, type: .string
            )
        }

        // 安装 Tahoma CJK 替代：将 STHeitiSCLight 复制为 tahoma.ttf
        // winecfg 的 DPI 预览用 CreateFont("Tahoma") 直接渲染，不走字体替换表
        // 只有在字体目录里存在真正的 tahoma.ttf 文件才能修复方块问题
        if let srcHeiti = installed.first(where: { $0.fileName == "STHeitiSCLight.ttc" }) {
            let srcURL = winFontsDir.appending(path: srcHeiti.fileName)
            let tahomaURL = winFontsDir.appending(path: "tahoma.ttf")
            if fm.fileExists(atPath: tahomaURL.path(percentEncoded: false)) {
                try fm.removeItem(at: tahomaURL)
            }
            try fm.copyItem(at: srcURL, to: tahomaURL)
            try await addRegistryKey(
                bottle: bottle, key: fontsKey,
                name: "Tahoma (TrueType)",
                data: "tahoma.ttf", type: .string
            )
        }

        // 字体替换：只在 STHeitiSCLight 成功安装时才写入 FontSubstitutes
        // 目标必须是已安装的字体，否则替换无效
        guard let primaryFont = installed.first(where: { $0.fileName == "STHeitiSCLight.ttc" }) else { return }
        let substKey = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"#
        for fallback in ["MS Shell Dlg", "MS Shell Dlg 2", "MS UI Gothic"] {
            try await addRegistryKey(
                bottle: bottle, key: substKey,
                name: fallback, data: primaryFont.displayName, type: .string
            )
        }
    }
}
