//
//  CrashRecoveryManager.swift
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

/// 崩溃检测和自动恢复管理器
/// 当游戏在 CrossOver 引擎 + native D3D DLL override 下快速崩溃时，
/// 自动用降级配置重试，并保存可工作的配置
public enum CrashRecoveryManager {

    /// 快速崩溃判定阈值（秒）
    private static let crashThreshold: TimeInterval = 15.0

    /// 降级配置
    public struct FallbackConfig {
        public let dllOverridePolicy: DLLOverridePolicy
        public let description: String
    }

    /// 生成降级序列
    private static func fallbackSequence() -> [FallbackConfig] {
        [
            FallbackConfig(
                dllOverridePolicy: .auto,
                description: "自动模式（根据游戏类型）"
            ),
            FallbackConfig(
                dllOverridePolicy: .forceBuiltin,
                description: "兼容模式（Wine 内置 D3D）"
            )
        ]
    }

    /// 带崩溃恢复的游戏运行
    /// 仅在 CrossOver 引擎 + auto 策略时触发自动恢复
    /// - Parameters:
    ///   - args: 已处理好的启动参数（含 --disable-gpu 等性能参数）
    ///   - framework: 已检测好的游戏框架类型（含 NW.js/Electron 等）
    /// - Returns: 成功运行的策略（如果发生了降级），nil 表示首次就成功或无需恢复
    public static func runWithRecovery(
        program: Program, args: [String], framework: GameFramework
    ) async throws -> DLLOverridePolicy? {
        let bottle = program.bottle
        let arguments = args
        let environment = program.generateEnvironment()
        let gameFramework = framework

        let fallbacks = fallbackSequence()

        for (index, config) in fallbacks.enumerated() {
            Logger.wineKit.info(
                "启动尝试 \(index + 1)/\(fallbacks.count): \(config.description)"
            )

            let result = try await Wine.runProgram(
                at: program.url, args: arguments, bottle: bottle,
                environment: environment,
                dllOverridePolicy: config.dllOverridePolicy,
                gameFramework: gameFramework
            )

            let duration = result.endTime.timeIntervalSince(result.startTime)
            let isSuspectedCrash = duration < crashThreshold && result.terminationStatus != 0

            if isSuspectedCrash {
                Logger.wineKit.warning(
                    "疑似崩溃: \(duration)秒内退出, 状态码 \(result.terminationStatus)"
                )
                if index < fallbacks.count - 1 {
                    // 还有降级选项，等待 wineserver 完全退出后重试
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
            }

            // 正常运行或所有重试用尽
            if index > 0 && !isSuspectedCrash {
                // 降级后成功运行
                Logger.wineKit.info(
                    "降级成功: 使用 \(config.description) 正常运行"
                )
                return config.dllOverridePolicy
            }
            return nil
        }
        return nil
    }
}
