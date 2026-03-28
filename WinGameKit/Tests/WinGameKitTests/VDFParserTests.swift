//
//  VDFParserTests.swift
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

final class VDFParserTests: XCTestCase {

    // MARK: - 基本解析

    func testParseSimpleKeyValue() throws {
        let input = """
        "key1"  "value1"
        "key2"  "value2"
        """
        let result = try VDFParser.parse(input)
        XCTAssertEqual(result["key1"]?.stringValue, "value1")
        XCTAssertEqual(result["key2"]?.stringValue, "value2")
    }

    func testParseNestedBlock() throws {
        let input = """
        "outer"
        {
            "inner_key"  "inner_value"
        }
        """
        let result = try VDFParser.parse(input)
        let outer = result["outer"]?.dictionaryValue
        XCTAssertNotNil(outer)
        XCTAssertEqual(outer?["inner_key"]?.stringValue, "inner_value")
    }

    func testParseDeeplyNested() throws {
        let input = """
        "level1"
        {
            "level2"
            {
                "level3"  "deep_value"
            }
        }
        """
        let result = try VDFParser.parse(input)
        let deep = result["level1"]?["level2"]?["level3"]
        XCTAssertEqual(deep?.stringValue, "deep_value")
    }

    // MARK: - Steam libraryfolders.vdf 格式

    func testParseSteamLibraryFolders() throws {
        let input = """
        "libraryfolders"
        {
            "contentstatsid"    "-8820764536697498672"
            "0"
            {
                "path"    "C:\\\\Program Files (x86)\\\\Steam"
                "label"   ""
                "apps"
                {
                    "730"    "25438210048"
                    "440"    "18874368000"
                }
            }
            "1"
            {
                "path"    "D:\\\\SteamLibrary"
                "label"   "Games"
                "apps"
                {
                    "570"    "34359738368"
                }
            }
        }
        """
        let result = try VDFParser.parse(input)
        let folders = result["libraryfolders"]?.dictionaryValue
        XCTAssertNotNil(folders)

        // 检查 library 0
        let lib0 = folders?["0"]?.dictionaryValue
        XCTAssertEqual(lib0?["path"]?.stringValue, "C:\\Program Files (x86)\\Steam")

        // 检查 library 0 的 apps
        let apps0 = lib0?["apps"]?.dictionaryValue
        XCTAssertEqual(apps0?["730"]?.stringValue, "25438210048")
        XCTAssertEqual(apps0?["440"]?.stringValue, "18874368000")

        // 检查 library 1
        let lib1 = folders?["1"]?.dictionaryValue
        XCTAssertEqual(lib1?["path"]?.stringValue, "D:\\SteamLibrary")
        XCTAssertEqual(lib1?["label"]?.stringValue, "Games")
    }

    // MARK: - Steam appmanifest 格式

    func testParseAppManifest() throws {
        let input = """
        "AppState"
        {
            "appid"       "730"
            "Universe"    "1"
            "name"        "Counter-Strike 2"
            "installdir"  "Counter-Strike Global Offensive"
            "StateFlags"  "4"
        }
        """
        let result = try VDFParser.parse(input)
        let appState = result["AppState"]?.dictionaryValue
        XCTAssertNotNil(appState)
        XCTAssertEqual(appState?["appid"]?.stringValue, "730")
        XCTAssertEqual(appState?["name"]?.stringValue, "Counter-Strike 2")
        XCTAssertEqual(appState?["installdir"]?.stringValue, "Counter-Strike Global Offensive")
    }

    // MARK: - 转义字符

    func testParseEscapedCharacters() throws {
        let input = """
        "path"  "C:\\\\Users\\\\test\\\\Documents"
        "tab"   "hello\\tworld"
        "newline" "line1\\nline2"
        "quote" "say \\"hello\\""
        """
        let result = try VDFParser.parse(input)
        XCTAssertEqual(result["path"]?.stringValue, "C:\\Users\\test\\Documents")
        XCTAssertEqual(result["tab"]?.stringValue, "hello\tworld")
        XCTAssertEqual(result["newline"]?.stringValue, "line1\nline2")
        XCTAssertEqual(result["quote"]?.stringValue, "say \"hello\"")
    }

    // MARK: - 注释处理

    func testParseWithComments() throws {
        let input = """
        // 这是注释
        "key1"  "value1"
        // 另一个注释
        "key2"  "value2"
        """
        let result = try VDFParser.parse(input)
        XCTAssertEqual(result["key1"]?.stringValue, "value1")
        XCTAssertEqual(result["key2"]?.stringValue, "value2")
    }

    // MARK: - 边界情况

    func testParseEmptyDictionary() throws {
        let input = """
        "empty"
        {
        }
        """
        let result = try VDFParser.parse(input)
        let empty = result["empty"]?.dictionaryValue
        XCTAssertNotNil(empty)
        XCTAssertTrue(empty?.isEmpty ?? false)
    }

    func testParseEmptyString() throws {
        let input = """
        "key"  ""
        """
        let result = try VDFParser.parse(input)
        XCTAssertEqual(result["key"]?.stringValue, "")
    }

    func testParseEmptyInput() throws {
        let result = try VDFParser.parse("")
        XCTAssertNotNil(result.dictionaryValue)
        XCTAssertTrue(result.dictionaryValue?.isEmpty ?? false)
    }

    // MARK: - 错误处理

    func testUnexpectedEndOfInput() {
        let input = """
        "key"
        {
        """
        XCTAssertThrowsError(try VDFParser.parse(input)) { error in
            XCTAssertEqual(error as? VDFParser.VDFError, .unexpectedEndOfInput)
        }
    }

    func testMissingQuote() {
        let input = """
        key  "value"
        """
        XCTAssertThrowsError(try VDFParser.parse(input)) { error in
            XCTAssertEqual(error as? VDFParser.VDFError, .expectedQuote)
        }
    }
}
