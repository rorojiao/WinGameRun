// swift-tools-version: 5.9
//
//  PortableExecutable.swift
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

import PackageDescription

let package = Package(
    name: "WinGameKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WinGameKit",
            targets: ["WinGameKit"]
        )
    ],
    dependencies: [
      .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "WinGameKit",
            dependencies: ["SemanticVersion"]
        ),
        .testTarget(
            name: "WinGameKitTests",
            dependencies: ["WinGameKit"]
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
