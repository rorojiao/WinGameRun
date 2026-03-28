//
//  D3DMetalTests.swift
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

final class D3DMetalTests: XCTestCase {

    func testSearchPathsContainSystemLocations() {
        let paths = D3DMetal.searchPaths
        // 验证系统级 GPTK 安装路径都在搜索列表中
        XCTAssertTrue(paths.contains("/Library/Apple/usr/lib/d3d/"))
        XCTAssertTrue(paths.contains("/usr/local/lib/d3d/"))
        XCTAssertTrue(paths.contains("/usr/local/opt/game-porting-toolkit/"))
    }

    func testSearchPathsContainAppBundledPath() {
        let paths = D3DMetal.searchPaths
        // 验证 App 内置路径在搜索列表中（优先级最高）
        XCTAssertTrue(paths[0].contains("D3DMetal.framework"))
        XCTAssertTrue(paths[0].contains("Libraries"))
    }

    func testIsAvailableReturnsConsistentResult() {
        let available = D3DMetal.isAvailable()
        let path = D3DMetal.installedPath()
        XCTAssertEqual(available, path != nil)
    }

    func testDetectedVersionConsistency() {
        if D3DMetal.isAvailable() {
            XCTAssertNotNil(D3DMetal.detectedVersion())
        } else {
            XCTAssertNil(D3DMetal.detectedVersion())
        }
    }

    func testGPTKDMGURL() {
        XCTAssertNotNil(D3DMetal.gptkDMGURL)
        XCTAssertTrue(D3DMetal.gptkDMGURL.absoluteString.contains("github.com"))
    }
}
