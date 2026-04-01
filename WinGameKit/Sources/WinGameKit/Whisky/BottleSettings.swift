//
//  BottleSettings.swift
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

public struct PinnedProgram: Codable, Hashable, Equatable {
    public var name: String
    public var url: URL?
    public var removable: Bool

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        do {
            let volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume
            self.removable = try !(volume?.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal ?? false)
        } catch {
            self.removable = false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false
    }
}

public struct BottleInfo: Codable, Equatable {
    var name: String = "Bottle"
    var pins: [PinnedProgram] = []
    var blocklist: [URL] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
    }
}

public enum WinVersion: String, CaseIterable, Codable, Sendable {
    case winXP = "winxp64"
    case win7 = "win7"
    case win8 = "win8"
    case win81 = "win81"
    case win10 = "win10"
    case win11 = "win11"

    public func pretty() -> String {
        switch self {
        case .winXP:
            return "Windows XP"
        case .win7:
            return "Windows 7"
        case .win8:
            return "Windows 8"
        case .win81:
            return "Windows 8.1"
        case .win10:
            return "Windows 10"
        case .win11:
            return "Windows 11"
        }
    }
}

public enum EnhancedSync: Codable, Equatable {
    case none, esync, msync
}

/// 渲染引擎选择（决定 DirectX 翻译路径）
public enum WineEngine: String, CaseIterable, Codable {
    case d3dmetal   // D3DMetal: DX→D3DMetal→Metal（2层，最佳性能）
    case wined3d    // wined3d: DX→wined3d→MoltenVK→Metal（4层，兼容模式）
    case dxvk       // DXVK: DX11→DXVK→Vulkan→MoltenVK→Metal（4层，成熟稳定）

    // 向后兼容：bourbon → d3dmetal, crossover → d3dmetal
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "bourbon", "crossover":
            self = .d3dmetal
        default:
            self = WineEngine(rawValue: raw) ?? .d3dmetal
        }
    }

    public func pretty() -> String {
        switch self {
        case .d3dmetal:
            return "D3DMetal (DX11 + DX12)"
        case .wined3d:
            return "wined3d (兼容模式)"
        case .dxvk:
            return "DXVK (Vulkan)"
        }
    }
}

public struct BottleWineConfig: Codable, Equatable {
    static let defaultWineVersion = SemanticVersion(7, 7, 0)
    var wineVersion: SemanticVersion = Self.defaultWineVersion
    var windowsVersion: WinVersion = .win10
    var enhancedSync: EnhancedSync = .msync
    var avxEnabled: Bool = false
    var wineEngine: WineEngine = .d3dmetal

    public init() {}

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wineVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .wineVersion) ?? Self.defaultWineVersion
        self.windowsVersion = try container.decodeIfPresent(WinVersion.self, forKey: .windowsVersion) ?? .win10
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync) ?? .msync
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled) ?? false
        self.wineEngine = try container.decodeIfPresent(WineEngine.self, forKey: .wineEngine) ?? .d3dmetal
    }
    // swiftlint:enable line_length
}

public struct BottleMetalConfig: Codable, Equatable {
    var metalHud: Bool = false
    var metalTrace: Bool = false
    var dxrEnabled: Bool = true             // M3+ 默认开启光追
    var asyncCommit: Bool = true            // D3DM_ENABLE_ASYNC_COMMIT（异步GPU命令提交）
    var metalFX: Bool = true                // D3DM_ENABLE_METALFX（MetalFX超采样）
    var multithreaded: Bool = true          // D3DM_MULTITHREADED_INTERFACE_ENABLE（多线程D3D）
    var gpuSpoofEnabled: Bool = true        // GPU伪装开关
    var gpuSpoofVendor: String = "0x10de"   // NVIDIA
    var gpuSpoofDevice: String = "0x2684"   // RTX 4090
    var gpuSpoofName: String = "NVIDIA GeForce RTX 4090"

    public init() {}

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        self.metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        self.dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? true
        self.asyncCommit = try container.decodeIfPresent(Bool.self, forKey: .asyncCommit) ?? true
        self.metalFX = try container.decodeIfPresent(Bool.self, forKey: .metalFX) ?? true
        self.multithreaded = try container.decodeIfPresent(Bool.self, forKey: .multithreaded) ?? true
        self.gpuSpoofEnabled = try container.decodeIfPresent(Bool.self, forKey: .gpuSpoofEnabled) ?? true
        self.gpuSpoofVendor = try container.decodeIfPresent(String.self, forKey: .gpuSpoofVendor) ?? "0x10de"
        self.gpuSpoofDevice = try container.decodeIfPresent(String.self, forKey: .gpuSpoofDevice) ?? "0x2684"
        self.gpuSpoofName = try container.decodeIfPresent(String.self, forKey: .gpuSpoofName) ?? "NVIDIA GeForce RTX 4090"
    }
    // swiftlint:enable line_length
}

public enum DXVKHUD: Codable, Equatable {
    case full, partial, fps, off
}

public struct BottleDXVKConfig: Codable, Equatable {
    var dxvk: Bool = false
    var dxvkAsync: Bool = true
    var dxvkHud: DXVKHUD = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
    }
}

public struct BottleSettings: Codable, Equatable {
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    var fileVersion: SemanticVersion = Self.defaultFileVersion
    private var info: BottleInfo
    private var wineConfig: BottleWineConfig
    private var metalConfig: BottleMetalConfig
    private var dxvkConfig: BottleDXVKConfig

    public init() {
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.dxvkConfig = BottleDXVKConfig()
    }

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self.defaultFileVersion
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.dxvkConfig = try container.decodeIfPresent(BottleDXVKConfig.self, forKey: .dxvkConfig) ?? BottleDXVKConfig()
    }
    // swiftlint:enable line_length

    /// The name of this bottle
    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    /// The version of wine used by this bottle
    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The version of windows used by this bottle
    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The pinned programs on this bottle
    public var pins: [PinnedProgram] {
        get { return info.pins }
        set { info.pins = newValue }
    }

    /// The blocked applications on this bottle
    public var blocklist: [URL] {
        get { return info.blocklist }
        set { info.blocklist = newValue }
    }

    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    public var wineEngine: WineEngine {
        get { return wineConfig.wineEngine }
        set { wineConfig.wineEngine = newValue }
    }

    public var metalHud: Bool {
        get { return metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    public var metalTrace: Bool {
        get { return metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    public var dxrEnabled: Bool {
        get { return metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    public var asyncCommit: Bool {
        get { return metalConfig.asyncCommit }
        set { metalConfig.asyncCommit = newValue }
    }

    public var metalFX: Bool {
        get { return metalConfig.metalFX }
        set { metalConfig.metalFX = newValue }
    }

    public var multithreaded: Bool {
        get { return metalConfig.multithreaded }
        set { metalConfig.multithreaded = newValue }
    }

    public var gpuSpoofEnabled: Bool {
        get { return metalConfig.gpuSpoofEnabled }
        set { metalConfig.gpuSpoofEnabled = newValue }
    }

    public var gpuSpoofVendor: String {
        get { return metalConfig.gpuSpoofVendor }
        set { metalConfig.gpuSpoofVendor = newValue }
    }

    public var gpuSpoofDevice: String {
        get { return metalConfig.gpuSpoofDevice }
        set { metalConfig.gpuSpoofDevice = newValue }
    }

    public var gpuSpoofName: String {
        get { return metalConfig.gpuSpoofName }
        set { metalConfig.gpuSpoofName = newValue }
    }

    public var dxvk: Bool {
        get { return dxvkConfig.dxvk }
        set { dxvkConfig.dxvk = newValue }
    }

    public var dxvkAsync: Bool {
        get { return dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get {  return dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    @discardableResult
    public static func decode(from metadataURL: URL) throws -> BottleSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            // 文件不存在 → 创建默认配置并写入磁盘
            let settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(BottleSettings.self, from: data)

        guard settings.fileVersion == BottleSettings.defaultFileVersion else {
            Logger.wineKit.warning("Invalid file version `\(settings.fileVersion)`")
            settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        if settings.wineConfig.wineVersion != BottleWineConfig().wineVersion {
            Logger.wineKit.warning("Bottle has a different wine version `\(settings.wineConfig.wineVersion)`")
            settings.wineConfig.wineVersion = BottleWineConfig().wineVersion
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func environmentVariables(
        wineEnv: inout [String: String],
        dllOverridePolicy: DLLOverridePolicy = .auto,
        gameFramework: GameFramework? = nil
    ) {
        // DXVK 和 D3DMetal 是互斥的渲染方案，DXVK 优先
        if dxvk {
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
            switch dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }
            if dxvkAsync {
                wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
            }
            // DXVK 模式下跳过后续 D3DMetal DLL override，避免冲突
        }

        switch enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
            // D3DM detects ESYNC and changes behaviour accordingly
            // so we have to lie to it so that it doesn't break
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        }

        if metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
        }

        if metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }

        if avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }

        // MARK: - D3DMetal 性能优化（仅 D3DMetal 引擎 + 非 Chromium 游戏时生效）
        let isChromiumGame = GameTypeDetector.isIncompatibleWithNativeD3D(gameFramework ?? .unknown)

        if wineEngine == .d3dmetal && !isChromiumGame && !dxvk {
            if dxrEnabled {
                wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
            }
            if asyncCommit {
                wineEnv.updateValue("1", forKey: "D3DM_ENABLE_ASYNC_COMMIT")
            }
            if metalFX {
                wineEnv.updateValue("1", forKey: "D3DM_ENABLE_METALFX")
            }
            if multithreaded {
                wineEnv.updateValue("1", forKey: "D3DM_MULTITHREADED_INTERFACE_ENABLE")
            }
            // GPU 伪装（让游戏启用 NVIDIA 最优渲染路径）
            if gpuSpoofEnabled {
                wineEnv.updateValue(gpuSpoofVendor, forKey: "D3DM_VENDOR_ID")
                wineEnv.updateValue(gpuSpoofDevice, forKey: "D3DM_DEVICE_ID")
                wineEnv.updateValue(gpuSpoofName, forKey: "D3DM_DEVICE_DESCRIPTION")
            }
        }

        // MARK: - DLL Override 策略（按渲染引擎和游戏类型）
        // DXVK 已经设置了自己的 WINEDLLOVERRIDES，跳过 D3DMetal 路径
        guard !dxvk else { return }

        let useNativeD3DMetal: Bool
        switch dllOverridePolicy {
        case .auto:
            // D3DMetal 引擎 + 非 Chromium 游戏 → 用 native D3DMetal DLL
            useNativeD3DMetal = (wineEngine == .d3dmetal) && !isChromiumGame
        case .forceNative:
            useNativeD3DMetal = true
        case .forceBuiltin:
            useNativeD3DMetal = false
        }

        if useNativeD3DMetal {
            // D3DMetal 直通：DX→D3DMetal→Metal（2层翻译，最佳性能）
            // 系统级 GPTK 未安装时，D3D12 无法工作（libd3dshared.dylib 内部需要系统路径），
            // 仅启用 D3D11/DXGI 的 native override，d3d12 设为禁用避免崩溃
            let d3dOverride: String
            if D3DMetal.isSystemGPTKInstalled() {
                d3dOverride = "d3d11,d3d12,dxgi=n,b"
            } else {
                d3dOverride = "d3d11,dxgi=n,b;d3d12="
            }
            if let existing = wineEnv["WINEDLLOVERRIDES"], !existing.isEmpty {
                wineEnv["WINEDLLOVERRIDES"] = existing + ";" + d3dOverride
            } else {
                wineEnv["WINEDLLOVERRIDES"] = d3dOverride
            }
        } else if isChromiumGame || dllOverridePolicy == .forceBuiltin {
            // Chromium 游戏或用户/崩溃恢复强制 builtin：使用 Wine 内置 DLL
            let d3dOverride = "d3d11,d3d12,dxgi=b"
            if let existing = wineEnv["WINEDLLOVERRIDES"], !existing.isEmpty {
                wineEnv["WINEDLLOVERRIDES"] = existing + ";" + d3dOverride
            } else {
                wineEnv["WINEDLLOVERRIDES"] = d3dOverride
            }
        } else if !D3DMetal.isAvailable() {
            // D3DMetal 未安装时，自动禁用 d3d12.dll
            if let existing = wineEnv["WINEDLLOVERRIDES"], !existing.isEmpty {
                wineEnv["WINEDLLOVERRIDES"] = existing + ";d3d12="
            } else {
                wineEnv["WINEDLLOVERRIDES"] = "d3d12="
            }
        }
    }
}
