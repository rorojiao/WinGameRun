//
//  SteamGameTests.swift
//  WinGameKitTests
//
//  This file is part of WinGameRun.
//
//  WinGameRun is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//

import XCTest
@testable import WinGameKit

final class SteamGameTests: XCTestCase {

    func testSteamGameInit() {
        let game = SteamGame(appId: "730", name: "Counter-Strike 2", installDir: "Counter-Strike Global Offensive")
        XCTAssertEqual(game.appId, "730")
        XCTAssertEqual(game.name, "Counter-Strike 2")
        XCTAssertEqual(game.installDir, "Counter-Strike Global Offensive")
        XCTAssertEqual(game.id, "730")
    }

    func testSteamGameCodable() throws {
        let game = SteamGame(appId: "440", name: "Team Fortress 2", installDir: "Team Fortress 2")
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(SteamGame.self, from: data)
        XCTAssertEqual(game, decoded)
    }

    func testSteamGameHashable() {
        let game1 = SteamGame(appId: "730", name: "CS2", installDir: "cs2")
        let game2 = SteamGame(appId: "730", name: "CS2", installDir: "cs2")
        let game3 = SteamGame(appId: "440", name: "TF2", installDir: "tf2")

        XCTAssertEqual(game1, game2)
        XCTAssertNotEqual(game1, game3)

        let set: Set<SteamGame> = [game1, game2, game3]
        XCTAssertEqual(set.count, 2)
    }
}
