//
//  SteamGame.swift
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

/// Steam 游戏信息模型
public struct SteamGame: Identifiable, Codable, Sendable, Hashable {
    public let appId: String
    public let name: String
    public let installDir: String

    public var id: String { appId }

    public init(appId: String, name: String, installDir: String) {
        self.appId = appId
        self.name = name
        self.installDir = installDir
    }
}
