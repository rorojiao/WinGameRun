//
//  VDFParser.swift
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

/// Valve Data Format (VDF/KeyValues) 解析器
/// 解析 Steam 使用的 KeyValue 格式配置文件（如 libraryfolders.vdf）
public enum VDFParser {

    public enum VDFError: Error, Equatable {
        case unexpectedEndOfInput
        case expectedQuote
        case expectedOpenBrace
        case unexpectedCharacter(Character)
    }

    /// 解析后的 VDF 节点
    public indirect enum VDFNode: Equatable, Sendable {
        case string(String)
        case dictionary([String: VDFNode])

        public var stringValue: String? {
            if case .string(let value) = self { return value }
            return nil
        }

        public var dictionaryValue: [String: VDFNode]? {
            if case .dictionary(let dict) = self { return dict }
            return nil
        }

        public subscript(key: String) -> VDFNode? {
            dictionaryValue?[key]
        }
    }

    /// 解析 VDF 格式字符串
    public static func parse(_ input: String) throws -> VDFNode {
        var index = input.startIndex
        skipWhitespaceAndComments(input, &index)

        // 顶层可以是一个 "key" { ... } 对，或者直接是 { ... } 块
        if index < input.endIndex && input[index] == "{" {
            return try parseDictionary(input, &index)
        }

        // 否则读取顶层 key-value 对
        var result: [String: VDFNode] = [:]
        while index < input.endIndex {
            skipWhitespaceAndComments(input, &index)
            guard index < input.endIndex else { break }
            if input[index] == "}" { break }

            let key = try parseQuotedString(input, &index)
            skipWhitespaceAndComments(input, &index)
            guard index < input.endIndex else {
                throw VDFError.unexpectedEndOfInput
            }

            if input[index] == "{" {
                result[key] = try parseDictionary(input, &index)
            } else {
                result[key] = .string(try parseQuotedString(input, &index))
            }
        }
        return .dictionary(result)
    }

    /// 解析 VDF 格式文件
    public static func parseFile(at url: URL) throws -> VDFNode {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
    }

    // MARK: - 内部解析方法

    private static func parseDictionary(
        _ input: String, _ index: inout String.Index
    ) throws -> VDFNode {
        guard index < input.endIndex && input[index] == "{" else {
            throw VDFError.expectedOpenBrace
        }
        index = input.index(after: index)

        var result: [String: VDFNode] = [:]

        while true {
            skipWhitespaceAndComments(input, &index)
            guard index < input.endIndex else {
                throw VDFError.unexpectedEndOfInput
            }

            if input[index] == "}" {
                index = input.index(after: index)
                return .dictionary(result)
            }

            let key = try parseQuotedString(input, &index)
            skipWhitespaceAndComments(input, &index)
            guard index < input.endIndex else {
                throw VDFError.unexpectedEndOfInput
            }

            if input[index] == "{" {
                result[key] = try parseDictionary(input, &index)
            } else {
                result[key] = .string(try parseQuotedString(input, &index))
            }
        }
    }

    private static func parseQuotedString(
        _ input: String, _ index: inout String.Index
    ) throws -> String {
        guard index < input.endIndex && input[index] == "\"" else {
            throw VDFError.expectedQuote
        }
        index = input.index(after: index)

        var result = ""
        while index < input.endIndex {
            let char = input[index]
            if char == "\\" {
                // 转义字符
                index = input.index(after: index)
                guard index < input.endIndex else {
                    throw VDFError.unexpectedEndOfInput
                }
                let escaped = input[index]
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: result.append("\\"); result.append(escaped)
                }
            } else if char == "\"" {
                index = input.index(after: index)
                return result
            } else {
                result.append(char)
            }
            index = input.index(after: index)
        }
        throw VDFError.unexpectedEndOfInput
    }

    private static func skipWhitespaceAndComments(
        _ input: String, _ index: inout String.Index
    ) {
        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace || char.isNewline {
                index = input.index(after: index)
            } else if char == "/" {
                let next = input.index(after: index)
                if next < input.endIndex && input[next] == "/" {
                    // 行注释：跳到行末
                    while index < input.endIndex && input[index] != "\n" {
                        index = input.index(after: index)
                    }
                } else {
                    break
                }
            } else {
                break
            }
        }
    }
}
